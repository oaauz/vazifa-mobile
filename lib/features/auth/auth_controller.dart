import 'dart:async';

import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/account_switch.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers/core_providers.dart';
import '../../core/push/push_service.dart';
import '../../core/remote_config/internal_tester.dart';
import '../../core/restart_widget.dart';
import '../../core/router/home_area_pref.dart';
import '../../core/telemetry/app_open_session.dart';
import '../../core/telemetry/crash_reporter.dart';
import '../../data/models/auth_user.dart';
import '../../data/repositories/auth_repository.dart';
import 'auth_error_l10n.dart';
import 'auth_state.dart';

final authControllerProvider =
    NotifierProvider<AuthController, AuthSessionState>(AuthController.new);

// ⚠️ Foydalanuvchi: "otp koddan keyin splash ekransiz ishga tushirsak
// bo'ladimi?" — `verifyOtp()`/`loginWithPassword()` `restartApp()`ni
// chaqirganda YANGI `AuthController.build()` odatiy holda `_restore()`ni
// (xavfsiz xotiradan token/foydalanuvchini QAYTADAN o'qish, kamida
// `_minSplashDuration` kutish) ishga tushiradi — bu yerda esa NATIJA
// ALLAQACHON MA'LUM (`verifyOtp()` shu zahoti qaytargan `AuthUser`) va
// tokenlar ALLAQACHON saqlangan, shu sababli qayta o'qish + sun'iy
// kechikish FOYDASIZ vaqt yo'qotish, faqat splash "yaltirab o'tishi"ga
// olib keladi. Modul darajasidagi ushbu o'zgaruvchi — restart
// chegarasidan (butunlay yangi provider daraxti) natijani "olib o'tish"
// uchun yagona yo'l (Riverpod provider'lar buzilib qayta quriladi, oddiy
// konstruktor argumenti yo'q). Faqat LOGIN uchun — logout ATAYLAB bunda
// ishlatilmaydi (foydalanuvchi qarori: "logoutdan keyin splash chiqishi
// zarari yo'q, loginda chiqmasa bo'ldi").
AuthUser? _fastLoginUser;

/// `_fastLoginUser`dagi bilan bir xil restart-chegarasidan o'tkazish
/// naqshi — sessiya tugashi haqidagi xabarni (`onSessionExpired`) endi
/// `_hardReset()` orqali kelgan restart'dan KEYIN ham ko'rsatish uchun.
String? _pendingUnauthMessage;

class AuthController extends Notifier<AuthSessionState> {
  late final AuthRepository _repo;

  @override
  AuthSessionState build() {
    _repo = ref.watch(authRepositoryProvider);
    // 401 bilan refresh yiqilib, sessiya haqiqatan o'lganda interceptor
    // shu yerga qaytadi — offline'da bu HECH QACHON chaqirilmaydi
    // (reja §7: tarmoq xatosi ≠ chiqib ketish).
    // ⚠️ Topilma: avval bu yerda faqat `state`ni o'zgartirar edi —
    // tokenlar tozalanardi-yu, lokal DB'da oldingi xodimning navbati/
    // qoralamalari/media'si qolib ketardi.
    //
    // ⚠️ Ko'rik topilmasi (birinchi tuzatish HADDAN OSHIB ketgan edi):
    // bu yerda `wipeAll()` chaqirish sessiya tugashi bilanoq XUDDI O'SHA
    // xodimning yuborilmagan ishini yo'q qilardi — holbuki sessiya
    // tugashi odatiy hodisa (uzoq tanaffus, token rotatsiyasi, deploy).
    // Haqiqiy xavf — QURILMADA HISOB ALMASHISHI — endi aniq o'z joyida,
    // kirish paytida hal qilinadi (`account_switch.dart`). Bu yerda esa
    // faqat sessiya yopiladi, MA'LUMOTGA TEGILMAYDI.
    ref.watch(authSessionBridgeProvider).onExpired = () {
      unawaited(_endSession(message: 'Sessiya muddati tugadi — qayta kiring'));
    };
    final fastUser = _fastLoginUser;
    if (fastUser != null) {
      _fastLoginUser = null;
      // Native splash shu bosqichda allaqachon olib tashlangan (ilk
      // ochilishda) — bu yo'lda umuman qayta chaqirilmaydi, chunki bu
      // holat FAQAT restart'dan (allaqachon ishlab turgan ilova ichida)
      // keladi.
      return AuthAuthenticated(fastUser);
    }
    final pendingMessage = _pendingUnauthMessage;
    if (pendingMessage != null) {
      _pendingUnauthMessage = null;
      return AuthUnauthenticated(message: pendingMessage);
    }
    _restore();
    return const AuthChecking();
  }

