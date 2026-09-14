import 'package:flutter/services.dart';

/// Xom raqamlarni ("901234567") jonli ravishda "90 123 45 67" ko'rinishiga
/// keltiradi — kursor doim oxirida qoladi (o'rtaga kiritish/o'chirish
/// kamdan-kam holat, ilova ichidagi telefon maydonlari uchun yetarli).
/// ⚠️ Avval `phone_login_screen.dart`ning PRIVATE nusxasi edi — Xodimni
/// tahrirlash formasiga ("telefon raqam qatorini chiroyliroq qiling.
/// formatlangan ham bo'lsinda") ikkinchi kerak bo'lgach umumiy joyga
/// ko'chirildi.
class UzPhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      buffer.write(digits[i]);
      final isGroupEnd = i == 1 || i == 4 || i == 6;
      if (isGroupEnd && i != digits.length - 1) buffer.write(' ');
    }
    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// O'zbekiston telefon raqamini E.164 formatiga normallashtiradi.
/// `+998901234567` shaklida qaytaradi, yaroqsiz bo'lsa `null`.
String? normalizeUzPhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  String national;
  if (digits.startsWith('998') && digits.length == 12) {
    national = digits.substring(3);
  } else if (digits.length == 9) {
    national = digits;
  } else {
    return null;
  }
  if (national.length != 9) return null;
  return '+998$national';
}
