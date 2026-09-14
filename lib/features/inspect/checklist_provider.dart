import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_exception.dart';
import '../../core/providers/core_providers.dart';
import '../../data/models/checklist.dart';
import '../../data/models/subject_candidate.dart';

const _kChecklistCachePrefix = 'checklist_cache_v1_';

/// ⚠️ Beshinchi audit topilmasi: avval bu provider TO'G'RIDAN-TO'G'RI
/// tarmoqqa murojaat qilardi, hech qanday lokal keshi yo'q edi —
/// oflayn holatda ALLAQACHON bir marta ochilgan checklist ham
/// "Yuklab bo'lmadi" bilan ochilmasdi, garchi ilova o'zi "offline-first"
/// deb belgilangan bo'lsa ham. Endi: muvaffaqiyatli tarmoq javobi
/// `SharedPreferences`ga xom JSON sifatida saqlanadi; keyingi
/// urinishda tarmoq YO'Q bo'lsa (`ApiErrorKind.network`) — saqlangan
/// nusxa qaytariladi (bo'lsa), bo'lmasa xato qayta uloqtiriladi.
///
/// ⚠️ To'liq Drift jadvali (migratsiya bilan) emas, atayin — bu loyihada
/// migratsiya testlari (`migration_test.dart`) juda katta va nozik
/// matritsa, yangi jadval xavfini asossiz oshiradi. `SharedPreferences`
/// yetarli: checklist ta'rifi kamdan-kam o'zgaradi, faqat "oxirgi
/// ko'rilgan nusxa"ni saqlash kifoya.
///
/// ⚠️ Foydalanuvchi topilmasi: "tekshiruv sahifasiga o'tishda ... belgi
/// chaqnayapti" — sabab (ikkinchi qatlam, `geofence_gate.dart`dagi
/// tuzatishdan keyin ham qolgan): `autoDispose` bo'lgani sabab, HAR
/// safar ekrandan chiqilganda (boshqa hech kim tinglamasa) provider
/// darhol o'chirilib, KEYINGI safar XUDDI SHU checklist qayta ochilsa
/// ham tarmoqdan qaytadan yuklanardi — bu esa `InspectScreen`ning
/// shimmer skeletonini har safar (hatto bir necha soniya oldin
/// ko'rilgan checklist uchun ham) qisqa muddatga qayta ko'rsatardi.
/// Checklist ta'rifi bir sessiya davomida deyarli o'zgarmaydi (yuqoridagi
/// izohga qarang) — shu sabab `autoDispose` olib tashlandi, endi ilova
/// ochiq turgan butun sessiya davomida keshda qoladi (xotira narxi —
/// bir nechta kichik JSON obyekti, ahamiyatsiz).
final checklistProvider = FutureProvider.family<Checklist, String>((
  ref,
  checklistId,
) async {
  final prefs = await SharedPreferences.getInstance();
  final cacheKey = '$_kChecklistCachePrefix$checklistId';
  try {
    final checklist = await ref
        .read(employeeApiProvider)
        .getChecklist(checklistId);
    // Fon vazifasi sifatida yozamiz — javobni kutish shart emas.
    unawaited(prefs.setString(cacheKey, jsonEncode(checklist.toJson())));
    return checklist;
  } on ApiException catch (e) {
    if (e.kind == ApiErrorKind.network) {
      final cached = prefs.getString(cacheKey);
      if (cached != null) {
        return Checklist.fromJson(jsonDecode(cached) as Map<String, dynamic>);
      }
    }
    rethrow;
  }
});

/// `checklist.subjectEmployee` bo'lgan checklist'lar uchun "tekshirilayotgan
/// xodim" nomzodlari ro'yxati.
final subjectCandidatesProvider = FutureProvider.family
    .autoDispose<List<SubjectCandidate>, String>((ref, checklistId) {
      return ref.read(employeeApiProvider).getSubjectCandidates(checklistId);
    });
