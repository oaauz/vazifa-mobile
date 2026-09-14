import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/haptics.dart';
import '../../core/l10n/gen/app_localizations.dart';
import '../../core/widgets/auth_brand_header.dart';
import '../../core/widgets/auth_chrome.dart';
import '../../core/widgets/platform_button.dart';
import '../../core/widgets/platform_loading_indicator.dart';
import 'auth_controller.dart';
import 'auth_error_l10n.dart';
import 'auth_state.dart';

/// Zaxira kirish yo'li — `POST /auth/login {login, password}` bugun
/// backend'da tayyor (OTP endpointlari qurilmaguncha shu yo'l orqali
/// haqiqiy backend bilan sinash mumkin). Reja: Backend B1.
class PasswordLoginScreen extends ConsumerStatefulWidget {
  const PasswordLoginScreen({super.key});

  @override
  ConsumerState<PasswordLoginScreen> createState() =>
      _PasswordLoginScreenState();
}

class _PasswordLoginScreenState extends ConsumerState<PasswordLoginScreen> {
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    // ⚠️ Telefon ekranidagi (yoki shu ekrandagi avvalgi) muvaffaqiyatsiz
    // urinishdan qolgan xato GLOBAL holatda saqlanib qolgani uchun bu
    // yerga hech narsa qilinmasdan ko'chib kelardi ("bu sahifadagi xatolik
    // hech narsa qilmasa ham turibdi" — foydalanuvchi izohi).
    //
    // ⚠️ `phone_login_screen.dart`dagi bilan bir xil senior audit
    // topilmasi — `initState()` ichida providerni sinxron o'zgartirish
    // Riverpod tomonidan taqiqlangan, release rejimida bu jim yutilib,
    // "OTP/chiqishdan keyin ekran abadiy qotib qoladi" holatiga olib
    // kelgan. `Future.microtask()` bilan kechiktirildi.
    Future.microtask(
      () => ref.read(authControllerProvider.notifier).clearError(),
    );
  }

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    impactHaptic();
    FocusScope.of(context).unfocus();
    ref
        .read(authControllerProvider.notifier)
        .loginWithPassword(
          _loginController.text.trim(),
          _passwordController.text,
        );
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
      // ⚠️ Avval standart Material `AppBar(title: Text(...))` edi — ilova
      // ichidagi HECH bir joyda ishlatilmagan qattiq/katta sarlavha
      // shrifti bilan chiqib, qolgan matnlardan "begona" ko'rinardi.
      // ⚠️ 2-urinish: `AppBar(backgroundColor: transparent)` +
      // `extendBodyBehindAppBar: true` bilan sarlavhasiz, shaffof panel
      // qilingan edi — lekin `Scaffold.appBar` MAVJUD bo'lishining o'zi
      // (hatto bo'sh bo'lsa ham) `SafeArea`ga berilayotgan tepa
      // bo'shlig'ini telefon ekranidagidan FARQLI qildi — bir xil `56`
      // padding qo'yilgan bo'lsa ham, ikkala ekrandagi brend belgisi bir
      // xil balandlikdan BOSHLANMADI ("bir xil emas" — foydalanuvchi,
      // skrinshotlar bilan tasdiqlangan). Endi `appBar` UMUMAN yo'q —
      // orqaga tugmasi tananing O'ZI ichida, `Stack` bilan ustiga
      // qo'yilgan (joy egallamaydi) — shu bilan pastdagi `SafeArea` >
      // `SingleChildScrollView` > `padding(24,56,...)` daraxti telefon
      // ekrani bilan BAYT-BA-BAYT bir xil, joylashuv KAFOLATLANGAN mos
      // keladi.
      body: AuthGradientBackground(
        child: SafeArea(
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ⚠️ Uchala kirish ekranida (telefon/OTP/parol) bir xil
                      // brend belgisi, bir xil o'lchamda — avval bu yerda
                      // "compact" (kichikroq) + nom matni bor edi, telefon
                      // ekranida esa katta + tagline — ikkisi ORASIDA ham,
                      // OTP ekrani bilan ham izchil emas edi ("o'rtadagi icon
                      // har sahifada har xil ko'rinyapti" — foydalanuvchi
                      // izohi).
                      const Center(
                        child: AuthBrandHeader(logoOnly: true, size: 96),
                      ),
                      const SizedBox(height: 36),
                      TextFormField(
                        controller: _loginController,
                        // ⚠️ Telefon ekranida xuddi shu sabab bilan ATAYLAB
                        // olib tashlangan edi — bu yerda esa qolib ketgan
                        // edi: ekran ochilishi bilan klaviatura darhol
                        // sakrab chiqardi, endi kontent barcha ekranlarda
                        // bir xil sobit joydan boshlangani uchun bu
                        // "sakrash" yanada ko'zga tashlanadi. Foydalanuvchi
                        // o'zi bosganda ochiladi.
                        decoration: InputDecoration(
                          labelText: l10n.authLoginOrEmail,
                        ),
                        // ⚠️ Avval ikkala maydon ham standart `done`
                        // harakatiga ega edi — login maydonida "Return"
                        // bosilsa klaviatura shunchaki yopilib qolardi,
                        // parol maydoniga o'tish uchun qo'lda bosish kerak
                        // edi. Endi "Keyingisi" parol maydoniga o'tkazadi.
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) =>
                            FocusScope.of(context).nextFocus(),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? l10n.authRequired
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: l10n.authPasswordLabel,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure ? LucideIcons.eye : LucideIcons.eyeOff,
                            ),
                            tooltip: _obscure
                                ? l10n.authShowPassword
                                : l10n.authHidePassword,
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        textInputAction: TextInputAction.done,
                        validator: (v) =>
                            (v == null || v.isEmpty) ? l10n.authRequired : null,
                        onFieldSubmitted: (_) => _submit(),
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
                      // ⚠️ Avval maydonlar bo'sh bo'lsa ham tugma yoqilgan
                      // turardi — bosilgach VALIDATOR orqali xato
                      // ko'rsatardi ("tugma hech narsa kiritilmagan
                      // bo'lsa ham active turibdi" — foydalanuvchi
                      // izohi). Telefon/OTP ekranlaridagi kabi —
                      // ikkala maydon to'ldirilmaguncha o'chirilgan.
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _loginController,
                        builder: (context, loginValue, _) {
                          return ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _passwordController,
                            builder: (context, passwordValue, _) {
                              final canSubmit =
                                  !isSubmitting &&
                                  loginValue.text.trim().isNotEmpty &&
                                  passwordValue.text.isNotEmpty;
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
                                      : Text(l10n.authSignInButton),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 4,
                left: 4,
                child: BackButton(
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