  // ⚠️ `restoreSession()` (secure storage'dan token o'qish) odatda bir
  // necha millisekundda tugaydi — `FlutterNativeSplash.remove()` shu
  // zahoti chaqirilsa, brend belgisi ko'rishga ulgurmay chaqib o'tib
  // ketadi. Minimal ko'rsatish muddati shu uchun bor. ⚠️ Lekin
  // `addPostFrameCallback`ga bog'lab qo'yish (avvalgi versiya) — agar
  // birinchi ekran (masalan Vazifalar) o'zining ma'lumotini yuklab
  // bo'lguncha frame "og'irlashsa" — splash NOANIQ muddatga cho'zilib
  // ketishi mumkin edi ("2-3 soniyadan uzoq qolib ketdi" — foydalanuvchi
  // izohi). Endi ikkalasi ham QAT'IY chegaralangan: kamida
  // `_minSplashDuration`, ko'pi bilan `_maxRestoreWait` (sessiya
  // tekshiruvi qanchalik sekin bo'lishidan qat'i nazar) — va olib
  // tashlash HECH QANDAY kadrni kutmasdan, darhol chaqiriladi.
  static const _minSplashDuration = Duration(milliseconds: 900);
  // ⚠️ Foydalanuvchi topilmasi: "tez-tez ishlatmaydigan mijoz avtomatik
  // chiqib ketyapti" — bu SHU chegara ILGARI xavfsiz saqlashning o'z
  // ichki chegarasidan (`SecureTokenStorage._ioTimeout`, 5s har o'qish)
  // QISQAROQ (2s) edi. Uzoq ishlatilmagan ilovada qurilmaning xavfsiz
  // saqlash xizmati (Keychain/Keystore) "sovuq" bo'lib, BIRINCHI
  // murojaat odatdagidan sekinroq bo'lishi mumkin — bunda bu tashqi
  // chegara ICHKI (haqiqatan chidamli, xato bo'lsa ham ma'lumotni
  // O'CHIRMAYDIGAN) chegaraga yetib borishdan OLDIN ishga tushib,
  // ma'lumot aslida yo'qolmagan bo'lsa ham "sessiya yo'q" deb
  // ko'rsatardi (`onTimeout: () => null` pastda). Endi ICHKI
  // chegaradan KATTA — shu sinfdagi soxta-logout endi imkonsiz
  // (haqiqiy o'qish xatosi/vaqt tugashisiz).
  static const _maxRestoreWait = Duration(seconds: 12);

  Future<void> _restore() async {
    final started = DateTime.now();
    try {
      final user = await _repo.restoreSession().timeout(
        _maxRestoreWait,
        onTimeout: () => null,
      );
      state = user != null
          ? AuthAuthenticated(user)
          : const AuthUnauthenticated();
      // ⚠️ Ikkinchi ko'rik topilmasi: `last_user_id` FAQAT shu build'da
      // paydo bo'ldi, ya'ni ALLAQACHON o'rnatilgan ilovalarda u bo'sh.
      // Natijada yangilanishdan keyingi BIRINCHI hisob almashishi
      // "avvalgi foydalanuvchi noma'lum" deb o'tkazib yuborilardi —
      // ya'ni himoya butun mavjud parkda ishlamasdi. Sessiya tiklangan
      // zahoti egasi yozib qo'yiladi (bu — ta'rifi bo'yicha oxirgi
      // kirgan foydalanuvchi), shu bilan bo'shliq yopiladi va HECH
      // KIMNING ishi o'chirilmaydi.
      // ⚠️ `IfAbsent` — mavjud qiymatga TEGMAYDI (izoh:
      // `account_switch.dart`). Aks holda yiqilgan tozalashni qayta
      // urinish imkoniyati yo'qolardi.
      if (user != null) await AccountSwitch.rememberUserIfAbsent(user.id);
    } catch (_) {
      // Native splash abadiy osilib qolmasligi uchun — kutilmagan xatoda
      // ham holatni albatta hal qilamiz (kirish ekraniga tushadi).
      state = const AuthUnauthenticated();
    } finally {
      final elapsed = DateTime.now().difference(started);
      if (elapsed < _minSplashDuration) {
        await Future.delayed(_minSplashDuration - elapsed);
      }
      FlutterNativeSplash.remove();
      // "Mobil so'rov narxi" — sovuq start shu yerda "tayyor" hisoblanadi.
      AppOpenSession.markReady();
    }
  }

