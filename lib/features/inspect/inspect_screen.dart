import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/core_providers.dart';
import '../../core/widgets/detail_app_bar.dart';
import '../../core/widgets/list_error_state.dart';
import '../../core/widgets/shimmer_block.dart';
import '../../data/models/inspection_answer_draft.dart';
import '../settings/profile_provider.dart';
import 'checklist_provider.dart';
import 'geofence_gate.dart';
import 'inspect_fill_screen.dart';

/// `/inspect/:checklistId` — checklist + qoralamani yuklab, tayyor
/// bo'lgach [InspectFillScreen]ni TO'G'RIDAN-TO'G'RI qaytaradi.
///
/// ⚠️ Avval bu yerda alohida "ko'rib chiqish" (preview) bosqichi bo'lgan —
/// tavsif, savollar soni, bo'limlar xulosasi va subyekt tanlovi, "Boshlash"
/// tugmasi bilan. Foydalanuvchi buni sinab ko'rib, mini appda kerak
/// bo'lgan bu bosqich (asosan filial tanlash uchun, u allaqachon olib
/// tashlangan) native ilovada shunchaki ortiqcha bosish ekanini payqadi —
/// "Boshlash" ikki marta bosilganday tuyulardi. Yagona haqiqiy funksional
/// zarurat — subyekt (`checklist.subjectEmployee`) tanlovi — endi
/// [InspectFillScreen]ning O'ZIDA, eng yuqorida turadi; tanlanmasdan
/// yuborishga urinilsa o'sha yerga scroll+chayqalish+vibratsiya bilan
/// diqqat tortiladi (`_onSubmitPressed` / `SubjectPickerField`).
class InspectScreen extends ConsumerStatefulWidget {
  const InspectScreen({
    super.key,
    required this.checklistId,
    this.taskId,
    this.locationId,
    this.locationName,
    this.initialChecklistTitle,
  });

  final String checklistId;
  final String? taskId;
  final String? locationId;

  /// Ekran sarlavhasi ostida ko'rsatish uchun (`InspectFillScreen`).
  /// `MyTasksScreen`dan navigatsiya vaqtida uzatiladi — `EmployeeTask`da
  /// allaqachon bor, qayta so'rov shart emas.
  final String? locationName;

  /// ⚠️ Auditda topilgan xato: checklist yuklanmay xato bersa, AppBar
  /// sarlavhasi bo'sh qolardi ("begona ekran" hissi — `geofence_gate
  /// .dart`da xuddi shu sabab bilan tuzatilgan). `MyTasksScreen`da
  /// checklist nomi ALLAQACHON bor (`EmployeeTask.checklists`) —
  /// tarmoq so'rovisiz shu yerga uzatiladi, faqat XATO holatida
  /// zaxira sifatida ishlatiladi (checklist muvaffaqiyatli yuklansa,
  /// haqiqiy `checklist.title` ustunlik qiladi).
  final String? initialChecklistTitle;

  @override
  ConsumerState<InspectScreen> createState() => _InspectScreenState();
}

