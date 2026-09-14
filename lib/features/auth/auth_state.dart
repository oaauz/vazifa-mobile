import '../../core/network/api_exception.dart';
import '../../data/models/auth_user.dart';

sealed class AuthSessionState {
  const AuthSessionState();
}

/// Ilova ochilganda — saqlangan sessiya tekshirilmoqda.
class AuthChecking extends AuthSessionState {
  const AuthChecking();
}

/// Kirish ekrani: telefon kiritilmagan.
class AuthUnauthenticated extends AuthSessionState {
  const AuthUnauthenticated({
    this.message,
    this.code,
    this.kind,
    this.statusCode,
  });
  final String? message;

  /// Serverning `errorCode`si (masalan `AUTH_OTP_PHONE_NOT_FOUND`) — bor
  /// bo'lsa, UI o'zining LOKALLASHTIRILGAN matnini ko'rsatadi, chunki
  /// `message` doim server standart tilida (`otp_message_locale`) keladi,
  /// klient tiliga qarab o'zgarmaydi.
  final String? code;

  /// ⚠️ Xato TASNIFI — UI "server rad etdi"ni "serverga umuman yetib
  /// bormadi"dan farqlashi uchun. Masalan OTP qayta yuborish oflaynda
  /// yiqilsa, sovutish taymerini boshlash NOTO'G'RI bo'lardi: server
  /// hech qanday kod yaratmagan (`otp_verify_screen.dart`). Avval buni
  /// bilishning yagona yo'li `message` matnini tekshirish edi — mo'rt.
  final ApiErrorKind? kind;

  /// ⚠️ Ikkinchi ko'rik topilmasi: `kind == network` YETARLI EMAS —
  /// u 5xx'ni ham qamrab oladi (`api_exception.dart`: "Tarmoq/timeout/
  /// DNS/5xx"). 502/503 esa server SMS'ni ALLAQACHON yuborgan bo'lishi
  /// mumkinligini anglatadi, ya'ni sovutishni o'tkazib yuborish
  /// foydalanuvchini takroriy SMS'ga (va rate-limit'ga) olib boradi.
  /// Faqat `statusCode == null` haqiqiy transport xatosi.
  final int? statusCode;
}

/// OTP kod yuborildi, foydalanuvchi kodni kutmoqda.
class AuthOtpSent extends AuthSessionState {
  const AuthOtpSent({required this.phoneE164, this.error, this.code});
  final String phoneE164;
  final String? error;
  final String? code;
}

/// Kirish/tekshirish jarayonida (tugma spinner holati).
class AuthSubmitting extends AuthSessionState {
  const AuthSubmitting();
}

class AuthAuthenticated extends AuthSessionState {
  const AuthAuthenticated(this.user);
  final AuthUser user;
}