  // ⚠️ Avval bu holatni `state`ga yozib qo'yardi, ekranlar esa `ref.listen`
  // orqali global holatni kuzatib navigatsiya qilardi — bu OTP ekranidagi
  // "Qayta yuborish" (`resendOtp` → shu metodni qayta chaqiradi) ham xuddi
  // shu `AuthOtpSent` holatini qayta chiqarganini, va telefon ekrani HALI
  // HAM ostda o'chirilmagan holda tinglab turganini anglatardi — natijada
  // har "Qayta yuborish"da telefon ekrani buni "yangi so'rov" deb bilib,
  // OTP ekranini YANA BIR MARTA navbatga qo'yardi (foydalanuvchi izohi:
  // "4 marta resend — 4 marta back kerak"). Endi natija to'g'ridan-to'g'ri
  // `bool` sifatida qaytariladi — chaqiruvchi ANIQ shu chaqiruv uchun bir
  // marta reaksiya qiladi, global tinglovchi shart emas.
  Future<bool> requestOtp(String phoneE164) async {
    // ⚠️ Audit topilmasi: tez ketma-ket ikki marta chaqirilsa (masalan
    // matn maydonida `onFieldSubmitted` tugma o'chirilishidan OLDIN ikki
    // marta ishga tushsa), avval ikkala so'rov ham parallel yuborilardi.
    // `_endSession`dagi bilan bir xil naqsh — allaqachon jarayonda bo'lsa
    // (`state is AuthSubmitting`) hech narsa qilinmaydi.
    if (state is AuthSubmitting) return false;
    state = const AuthSubmitting();
    try {
      await _repo.requestOtp(phoneE164);
      state = AuthOtpSent(phoneE164: phoneE164);
      return true;
    } on ApiException catch (e) {
      state = AuthUnauthenticated(
        message: e.message,
        code: e.code,
        kind: e.kind,
        statusCode: e.statusCode,
      );
      return false;
    } catch (e) {
      // ⚠️ Senior audit topilmasi: faqat `ApiException` ushlanardi —
      // kutilmagan tur (masalan server javobi noto'g'ri formatda bo'lsa
      // `AuthTokenPair.fromJson`dagi `TypeError`) bu yerdan o'tib ketib,
      // `state` abadiy `AuthSubmitting`da qolib ketardi ("SMS kod"
      // tugmasi cheksiz aylanardi — foydalanuvchi izohi). Endi HAR
      // qanday xato holatni albatta hal qiladi.
      //
      // ⚠️ Topilma: `message: e.toString()` — Dio xatosining to'liq
      // URL/tafsilotlari ekranda ko'rinishi mumkin edi. Haqiqiy xato
      // endi hisobotga yoziladi, foydalanuvchi esa xavfsiz umumiy
      // xabar ko'radi (`kClientUnexpectedErrorCode` → `auth_error_l10n.dart`).
      CrashReporter.report(e, StackTrace.current, zone: 'auth:requestOtp');
      state = AuthUnauthenticated(
        message: e.toString(),
        code: kClientUnexpectedErrorCode,
      );
      return false;
    }
  }

