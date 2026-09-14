import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/l10n/gen/app_localizations.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/auth_brand_header.dart';
import '../../core/widgets/auth_chrome.dart';
import '../../core/widgets/platform_button.dart';
import '../../core/widgets/platform_loading_indicator.dart';
import 'auth_controller.dart';
import 'auth_error_l10n.dart';
import 'auth_state.dart';
import 'phone_utils.dart';

/// Kirish oqimining birinchi qadami — telefon raqami kiritiladi, OTP kod
/// yuboriladi.
///
/// ⚠️ 1-urinish: brend + tokenlar qo'yilgan edi, lekin kompozitsiya YO'Q
/// edi — hammasi yuqoriga yopishib, ekranning pastki yarmi butunlay bo'sh
/// qolardi ("premium hissiyot yo'q" — foydalanuvchi izohi, screenshot bilan
/// tasdiqlangan). Shuningdek `prefixText: '+998 '` `hintText` bilan birga
/// ko'rinmay qoldi (Flutter'ning ma'lum nozik joyi). Endi: (1) butun blok
/// (logo+forma+tugma+havola) BITTA birlik sifatida vertikal markazlashadi
/// — klaviatura ochilsa `SingleChildScrollView` unga joy beradi; (2) fon —
/// logotip rangidan yumshoq gradient wash; (3) telefon maydoni qo'lda
/// qurilgan segmentli input (`+998` doim ko'rinadi); (4) logo va CTA
/// tugmasi ostida yumshoq soya — "yassi" emas, "ko'tarilgan" tuyg'usi.
class PhoneLoginScreen extends ConsumerStatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  ConsumerState<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends ConsumerState<PhoneLoginScreen> {
  final _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    // ⚠️ Parol ekranidagi (yoki shu ekrandagi avvalgi) urinishdan qolgan
    // xato xabari bu yerga GLOBAL holat orqali "sizib o'tib" qolmasligi
    // uchun — ekran ochilganda har doim toza boshlanadi.
    //
    // ⚠️ SENIOR AUDIT — JIDDIY TOPILMA: `initState()` ichida providerni
    // TO'G'RIDAN-TO'G'RI (sinxron) o'zgartirish Riverpod tomonidan
    // TAQIQLANGAN ("Tried to modify a provider while the widget tree
    // was building"). Debug rejimida qizil xato ekrani chiqadi, LEKIN
    // release rejimida bu xato JIM yutilib, o'sha kadr chizilmay qoladi
    // — foydalanuvchi buni "OTP kod kiritgandan/chiqishdan keyin ekran
    // abadiy qotib qoladi" deb ko'rgan edi (`restartApp()` BUTUN daraxtni
    // qayta qurganda, GoRouter'ning `authControllerProvider`ni allaqachon
    // tinglayotgan `Builder`i HALI QURILAYOTGANDA shu ekran o'zining
    // `initState()`ida xuddi shu providerni o'zgartirmoqchi bo'lgan).
    // Riverpod'ning o'z tavsiyasi: o'zgartirishni qurilish TUGAGANDAN
    // KEYINGI mikrovazifaga kechiktirish — `Future.microtask()` birinchi
    // kadr chizilishidan OLDIN ishlaydi, shu sabab "eski xato bir lahza
    // ko'rinib qoladi" xavfi yo'q, faqat Riverpod qoidasiga rioya
    // qilinadi.
    Future.microtask(
      () => ref.read(authControllerProvider.notifier).clearError(),
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  // ⚠️ Avval bu yerda faqat `requestOtp`ni chaqirib qo'yardi, navigatsiya
  // esa `build()`dagi `ref.listen` orqali GLOBAL holatni kuzatib amalga
  // oshirilardi. Muammo: OTP ekranidagi "Qayta yuborish" HAM xuddi shu
  // global holatni (`AuthOtpSent`) qayta chiqarardi — bu ekran esa
  // (Navigator'da ostda, o'chirilmagan) buni "yangi so'rov" deb bilib,
  // OTP ekranini YANA push qilardi. Natija: har "Qayta yuborish"da OTP
  // ekrani navbatga qayta qo'shilib borardi ("4 marta resend — 4 marta
  // back kerak" — foydalanuvchi izohi). Endi navigatsiya to'g'ridan-to'g'ri
  // SHU chaqiruvning natijasiga bog'liq — global tinglovchi shart emas.
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final phone = normalizeUzPhone(_phoneController.text);
    if (phone == null) return;
    impactHaptic();
    FocusScope.of(context).unfocus();
    final ok = await ref
        .read(authControllerProvider.notifier)
        .requestOtp(phone);
    if (ok && mounted) {
      context.push('/login/otp', extra: phone);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authState = ref.watch(authControllerProvider);
    final isSubmitting = authState is AuthSubmitting;
    final errorMessage =
        authState is AuthUnauthenticated && authState.message != null
        ? localizedAuthError(
            l10n,
            code: authState.code,
            fallback: authState.message!,
          )
        : null;

    return Scaffold(
      // ⚠️ Avval `LayoutBuilder` + `ConstrainedBox(minHeight: constraints.
      // maxHeight - 48)` + `Center` bilan mazmun HAR SAFAR mavjud
      // balandlikning o'rtasiga joylashardi — klaviatura ochilganda Scaffold
      // (`resizeToAvoidBottomInset`) tanani torayttiradi, `constraints.
      // maxHeight` birdan kamayadi, `Center` esa mazmunni YANGI (kichikroq)
      // balandlikning o'rtasiga QAYTA joylashtiradi — natijada butun blok
      // sakrab yuqoriga otilardi ("kontent hozir klaviatura ochilganida
      // sakrayapti" — foydalanuvchi izohi). Endi mazmun ekranning O'ZIGA XOS
      // (klaviaturadan mustaqil) tepa nuqtasidan boshlanadi — klaviatura
      // ochilganda faqat `SingleChildScrollView` diqqat markazidagi maydonni
      // ko'rinadigan qilib SILLIQ aylantiradi, hech narsa qayta
      // markazlashmaydi.
      body: AuthGradientBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(
                    child: AuthBrandHeader(logoOnly: true, size: 96),
                  ),
                  const SizedBox(height: 36),
                  Text(
                    l10n.authPhoneLabel,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  _PhoneField(
                    controller: _phoneController,
                    onSubmitted: _submit,
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorMessage,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  // ⚠️ Avval raqam bo'sh/yaroqsiz bo'lsa ham tugma
                  // yoqilgan turardi — bosilgach xatoni ko'rsatardi.
                  // Endi to'liq (9 xonali) raqam kiritilmaguncha
                  // o'chirilgan — foydalanuvchi noto'g'ri urinib
                  // xato ko'rmasdan, kerakli holatni oldindan
                  // ko'radi.
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _phoneController,
                    builder: (context, value, _) {
                      final canSubmit =
                          !isSubmitting && normalizeUzPhone(value.text) != null;
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
                              : Text(l10n.authRequestCode),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: TextButton(
                      onPressed: () => context.push('/login/password'),
                      child: Text(l10n.authUsePassword),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// O'zbekiston telefon raqamini `+998` doim ko'rinadigan segmentli maydonga
/// ajratadi — `TextFormField.prefixText` bilan birga `hintText` ba'zan
/// ko'rinmasligi mumkinligi tufayli (avvalgi versiyada yuz bergan aynan
/// shu xato) qo'lda qurilgan, ishonchli variant.
///
/// ⚠️ 1-urinishda ICHKI `TextField` faqat `border: InputBorder.none`
/// bergan edi — `enabledBorder`/`focusedBorder` global `inputDecoration
/// Theme`dan meros qolgani uchun, fokusda TASHQI konteynerning o'z
/// chegarasi USTIGA yana bitta (primary rangli, boshqa radiusli) ICHKI
/// chegara chizilib, "ikkita mos kelmagan quti" ko'rinishini berardi.
/// Endi barcha chegara holatlari ANIQ o'chirilgan — fokus signali FAQAT
/// tashqi konteynerning o'zida (`_focused`). Shuningdek "+998" va raqam
/// matni endi BIR XIL stil o'zgaruvchisidan (`_digitsStyle`) — avval
/// ikkalasi alohida `copyWith` chaqirilgani uchun ko'zga ko'rinarli
/// darajada har xil o'lchamda chiqib qolgan edi.
class _PhoneField extends StatefulWidget {
  const _PhoneField({required this.controller, required this.onSubmitted});
  final TextEditingController controller;
  final VoidCallback onSubmitted;

  @override
  State<_PhoneField> createState() => _PhoneFieldState();
}

class _PhoneFieldState extends State<_PhoneField> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final separator = dark ? AppColors.darkSeparator : AppColors.lightSeparator;
    final digitsStyle = Theme.of(context).textTheme.headlineSmall
        ?.copyWith(letterSpacing: 0.5);
    return FormField<String>(
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (_) =>
          normalizeUzPhone(widget.controller.text) == null ? '' : null,
      builder: (field) {
        final hasError = field.hasError;
        // ⚠️ Avval bo'sh (fokussiz, xatosiz) holatda ham har doim
        // ko'rinadigan bo'z chegara bo'lardi — sof "quti ichida quti"
        // ko'rinishi berardi, keraksiz vizual shov-shuv ("input atrofidagi
        // border kerakmi?" — foydalanuvchi savoli). Endi chegara FAQAT
        // holat signali sifatida paydo bo'ladi: fokusda — asosiy rang,
        // xatoda — qizil; aks holda umuman yo'q, faqat fon rangi
        // (`surface`) uni orqa fondan ajratib turadi.
        final showBorder = hasError || _focusNode.hasFocus;
        final borderColor = hasError
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.primary;
        // ⚠️ Accessibility audit: "+998" prefiksi alohida `Text` sifatida
        // (o'zining maxsus stili — qalin + ikkilamchi rang) qatorda
        // ko'rinadi, lekin `TextField`ning semantika daraxtiga kirmaydi —
        // ekran o'quvchisi faqat kiritilgan raqamlarni o'qib beradi,
        // "+998" prefiksini umuman aytmaydi. `prefixText`ga qayta qurish
        // vizual dizaynni (maxsus stil, ajratuvchi chiziq) buzish xavfi
        // borligi uchun butun maydon `Semantics` bilan o'raldi.
        return Semantics(
          label: '${AppLocalizations.of(context).authPhoneLabel} +998',
          textField: true,
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              border: showBorder
                  ? Border.all(color: borderColor, width: 1.5)
                  : Border.all(color: Colors.transparent, width: 1.5),
            ),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: Text(
                    '+998',
                    style: digitsStyle?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: dark
                          ? AppColors.darkLabel2
                          : AppColors.lightLabel2,
                    ),
                  ),
                ),
                SizedBox(
                  height: 22,
                  child: VerticalDivider(
                    width: 20,
                    thickness: 1,
                    color: separator,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focusNode,
                    keyboardType: TextInputType.number,
                    // ⚠️ Avval `autofocus: true` edi — splashdan darhol
                    // keyin klaviatura sakrab ochilardi, ba'zan hatto native
                    // splash olib tashlanish animatsiyasi bilan bir vaqtga
                    // to'g'ri kelib, "klaviatura splashda ham ochiq turgan"
                    // taassurotini berardi (foydalanuvchi izohi). Endi
                    // foydalanuvchi o'zi bosganda ochiladi.
                    // ⚠️ Avval faqat xom raqamlar ("901234567") ko'rsatilardi —
                    // xint "90 123 45 67" formatda bo'lsa-yu, kiritilgan qiymat
                    // formatlanmasdan qolib ketardi (foydalanuvchi izohi).
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(9),
                      UzPhoneNumberFormatter(),
                    ],
                    style: digitsStyle,
                    decoration: const InputDecoration(
                      hintText: '90 123 45 67',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 14),
                    ),
                    onChanged: (_) => field.didChange(widget.controller.text),
                    onSubmitted: (_) => widget.onSubmitted(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
