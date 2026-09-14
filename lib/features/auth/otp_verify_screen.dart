import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/l10n/gen/app_localizations.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/auth_brand_header.dart';
import '../../core/widgets/auth_chrome.dart';
import '../../core/widgets/platform_button.dart';
import '../../core/widgets/platform_loading_indicator.dart';
import '../settings/settings_config_provider.dart';
import 'auth_controller.dart';
import 'auth_error_l10n.dart';
import 'auth_state.dart';

const _kOtpLength = 4;

class OtpVerifyScreen extends ConsumerStatefulWidget {
  const OtpVerifyScreen({super.key, required this.phoneE164});

  final String phoneE164;

  @override
  ConsumerState<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends ConsumerState<OtpVerifyScreen> {
  final _codeController = TextEditingController();
  final _codeFocusNode = FocusNode();
  bool _showError = false;

  // ⚠️ Avval "Qayta yuborish" istalgan vaqtda bosilishi mumkin edi —
  // backend'da `otp_resend_cooldown_seconds` (standart 60s) bor, lekin
  // klient buni HECH aks ettirmasdi (foydalanuvchi izohi). Bosilgach ham
  // hisoblash qayta boshlanmasdi. Endi ekran ochilishi bilan (kod
  // ALLAQACHON yuborilgan bo'lgani uchun) va har "Qayta yuborish"dan
  // keyin hisoblagich boshlanadi.
  //
  // ⚠️ Mobil audit topilmasi: bu qiymat qattiq 60s deb yozilgan edi,
  // lekin superadmin panelda o'zgartirilishi mumkin. Mos kelmasa server
  // cooldown oynasi ichida kelgan `requestOtp`ni JIMGINA rad etadi (SMS
  // yubormaydi, lekin baribir `{ok:true}` qaytaradi) — klient esa
  // "yuborildi" deb hisoblagichni qayta boshlab qo'yaveradi va
  // foydalanuvchi hech qachon kelmaydigan kodni kutib qoladi. Endi
  // haqiqiy qiymat `GET /config/app`dan (`appConfigProvider`) olinadi,
  // tarmoq xatosida standart 60s'ga qaytiladi.
  static const _defaultResendCooldown = 60;
  int _cooldownSeconds = _defaultResendCooldown;
  Timer? _cooldownTimer;
  int _secondsLeft = _defaultResendCooldown;
  bool _resending = false;

  @override
  void initState() {
    super.initState();
    _loadCooldownAndStart();
  }

  Future<void> _loadCooldownAndStart() async {
    try {
      final config = await ref.read(appConfigProvider.future);
      final parsed = int.tryParse(config['otpResendCooldownSeconds'] ?? '');
      if (parsed != null && parsed > 0) _cooldownSeconds = parsed;
    } catch (_) {
      // Konfiguratsiya kelmasa — standart 60s bilan davom etiladi
      // (avvalgi xatti-harakat, konservativ tomon).
    }
    if (!mounted) return;
    _startCooldown();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _secondsLeft = _cooldownSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  Future<void> _resend() async {
    selectionHaptic();
    if (_resending || _secondsLeft > 0) return;
    setState(() => _resending = true);
    final ok = await ref
        .read(authControllerProvider.notifier)
        .resendOtp(widget.phoneE164);
    if (!mounted) return;
    setState(() => _resending = false);
    // ⚠️ Topilma: avval faqat MUVAFFAQIYATDA qayta boshlanardi — server
    // rad etsa (shu jumladan AYNAN rate-limit sababli) tugma darhol qayta
    // bosiladigan holatda qolib, foydalanuvchi cheklovga qarshi cheksiz
    // urinishi mumkin edi, ustiga xato hech qayerda ko'rsatilmasdi (bu
    // ekran faqat `AuthOtpSent.error`ni chizadi, `resendOtp`
    // muvaffaqiyatsizligi esa global holatni `AuthUnauthenticated`ga
    // o'zgartiradi — bu yerda umuman aks etmaydi). Endi natijadan qat'i
    // nazar cooldown qayta boshlanadi, muvaffaqiyatsizlikda esa toast.
    final failedState = ref.read(authControllerProvider);
    // ⚠️ Ko'rik topilmasi: cooldown SHARTSIZ boshlanardi — telefon
    // OFLAYN bo'lsa, server so'rovni umuman ko'rmagan bo'lsa ham
    // foydalanuvchi 60 soniya kutishga majbur bo'lardi.
    //
    // ⚠️ Ikkinchi ko'rik topilmasi: birinchi tuzatish `kind == network`ni
    // ishlatgan edi — u esa 5xx'ni HAM qamrab oladi. 502/503 da server
    // SMS'ni allaqachon yuborgan bo'lishi mumkin, ya'ni sovutishni
    // o'tkazib yuborish takroriy SMS va rate-limit'ga olib boradi.
    // Faqat `statusCode == null` — javob UMUMAN kelmagan, ya'ni haqiqiy
    // transport xatosi.
    final transportFailure =
        !ok &&
        failedState is AuthUnauthenticated &&
        failedState.kind == ApiErrorKind.network &&
        failedState.statusCode == null;
    if (!transportFailure) _startCooldown();

    if (!ok && mounted) {
      final l10n = AppLocalizations.of(context);
      final message = failedState is AuthUnauthenticated
          ? localizedAuthError(
              l10n,
              code: failedState.code,
              fallback: failedState.message ?? l10n.authUnexpectedError,
            )
          : l10n.authUnexpectedError;
      showAppToast(context, message, type: ToastType.error);
      // ⚠️ `resendOtp` (=`requestOtp`) muvaffaqiyatsizlikda global
      // `authControllerProvider` holatini `AuthUnauthenticated`ga
      // o'zgartiradi — yuqoridagi toast bilan ko'rsatilgach, holatni
      // shu ekran uchun neytral holatga qaytaramiz (aks holda `/login`ga
      // qaytilganda ekranda eskirgan xato ko'rinib qolishi mumkin edi).
      ref.read(authControllerProvider.notifier).backToPhoneEntry();
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _codeFocusNode.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _submit() {
    if (_codeController.text.trim().length != _kOtpLength) {
      setState(() => _showError = true);
      return;
    }
    impactHaptic();
    setState(() => _showError = false);
    FocusScope.of(context).unfocus();
    ref
        .read(authControllerProvider.notifier)
        .verifyOtp(widget.phoneE164, _codeController.text.trim());
  }

  // ⚠️ Avval `BackButton(onPressed: ...)` FAQAT auth holatini
  // `AuthUnauthenticated`ga qaytarardi, lekin marshrutni HECH QACHON
  // pop qilmasdi (`onPressed` berilgani uchun tugma o'zining standart
  // "orqaga qaytish" xatti-harakatini yo'qotadi) — natijada tugma
  // bosilsa hech narsa ko'rinmas edi, foydalanuvchi OTP ekranida qolib
  // ketardi.
  void _backToPhoneEntry() {
    ref.read(authControllerProvider.notifier).backToPhoneEntry();
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // ⚠️ Avval noto'g'ri kod kiritilgach xato xabari chiqardi, lekin 4
    // ta katakcha ESKI (noto'g'ri) raqamlar bilan to'lган holicha
    // qolaverardi — qayta urinish uchun foydalanuvchi ularni QO'LDA
    // o'chirishi kerak edi. Native SMS-kod ekranlari (Uber, Telegram)
    // odatda xato kelgach maydonni o'zi tozalab, klaviaturani qayta
    // ochadi — endi shunday.
    ref.listen<AuthSessionState>(authControllerProvider, (previous, next) {
      if (next is AuthOtpSent && next.error != null) {
        _codeController.clear();
        _codeFocusNode.requestFocus();
        // ⚠️ Audit topilmasi: verifikatsiya xatosi avval FAQAT quti
        // ostidagi statik matn orqali ko'rsatilardi — `_resend`dagi
        // muvaffaqiyatsizlik yo'li (yuqorida) esa `showAppToast` orqali
        // standart toast+haptik (`notificationHaptic(success: false)`)
        // naqshidan foydalanadi. Endi shu ekrandagi ikkala xato yo'li ham
        // bir xil naqshga ergashadi — inline matn (qutilar bilan bog'liq
        // vizual signal) saqlanib qoladi, ustiga toast qo'shiladi.
        showAppToast(
          context,
          localizedAuthError(l10n, code: next.code, fallback: next.error!),
          type: ToastType.error,
        );
      }
    });
    final authState = ref.watch(authControllerProvider);
    final isSubmitting = authState is AuthSubmitting;
    final errorMessage = authState is AuthOtpSent && authState.error != null
        ? localizedAuthError(
            l10n,
            code: authState.code,
            fallback: authState.error!,
          )
        : null;

    return Scaffold(
      // ⚠️ 1-urinishda bu ekran ham telefon ekrani kabi butun bo'shliqni
      // `Center` bilan markazlashtirardi — lekin bu yerda mazmun ANCHA
      // qisqa (brend/logo yo'q, orqaga tugmasi bor — bu "hero" emas,
      // oqimning IKKINCHI qadami), shu sabab natija ustida ham, ostida
      // ham nomutanosib ravishda ko'p bo'sh joy qoldi ("premium
      // sezilmayapti" — foydalanuvchi izohi). Qadam ekranlari (Uber,
      // Revolut, Apple ID kabi) odatda MARKAZLASHMAYDI — tepadan boshlab,
      // ANIQ sarlavha bilan boshlanadi.
      // ⚠️ 2-urinish: `Scaffold.appBar` (shaffof, faqat orqaga tugmasi) +
      // `extendBodyBehindAppBar: true` — lekin `appBar` MAVJUD bo'lishining
      // o'zi (hatto bo'sh bo'lsa ham) `SafeArea`ga berilayotgan tepa
      // bo'shlig'ini telefon ekranidagidan FARQLI qildi — bir xil `56`
      // padding qo'yilgan bo'lsa ham, brend belgisi bir xil balandlikdan
      // BOSHLANMADI ("bir xil emas" — foydalanuvchi, skrinshotlar bilan
      // tasdiqlangan). Endi `appBar` UMUMAN yo'q — orqaga tugmasi tananing
      // O'ZI ichida, `Stack` bilan ustiga qo'yilgan (joy egallamaydi) — shu
      // bilan pastdagi `SafeArea` > `SingleChildScrollView` >
      // `padding(24,56,...)` daraxti telefon/parol ekranlari bilan
      // BAYT-BA-BAYT bir xil, joylashuv KAFOLATLANGAN mos keladi.
      body: AuthGradientBackground(
        child: SafeArea(
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ⚠️ Avval bu yerda ilova logotipi O'RNIGA generik
                    // "xabar" ikonkasi (doiracha ichida) ko'rsatilardi — telefon
                    // va parol ekranlaridagi haqiqiy logotipdan butunlay boshqa
                    // shakl/rang, shu bilan uch ekran o'rtasida "har birida
                    // boshqa belgi" taassurotini berardi ("o'rtadagi icon har
                    // sahifada har xil ko'rinyapti" — foydalanuvchi izohi). Endi
                    // uchala ekranda ham AYNAN bir xil brend belgisi, bir xil
                    // o'lchamda.
                    const Center(
                      child: AuthBrandHeader(logoOnly: true, size: 96),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      l10n.authCodeLabel,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.authCodeSentTo(widget.phoneE164),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? AppColors.darkLabel2
                            : AppColors.lightLabel2,
                      ),
                    ),
                    const SizedBox(height: 32),
                    _OtpBoxes(
                      controller: _codeController,
                      focusNode: _codeFocusNode,
                      length: _kOtpLength,
                      hasError: _showError || errorMessage != null,
                      onChanged: () {
                        if (_showError) setState(() => _showError = false);
                      },
                      // Kod to'liq kiritilgach — tugmani bosishni
                      // kutmasdan darhol tekshiradi (iOS SMS
                      // avtomatik to'ldirishda ham ishlaydi).
                      onCompleted: _submit,
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorMessage,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    // ⚠️ 4 xonali kod to'liq kiritilmaguncha o'chirilgan —
                    // bosilgach xato ko'rsatish o'rniga oldindan aniq holat.
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _codeController,
                      builder: (context, value, _) {
                        final canSubmit =
                            !isSubmitting && value.text.length == _kOtpLength;
                        return Container(
                          decoration: canSubmit
                              ? liftedShadow(context, radius: 12)
                              : null,
                          child: PlatformButton(
                            onPressed: canSubmit ? _submit : null,
                            child: isSubmitting
                                ? const PlatformLoadingIndicator(
                                    size: 20,
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  )
                                : Text(l10n.authVerifyCode),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton(
                        onPressed:
                            (isSubmitting || _resending || _secondsLeft > 0)
                            ? null
                            : _resend,
                        child: Text(
                          _secondsLeft > 0
                              ? l10n.authResendCodeIn('$_secondsLeft')
                              : l10n.authResendCode,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 4,
                left: 4,
                child: BackButton(
                  onPressed: _backToPhoneEntry,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 4 ta alohida katakcha — bitta ko'rinmas `TextField` (haqiqiy klaviatura
/// kiritishini ushlaydi, iOS SMS avto-to'ldirish uchun `oneTimeCode` bilan)
/// ustiga chizilgan. ⚠️ Avval oddiy bitta `TextFormField` (katta harflar
/// oralig'i bilan taqlid qilingan) edi — foydalanuvchi: "4 ta katakcha
/// bo'lib ko'rsatilsa yaxshi bo'lardi" (native SMS kod kiritish ekranlariga
/// o'xshash, kutilgan naqsh).
class _OtpBoxes extends StatefulWidget {
  const _OtpBoxes({
    required this.controller,
    required this.focusNode,
    required this.length,
    required this.onCompleted,
    required this.onChanged,
    this.hasError = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int length;
  final VoidCallback onCompleted;
  final VoidCallback onChanged;
  final bool hasError;

  @override
  State<_OtpBoxes> createState() => _OtpBoxesState();
}

class _OtpBoxesState extends State<_OtpBoxes> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleChange);
    widget.focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleChange);
    widget.focusNode.removeListener(_handleFocusChange);
    super.dispose();
  }

  void _handleFocusChange() => setState(() {});

  void _handleChange() {
    setState(() {});
    widget.onChanged();
    if (widget.controller.text.length == widget.length) {
      widget.onCompleted();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final separator = dark ? AppColors.darkSeparator : AppColors.lightSeparator;
    final text = widget.controller.text;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.focusNode.requestFocus(),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            // ⚠️ Avval `spaceBetween` edi — bu qatorni EKRAN KENGLIGIGA
            // yoyib yuborardi, 4 ta 56px quti orasida haddan tashqari
            // katta bo'shliq qoldirib ("orasi juda ko'p" — foydalanuvchi
            // izohi). Endi qutilar markazda, o'zaro yaqin (16px) turadi —
            // native SMS-kod ekranlaridagi kabi ixcham guruh.
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.length; i++) ...[
                if (i > 0) const SizedBox(width: 16),
                Builder(
                  builder: (context) {
                    final filled = i < text.length;
                    final active =
                        i == text.length &&
                        widget.focusNode.hasFocus &&
                        !widget.hasError;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 56,
                      height: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                        border: Border.all(
                          color: widget.hasError
                              ? Theme.of(context).colorScheme.error
                              : (active
                                    ? Theme.of(context).colorScheme.primary
                                    : separator),
                          width: active || widget.hasError ? 1.5 : 1,
                        ),
                      ),
                      child: Text(
                        filled ? text[i] : '',
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
          // Haqiqiy kiritish maydoni — ko'rinmas, faqat klaviatura va
          // qiymatni boshqaradi; yuqoridagi qatorlar shu qiymatni aks
          // ettiradi.
          Opacity(
            opacity: 0,
            child: Semantics(
              label: AppLocalizations.of(context).authCodeLabel,
              textField: true,
              value: '${text.length} / ${widget.length}',
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                keyboardType: TextInputType.number,
                autofocus: true,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(widget.length),
                ],
                showCursor: false,
                enableInteractiveSelection: false,
                decoration: const InputDecoration(
                  counterText: '',
                  border: InputBorder.none,
                ),
                style: const TextStyle(fontSize: 1, height: 0.01),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