  Future<void> verifyOtp(String phoneE164, String code) async {
    // ⚠️ `requestOtp`dagi bilan bir xil topilma/naqsh — ikki marta
    // ketma-ket bosilib qolsa ikkinchi chaqiruv jimgina e'tiborsiz
    // qoldiriladi.
    if (state is AuthSubmitting) return;
    state = const AuthSubmitting();
    try {
      final user = await _repo.verifyOtp(phoneE164, code);
      await _wipeIfAccountSwitched(user);
      // ⚠️ `internal_tester.dart` — `restartApp()`dan OLDIN tugashi
      // shart, aks holda yangi provider daraxti eski (noto'g'ri) qiymat
      // bilan quriladi. `phoneE164` (kirish maydoni) EMAS, `user.phone`
      // (backend tasdiqlagan) — izoh o'sha faylda.
      await markInternalTesterFromLogin(user.phone);
      // ⚠️ `state = AuthAuthenticated(user)` o'rniga — foydalanuvchi:
      // "login muvaffaqiyatli bo'lsa hamma narsa to'liq yangidan
      // ochilgandek bo'lishi kerak". Oddiy holat almashtirish
      // YETARLI EMAS (`restart_widget.dart`dagi izohga qarang) — butun
      // ilova provider daraxti qayta quriladi. Natija ALLAQACHON MA'LUM
      // (yuqoridagi `user`) — shu sabab `_fastLoginUser` orqali yangi
      // `AuthController`ga to'g'ridan-to'g'ri uzatiladi, u splash/qayta
      // o'qishsiz darhol `AuthAuthenticated` holatida boshlanadi (izoh:
      // yuqorida, `_fastLoginUser` ta'rifi).
      _fastLoginUser = user;
      restartApp();
    } on ApiException catch (e) {
      state = AuthOtpSent(phoneE164: phoneE164, error: e.message, code: e.code);
    } catch (e) {
      // ⚠️ Yuqoridagi `requestOtp`dagi bilan bir xil xato sinfi — bu yerda
      // AYNAN shu narsa "SMS kod kiritilgandan keyin abadiy yuklanish"
      // holatiga olib kelgan edi. Xom matn endi faqat hisobotga.
      CrashReporter.report(e, StackTrace.current, zone: 'auth:verifyOtp');
      state = AuthOtpSent(
        phoneE164: phoneE164,
        error: e.toString(),
        code: kClientUnexpectedErrorCode,
      );
    }
  }

  Future<bool> resendOtp(String phoneE164) => requestOtp(phoneE164);

  void backToPhoneEntry() => state = const AuthUnauthenticated();

  // ⚠️ Har bir kirish ekrani (telefon/parol) GLOBAL `authControllerProvider`
  // holatini o'qiydi — parol ekraniga telefon ekranidagi MUVAFFAQIYATSIZ
  // urinishdan keyin o'tilsa, avvalgi xato xabari HALI HAM `state`da turgani
  // uchun yangi ekranda hech narsa qilinmasa ham darhol ko'rinib qolardi
  // (foydalanuvchi izohi: "bu sahifadagi xatolik hech narsa qilmasa ham
  // turibdi"). Har ekran o'zi ochilganda shu metodni chaqirib eskisini
  // tozalaydi.
  void clearError() {
    if (state is AuthUnauthenticated) state = const AuthUnauthenticated();
  }

  Future<void> loginWithPassword(String login, String password) async {
    // ⚠️ `requestOtp`/`verifyOtp`dagi bilan bir xil topilma/naqsh.
    if (state is AuthSubmitting) return;
    state = const AuthSubmitting();
    try {
      final user = await _repo.loginWithPassword(login, password);
      await _wipeIfAccountSwitched(user);
      // ⚠️ `verifyOtp()`dagi bilan bir xil ikkita sabab (tekshiruvchi
      // bayrog'i + `_fastLoginUser`) — yuqoridagi izohlarga qarang.
      // `login` (kirish maydoni, username HAM bo'lishi mumkin) EMAS,
      // `user.phone` (backend tasdiqlagan haqiqiy raqam).
      await markInternalTesterFromLogin(user.phone);
      _fastLoginUser = user;
      restartApp();
    } on ApiException catch (e) {
      state = AuthUnauthenticated(message: e.message, code: e.code);
    } catch (e) {
      CrashReporter.report(
        e,
        StackTrace.current,
        zone: 'auth:loginWithPassword',
      );
      state = AuthUnauthenticated(
        message: e.toString(),
        code: kClientUnexpectedErrorCode,
      );
    }
  }