class _InspectScreenState extends ConsumerState<InspectScreen> {
  Map<String, InspectionAnswerDraft> _draftAnswers = const {};
  String? _subjectUserId;
  bool _subjectDecided = false;
  bool _draftLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadDraft();
  }

  // ⚠️ Foydalanuvchi: "kechagi yoki oldingi kunlardagi to'ldirilgan
  // tekshiruv javoblari bugun boshlanmagan cheklistga ham chiqib
  // turibdi" — avval SANA faqat YUKLANGANDAN KEYIN, alohida runtime
  // tekshiruvi (`_isSavedToday`) bilan bekor qilinardi. Endi sana
  // `DraftService`ning kalitiga singdirilgan (`DraftService.key`) —
  // `load()` STRUKTUR jihatdan faqat BUGUNGI qoralamani topa oladi,
  // eski kunning qatori boshqa kalit ostida yotadi va hech qachon
  // qaytmaydi — alohida runtime tekshiruvi/tozalash shart emas.
  Future<void> _loadDraft() async {
    final draftService = ref.read(draftServiceProvider);
    final draft = await draftService.load(
      checklistId: widget.checklistId,
      taskId: widget.taskId,
      locationId: widget.locationId,
      nowMs: ref.read(clockProvider).nowMs(),
    );
    if (!mounted) return;
    setState(() {
      _draftLoaded = true;
      if (draft != null) {
        _draftAnswers = draft.answers;
        _subjectUserId = draft.subjectUserId;
        if (draft.subjectUserId != null) _subjectDecided = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final checklistAsync = ref.watch(checklistProvider(widget.checklistId));
    // ⚠️ TOPILGAN BUG (foydalanuvchi: "ba'zi tekshiruvlarda javoblar 'Ha'
    // tanlangan bo'lib qolyapti, umuman ochilmagan inspectionni ochganda
    // ham shunday"): avval `profile?.prefillYes ?? true` — `profileProvider`
    // (tarmoqdan yuklanadigan `FutureProvider`) hali javob bermagan payt
    // HAR DOIM `true`ga tushib qolardi, tashkilot haqiqatda `false`
    // sozlagan bo'lsa ham. `InspectFillScreen`dagi `_answers` esa
    // `late final` — BIR MARTA, shu noto'g'ri `true` bilan hisoblanib
    // MUZLAB qolardi (State qayta yaratilmagani uchun profile keyinroq
    // to'g'ri qiymat bilan kelib, bu ekran qayta qurilsa ham, allaqachon
    // "Ha" bo'lib chizilgan savollar o'zgarmasdi). Natija: ilova endigina
    // ochilib (profile hali yuklanmagan), foydalanuvchi darhol tekshiruvga
    // kirsa — majburiy savollar noto'g'ri "Ha" ko'rinardi; chiqib qayta
    // kirganda (bu safar profile allaqachon yuklangan, haqiqiy `false`
    // qiymat) — "Ha" g'oyib bo'lganday tuyulardi. Yechim: checklist/
    // draft kabi, profile ham ANIQLANGUNCHA (yuklandi YOKI xato berdi —
    // ikkalasi ham "aniq holat") `InspectFillScreen` UMUMAN qurilmaydi —
    // shu bilan `prefillYes` doim HAQIQIY qiymat bilan uzatiladi.
    final profileAsync = ref.watch(profileProvider);
    final profile = profileAsync.valueOrNull;
    final prefillYes = profile?.prefillYes ?? true;
    final requireViewAll = profile?.requireViewAll ?? false;

    if (!_draftLoaded || checklistAsync.isLoading || profileAsync.isLoading) {
      return const _InspectSkeleton();
    }

    return checklistAsync.when(
      loading: () => const _InspectSkeleton(),
      error: (error, _) => Scaffold(
        appBar: DetailAppBar(title: widget.initialChecklistTitle ?? ''),
        body: ListErrorState(
          error: error,
          onRetry: () => ref.invalidate(checklistProvider(widget.checklistId)),
        ),
      ),
      // GPS geofencing (2026-09): `locationId` `geofenceRequired == true`
      // bo'lsa, `InspectFillScreen` UMUMAN qurilmasdan turib GPS
      // majburiy tekshiriladi (`geofence_gate.dart`) — boshqa filiallar
      // uchun bu qatlam shaffof, darhol `builder` chaqiriladi.
      data: (checklist) => GeofenceGate(
        locationId: widget.locationId,
        checklistTitle: checklist.title,
        builder: (context, gpsLat, gpsLng) => InspectFillScreen(
          checklistId: widget.checklistId,
          checklist: checklist,
          taskId: widget.taskId,
          locationId: widget.locationId,
          locationName: widget.locationName,
          initialAnswers: _draftAnswers,
          initialSubjectUserId: _subjectUserId,
          initialSubjectDecided: _subjectDecided,
          prefillYes: prefillYes,
          requireViewAll: requireViewAll,
          verifiedGpsLat: gpsLat,
          verifiedGpsLng: gpsLng,
        ),
      ),
    );
  }
}

/// Checklist yuklanayotgan payt — mini app `Inspect.tsx` skeleton porti
/// (sarlavha + 5 ta soxta savol kartasi). Avval bu yerda oddiy aylanuvchi
/// spinner bor edi — "juda oddiy" senior UI/UX auditida topilgan.
class _InspectSkeleton extends StatelessWidget {
  const _InspectSkeleton();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const ShimmerBlock(width: 140, height: 18, radius: 4),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (var i = 0; i < 5; i++) ...[
            const _InspectItemSkeleton(),
            if (i != 4) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _InspectItemSkeleton extends StatelessWidget {
  const _InspectItemSkeleton();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ShimmerBlock(width: 20, height: 20, radius: 10),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ShimmerBlock(width: double.infinity, height: 16),
                  const SizedBox(height: 8),
                  const ShimmerBlock(width: 180, height: 16),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: ShimmerBlock(
                          width: double.infinity,
                          height: 40,
                          radius: 12,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ShimmerBlock(
                          width: double.infinity,
                          height: 40,
                          radius: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
