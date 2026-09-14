import '../../core/l10n/gen/app_localizations.dart';

/// `AuthController`ning umumiy (`ApiException` bo'lmagan) xato yo'lidan
/// kelgan holatni belgilash uchun — server `code`lari bilan hech qachon
/// to'qnashmasligi uchun maxsus prefiks.
const kClientUnexpectedErrorCode = _kClientUnexpectedErrorCode;
const _kClientUnexpectedErrorCode = 'CLIENT_UNEXPECTED_ERROR';

/// Serverning `errorCode`sini klientning O'Z tilidagi xabariga o'giradi.
///
/// ⚠️ Server xato matnini (`message`) doim `otp_message_locale` (odatda
/// qat'iy `uz`) bo'yicha qaytaradi — ilova UI'si boshqa tilda bo'lsa ham
/// o'zgarmaydi ("xatolik xabari o'zbek tilida" — foydalanuvchi izohi,
/// ilova ingliz tilida edi). Bu yerda tanilgan kodlar UCHUN klient o'zi
/// tarjima qiladi; tanilmagan/`null` kod bo'lsa — server matni ko'rsatiladi
/// (yo'qdan yaxshi, faqat noto'g'ri tilda).
String localizedAuthError(
  AppLocalizations l10n, {
  required String? code,
  required String fallback,
}) {
  switch (code) {
    case 'AUTH_OTP_PHONE_NOT_FOUND':
      return l10n.authOtpPhoneNotFoundError;
    case 'AUTH_OTP_INVALID_PHONE':
      return l10n.authOtpInvalidPhoneError;
    case 'AUTH_INVALID_CREDENTIALS':
      return l10n.authInvalidCredentials;
    case _kClientUnexpectedErrorCode:
      // ⚠️ Topilma: `AuthController`ning umumiy `catch (e)` shoxlari
      // (ApiException BO'LMAGAN kutilmagan xato — masalan server javobi
      // buzuq shaklda kelsa) avval `e.toString()`ni to'g'ridan-to'g'ri
      // `message`/`fallback` sifatida ko'rsatardi — to'liq URL/so'rov
      // tafsilotlari bilan Dio xatosi ekranda chiqib qolishi mumkin edi.
      // `AuthController` bu holatda shu maxsus kodni beradi (haqiqiy
      // xato matni esa `CrashReporter`ga yoziladi), bu yerda umumiy,
      // xavfsiz xabarga almashtiriladi.
      return l10n.authUnexpectedError;
    default:
      return fallback;
  }
}