  // ⚠️ Foydalanuvchi: "logout qilganda avvalgi datalarni to'liq tozalab
  // yuborish kerak ... ilova xuddi yangidan ochilgandek bo'lishi kerak."
  // Avval FAQAT `_repo.logout()` (auth tokenlarini xavfsiz xotiradan
  // tozalash) chaqirilib, `state = AuthUnauthenticated()` qo'yilardi —
  // mahalliy DB (oflayn navbat, qoralamalar) va boshqa BARCHA provider
  // (vazifalar, statistika, vazifalar) xotirada ESKI foydalanuvchining
  // ma'lumotini saqlab qolaverardi. Endi: mahalliy DB ham butunlay
  // tozalanadi (`AppDatabase.wipeAll`), SO'NGRA butun ilova provider
  // daraxti noldan qayta quriladi (`restart_widget.dart`).
  /// ⚠️ Ko'rik topilmasi bo'yicha dizayn: qurilmada HISOB ALMASHGANDA
  /// (A xodim chiqib, B xodim kirganda) oldingi xodimning oflayn
  /// navbati/qoralamalari/media'si tozalanadi — aks holda ular YANGI
  /// xodimning tokeni bilan serverga yuborilib, ma'lumot chalkashardi.
  /// XUDDI O'SHA xodim qayta kirsa — HECH NARSA o'chirilmaydi (izoh:
  /// `account_switch.dart`).
  Future<void> _wipeIfAccountSwitched(AuthUser user) async {
    try {
      if (await AccountSwitch.isDifferentUserThanLast(user.id)) {
        await Future(() async {
          await ref.read(appDatabaseProvider).wipeAll();
          await ref.read(mediaQueueServiceProvider).purgeAllFiles();
          // ⚠️ `home_area_pref.dart` — qurilma ochiq (`logout()`siz)
          // hisob almashtirilganda ham oldingi foydalanuvchining "oxirgi
          // tarmog'i" (masalan owner uchun Boshqaruv) yangisiga
          // yopishmasin.
          await clearHomeAreaPref();
        }).timeout(const Duration(seconds: 5));
      }
      // ⚠️ FAQAT tozalash muvaffaqiyatli tugagach eslab qolinadi — aks
      // holda yiqilgan tozalash "bajarilgan" deb belgilanib, oldingi
      // xodimning ma'lumoti yangisi ostida qolib ketardi.
      await AccountSwitch.rememberUser(user.id);
    } catch (e, st) {
      // Best-effort — kirishni bloklamaydi, lekin JIM ham qolmaydi:
      // tozalanmagan holat ma'lumot chalkashuviga olib kelishi mumkin.
      // `rememberUser` chaqirilmagani uchun keyingi kirishda QAYTA
      // urinib ko'riladi.
      CrashReporter.report(e, st, zone: 'auth:accountSwitchWipe');
    }
  }

  /// Foydalanuvchining ANIQ niyati — lokal ma'lumot ham butunlay
  /// tozalanadi ("ilova xuddi yangidan ochilgandek bo'lsin").
  Future<void> logout() => _endSession(serverRevoke: true, wipeLocalData: true);

  /// ⚠️ Ko'rik topilmasi: bu bayroq avval yo'q edi — `onSessionExpired`
  /// ham `logout` bilan bir xil yo'ldan o'tib, sessiya tugashi bilanoq
  /// XUDDI O'SHA xodimning yuborilmagan ishini yo'q qilardi. Endi lokal
  /// tozalash faqat ANIQ so'ralganda (`logout`) yoki qurilmada HISOB
  /// ALMASHGANDA (`_wipeLocalData`, kirish paytida) bajariladi.
  ///
  /// Tartib ATAYLAB shunday: (1) tarmoqqa bog'liq, TOKEN HALI TIRIK
  /// paytda bajarilishi shart bo'lgan ishlar (server-side revoke, push
  /// tokenini bekor qilish) — o'zining QISQA, alohida chegarasi bilan;
  /// (2) SO'NGRA lokal ishlar — bu HAR DOIM to'liq o'z byudjetini oladi,
  /// tarmoq sekinligidan qat'i nazar (⚠️ topilma: avval bittagina umumiy
  /// 5s chegara bor edi, tarmoq chaqiruvi BIRINCHI bo'lgani uchun butun
  /// byudjetni yeb qo'yishi mumkin edi — natijada tozalash umuman
  /// ishlamay, "chiqish" ko'rinishda ishlagandek bo'lib, tokenlar
  /// Keychain'da qolib ketardi).
  Future<void> _endSession({
    bool serverRevoke = false,
    bool wipeLocalData = false,
    String? message,
  }) async {
    // ⚠️ Ko'rik topilmasi: `onExpired` HAR BIR 401 beruvchi so'rov uchun
    // chaqiriladi — parallel N ta so'rov N ta bir vaqtda ishlaydigan
    // reset boshlardi. Birinchisi `restartApp()` bilan butun
    // `ProviderScope`ni yo'q qilgach, qolganlari YO'Q QILINGAN
    // konteynerda `ref.read` qilib, ushlanmagan zona xatosiga aylanar va
    // yangi qurilgan kirish ekranini yana qayta yuklab yuborardi.
    // ⚠️ To'rtinchi ko'rik topilmasi: guard AVVAL SHARTSIZ edi. Fonda
    // 401 kelib `onExpired` → `_endSession(wipeLocalData: false)` ishga
    // tushgan paytda foydalanuvchi "Chiqish" bossa, `logout()` JIMGINA
    // qaytib ketardi: tokenlar tozalangani uchun chiqqandek KO'RINADI,
    // lekin lokal ma'lumot tozalanmaydi va server sessiyasi/push
    // tokeni bekor qilinmaydi. Endi "kuchliroq" so'rov (lokal tozalash
    // yoki server revoke talab qiladigani) o'tishi mumkin.
    final needsMoreThanInflight =
        (wipeLocalData && !_inflightWipedLocalData) ||
        (serverRevoke && !_inflightServerRevoked);
    if (_endingSession && !needsMoreThanInflight) return;
    _endingSession = true;
    _inflightWipedLocalData = _inflightWipedLocalData || wipeLocalData;
    _inflightServerRevoked = _inflightServerRevoked || serverRevoke;
    // ⚠️ Ikkinchi ko'rik topilmasi: bayroq AVVAL `restartApp()`dan keyin
    // `false`ga qaytarilardi — bu esa uni qo'shishdan maqsad bo'lgan
    // teshikni qaytadan ochardi. `RestartWidget` eski `ProviderScope`ni
    // darhol emas, animatsiya bilan (~280ms) yo'q qiladi, eski
    // konteynerdagi Dio so'rovlari esa bekor qilinmaydi (15-20s
    // timeout) — ulardan biri restart'dan KEYIN 401 bersa, eski
    // `onExpired` yopilmasi hamon ESKI notifier'ga ishora qiladi va
    // bayroq bo'sh bo'lgani uchun ikkinchi marta ishga tushib,
    // yo'q qilingan konteynerda `ref.read` qilib, ushlanmagan zona
    // xatosini beradi. Sessiya bir marta yakunlangach, bu instansiya
    // uchun boshqa hech narsa qilish shart emas — bayroq QAYTARILMAYDI.
    //
    // Butun tana `try/catch` ichida: yo'q qilingan konteynerdan
    // `ref.read` `StateError` tashlaydi, chaqiruvchi esa `unawaited`.
    try {
      await _endSessionBody(
        serverRevoke: serverRevoke,
        wipeLocalData: wipeLocalData,
        message: message,
      );
    } catch (e, st) {
      CrashReporter.report(e, st, zone: 'auth:endSession');
      // ⚠️ To'rtinchi ko'rik topilmasi: xato bo'lganda bayroq `true`
      // holida qolib ketardi va `restartApp()` ham chaqirilmagan
      // bo'lardi — natijada instansiya TIRIK qolib, keyingi har bir
      // "Chiqish" bosishi butunlay JIM no-op bo'lardi (na xato, na
      // holat o'zgarishi). Restart bo'lmagan bo'lsa — qayta urinishga
      // ruxsat beramiz.
      if (!canRestartApp()) {
        _endingSession = false;
        _inflightWipedLocalData = false;
        _inflightServerRevoked = false;
      }
    }
  }

  Future<void> _endSessionBody({
    required bool serverRevoke,
    required bool wipeLocalData,
    String? message,
  }) async {
    final tokenStorage = ref.read(secureTokenStorageProvider);

    if (serverRevoke) {
      try {
        await Future(() async {
          // Push tokenini bekor qilish — sessiya hali tirik paytda,
          // aks holda so'rov autentifikatsiyasiz ketib 401'ga uchraydi.
          await ref.read(pushServiceProvider).unregisterCurrentToken();
          await _repo.logout();
        }).timeout(const Duration(seconds: 5));
      } catch (_) {
        // Best-effort — pastdagi lokal ishlar baribir davom etadi.
      }
    }

    try {
      await Future(() async {
        await tokenStorage.clearAuth();
        if (wipeLocalData) {
          await ref.read(appDatabaseProvider).wipeAll();
          await ref.read(mediaQueueServiceProvider).purgeAllFiles();
          // ⚠️ `home_area_pref.dart`dagi izohga qarang — "ilova xuddi
          // yangidan ochilgandek bo'lsin" niyati shu yerga ham tegishli:
          // keyingi hisob oldingi foydalanuvchining "oxirgi tarmog'i"ni
          // meros qilib olmasin.
          await clearHomeAreaPref();
        }
      }).timeout(const Duration(seconds: 5));
    } catch (_) {
      // Best-effort: foydalanuvchi "chiqolmay qoldim" holatida qolib
      // ketmasligi kerak.
    }

    // ⚠️ Topilma: `clearAuth()` yuqoridagi `timeout()` ichida vaqtida
    // tugamagan bo'lishi mumkin — bunda tokenlar Keychain'da QOLIB
    // ketadi, `restartApp()` esa baribir chaqirilib, `_restore()` ularni
    // topib foydalanuvchini SILAB qaytadan kiritib yuboradi ("chiqish"
    // ko'rinishda ishlagan, aslida ishlamagan). Restart'dan oldin oxirgi
    // marta tekshirib, qolgan bo'lsa qat'iy tozalanadi.
    try {
      if (await tokenStorage.readAccessToken() != null) {
        await tokenStorage.clearAuth();
      }
    } catch (_) {
      // Keychain o'qib bo'lmadi — pastdagi holat baribir qo'yiladi.
    }

    // ⚠️ To'rtinchi ko'rik topilmasi: xabar SHARTSIZ o'rnatilardi.
    // `restartApp()` esa `RestartWidget` o'rnatilmagan bo'lsa JIM
    // no-op — bunday holatda xabar iste'mol qilinmay qolib, KEYINROQ
    // butunlay aloqasiz qayta qurishda (masalan muvaffaqiyatli
    // kirishdan keyin) noto'g'ri "Sessiya muddati tugadi" bo'lib chiqib
    // qolardi. Restart bo'lmasa xabar kerak ham emas — pastdagi `state`
    // allaqachon shu ekranga qo'yilgan.
    if (message != null && canRestartApp()) _pendingUnauthMessage = message;
    // ⚠️ Ko'rik topilmasi: `restartApp()` — `RestartWidget` hali
    // o'rnatilmagan bo'lsa JIM no-op (`restart_widget.dart`). Faqat
    // `_pendingUnauthMessage`ga tayanilsa, foydalanuvchi `AuthChecking`
    // holatida `/splash`da abadiy qotib qolishi mumkin edi. Holatni shu
    // yerda ham aniq qo'yamiz — restart ishlasa, u baribir ustidan
    // yozadi.
    state = AuthUnauthenticated(message: message);
    restartApp();
  }

  bool _endingSession = false;

  /// Ishlab turgan/yakunlangan sessiya-yakuni QAYSI ishlarni bajardi —
  /// keyinroq kelgan "kuchliroq" so'rov (masalan sessiya tugashi ustiga
  /// qo'lda "Chiqish") jimgina yo'qolmasligi uchun.
  bool _inflightWipedLocalData = false;
  bool _inflightServerRevoked = false;
}
