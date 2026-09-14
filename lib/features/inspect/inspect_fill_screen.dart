import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/haptics.dart';
import '../../core/l10n/gen/app_localizations.dart';
import '../../core/location/gps_helper.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers/core_providers.dart';
import '../../core/shared_logic/answer_completeness.dart';
import '../../core/shared_logic/score.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/confirm_sheet.dart';
import '../../core/widgets/detail_app_bar.dart';
import '../../core/widgets/platform_button.dart';
import '../../core/widgets/platform_loading_indicator.dart';
import '../../data/models/checklist.dart';
import '../../data/models/employee_task.dart';
import '../../data/models/inspection_answer_draft.dart';
import '../tasks/tasks_controller.dart';
import 'checklist_provider.dart';
import 'inspect_item_field.dart';
import 'inspection_result_screen.dart';
import 'subject_picker.dart';

/// To'ldirish (fill) bosqichi — **haqiqiy alohida sahifa** (`Navigator.push`
/// bilan ochiladi, preview'dan). Foydalanuvchi so'rovi: preview↔to'ldirish
/// o'tishi "haqiqiy sahifa almashinuvidek" bo'lishi kerak edi — bir nechta
/// qo'lda animatsiya (fade, o'zi yasagan siljish) "qo'pol"/"tabiiy emas"
/// deb topildi. Yagona ishonchli yechim — buni ROSTDAN HAM alohida route
/// qilish, shunda platforma standart o'tish animatsiyasi (Tekshiruv→Preview
/// bilan AYNAN bir xil mexanizm) qo'llanadi.
class InspectFillScreen extends ConsumerStatefulWidget {
  const InspectFillScreen({
    super.key,
    required this.checklistId,
    required this.checklist,
    this.taskId,
    this.locationId,
    this.locationName,
    this.initialAnswers = const {},
    this.initialSubjectUserId,
    this.initialSubjectDecided = false,
    this.prefillYes = true,
    this.requireViewAll = false,
    this.verifiedGpsLat,
    this.verifiedGpsLng,
  });

  final String checklistId;
  final Checklist checklist;
  final String? taskId;
  final String? locationId;

  /// ⚠️ Avval bu ekranda filial/joylashuv umuman ko'rsatilmasdi — manba
  /// (`Inspect.tsx`)da sarlavha ostida `MapPin` + filial nomi meta-qatori
  /// bor (xodim ko'p filialga tegishli bo'lsa, HOZIR qaysi biriga
  /// tekshiruv o'tkazayotganini tasdiqlash uchun). `MyTasksScreen`
  /// (bir xil `EmployeeTask.locations`dan) navigatsiya vaqtida uzatadi.
  final String? locationName;
  final Map<String, InspectionAnswerDraft> initialAnswers;
  final String? initialSubjectUserId;
  final bool initialSubjectDecided;

  /// `organization.prefillYes` — `true` bo'lsa (standart), majburiy
  /// YES_NO savollar ekran ochilganda "Ha" bilan oldindan to'ldiriladi
  /// (faqat haqiqiy YANGI boshlashda — qoralama tiklanganda EMAS, aks
  /// holda xodimning avval ataylab "Yo'q" qilib qo'ygan javobini
  /// ustidan bosib yuborardi).
  final bool prefillYes;

  /// `organization.requireViewAll` — `true` bo'lsa, hali ko'rilmagan/
  /// bosilmagan (ekranga bir marta ham chiqmagan VA qo'l bilan
  /// tegilmagan) standart "Ha" javoblar bilan yuborish qattiq bloklanadi.
  final bool requireViewAll;

  /// GPS geofencing (2026-09): `locationId` `geofenceRequired == true`
  /// bo'lsa, `InspectScreen`dagi `GeofenceGate` bu ekran ochilishidan
  /// OLDIN GPS'ni MAJBURIY tekshirib, muvaffaqiyatli koordinatani shu
  /// yerga uzatadi — pastdagi ikkita `getGpsQuietly()` chaqiruvi (`start`
  /// so'rovi uchun) o'sha holatda QAYTA so'ramaydi, shu qiymatlarni
  /// ishlatadi. Boshqa (geofencing majburiy bo'lmagan) filiallar uchun
  /// har doim `null` — mavjud jim yo'l o'zgarishsiz qoladi.
  final double? verifiedGpsLat;
  final double? verifiedGpsLng;

  @override
  ConsumerState<InspectFillScreen> createState() => _InspectFillScreenState();
}

/// AppBar sarlavhasi — bir qatorga sig'maydigan uzun checklist nomlari
/// ko'p (masalan "Inventarizatsiya / tovar qoldig'ini solishtirish").
/// Ikkinchi qatorga o'tkazish AppBar balandligini oshirishni talab
/// qiladi (boshqa ekranlar bilan nomuvofiq bo'lardi), shu sabab o'rniga:
/// matn haqiqatan kesilganda (`TextPainter` bilan o'lchanadi) sarlavha
/// bosiladigan bo'ladi va to'liq nomni pastdan chiquvchi oynada
/// ko'rsatadi; kesilmasa — oddiy, bosilmaydigan matn (behuda taassurot
/// bermaslik uchun).
/// Checklist tavsifi — standart holatda 3 qatorga cheklangan, haqiqatan
/// kesilganda (`TextPainter` bilan o'lchanadi) "ko'proq" havolasi
/// chiqadi. Sabab: xodim savollarga yetguncha uzun matnni pastga surib
/// o'qib o'tirmasin — checklist to'ldirish tez ish, kitob o'qish emas.
class _ExpandableDescription extends StatefulWidget {
  const _ExpandableDescription({required this.text});
  final String text;

  @override
  State<_ExpandableDescription> createState() => _ExpandableDescriptionState();
}

class _ExpandableDescriptionState extends State<_ExpandableDescription> {
  static const _collapsedMaxLines = 3;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = Theme.of(context).textTheme.bodyMedium;
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: _collapsedMaxLines,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);
        final overflowing = painter.didExceedMaxLines;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              maxLines: _expanded ? null : _collapsedMaxLines,
              overflow: _expanded
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
              style: style,
            ),
            if (overflowing) ...[
              const SizedBox(height: 4),
              InkWell(
                onTap: () {
                  selectionHaptic();
                  setState(() => _expanded = !_expanded);
                },
                child: Text(
                  _expanded ? l10n.inspectNoteLess : l10n.inspectNoteMore,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Vaqt-qoldi pilli — faqat grace davrida yoki oynaning oxirgi 5
/// daqiqasida ko'rinadi ("ekran tinch nafas oladi", boshqa vaqt yashirin).
/// Manba: `Inspect.tsx` header o'rta pilli.
///
/// ⚠️ Avval `InspectFillScreen`ning O'ZINING 30s taymeri bilan (butun
/// ekranni qayta chizib) yangilanardi — foydalanuvchi "ekran vaqti-vaqti
/// bilan sakraydi" deb xabar berdi. Endi bu FAQAT shu kichik pill'ning
/// o'z alohida taymeri/holati — qayta chizish shu widget doirasida
/// qoladi, katta ro'yxat/forma umuman tegilmaydi.
class _TimeLeftPill extends ConsumerStatefulWidget {
  const _TimeLeftPill({required this.taskId});
  final String taskId;

  @override
  ConsumerState<_TimeLeftPill> createState() => _TimeLeftPillState();
}

class _TimeLeftPillState extends ConsumerState<_TimeLeftPill> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tasks = ref.watch(tasksControllerProvider).valueOrNull;
    EmployeeTask? task;
    if (tasks != null) {
      for (final t in tasks) {
        if (t.id == widget.taskId) {
          task = t;
          break;
        }
      }
    }
    if (task == null) return const SizedBox.shrink();

    final now = ref.read(clockProvider).nowMs();
    int? msLeft;
    var grace = false;
    if (task.inGracePeriod && task.graceEndsAt != null) {
      msLeft = task.graceEndsAt! - now;
      grace = true;
    } else if (task.endsAt != null) {
      msLeft = task.endsAt! - now;
    }
    if (msLeft == null || msLeft <= 0) return const SizedBox.shrink();

    final minutesLeft = (msLeft / 60000).ceil();
    if (!grace && minutesLeft > 5) return const SizedBox.shrink();

    final dark = Theme.of(context).brightness == Brightness.dark;
    Color bg;
    Color fg;
    IconData icon;
    if (grace) {
      bg = AppColors.warning500.withValues(alpha: dark ? 0.18 : 0.12);
      fg = dark ? AppColors.warning500 : AppColors.warning600;
      icon = LucideIcons.hourglass;
    } else if (minutesLeft <= 1) {
      bg = AppColors.danger500.withValues(alpha: dark ? 0.18 : 0.1);
      fg = dark ? AppColors.danger500 : AppColors.danger600;
      icon = LucideIcons.timer;
    } else {
      bg = dark ? AppColors.darkFill1 : AppColors.lightFill1;
      fg = dark ? AppColors.darkLabel2 : AppColors.lightLabel2;
      icon = LucideIcons.timer;
    }

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: fg),
            const SizedBox(width: 4),
            Text(
              l10n.inspectTimeLeftMin('$minutesLeft'),
              // ⚠️ `labelLarge`ning qator balandligi (1.3) ikonga nisbatan
              // matnni pastroq ko'rsatardi — `height: 1` bilan tuzatildi.
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w600, color: fg, height: 1),
            ),
          ],
        ),
      ),
    );
  }
}

class _InspectFillScreenState extends ConsumerState<InspectFillScreen>
    with WidgetsBindingObserver {
  late final _answers = <String, InspectionAnswerDraft>{
    ...widget.initialAnswers,
    // Mini app `prefillYes`: FAQAT haqiqiy yangi boshlashda (qoralama
    // tiklanmayotganda) majburiy YES_NO savollarni "Ha" bilan to'ldiradi
    // — xodimning avval saqlangan (masalan ataylab "Yo'q" qilingan)
    // javobini bosib yubormaslik uchun `widget.initialAnswers.isEmpty`
    // sharti bilan chegaralangan.
    // ⚠️ `item.skippable` savollar CHIQARIB TASHLANADI — manba
    // (`Inspect.tsx`: `if (item.skippable) continue;`). Bunday savolda
    // xodim uchun haqiqiy T/E chiqish yo'li bor (endi majburiy belgi ham
    // ko'rsatilmaydi, 2-bosqich tuzatishi) — avtomatik "Ha" bilan jimgina
    // to'ldirilsa, xodim buni sezmasdan qoldirib yuborishi mumkin edi,
    // aynan "tegishli bo'lmasligi mumkin" degan savollarda noto'g'ri
    // standart eng ko'p zarar keltiradi.
    if (widget.prefillYes && widget.initialAnswers.isEmpty)
      for (final item in widget.checklist.items)
        if (item.required && !item.skippable && item.type == 'YES_NO')
          item.id: InspectionAnswerDraft(itemId: item.id, value: 'Ha'),
  };
  final _formKey = GlobalKey<FormState>();
  final _itemKeys = <String, GlobalKey>{};
  final _subjectKey = GlobalKey();
  final _collapsed = <String>{};
  final _autoCollapsedOnce = <String>{};
  final _scoreConfig = kDefaultScoreConfig;

  // Mini app `viewedItemsRef`/`interactedItemsRef` porti — "ko'rilmagan
  // standart javob" (blind-default) himoyasi uchun. `_interactedItemIds`
  // — xodim savolga QO'LDA tegingan (`_selectAnswer` orqali chaqirilgan),
  // prefill hisobga olinmaydi. `_viewedItemIds` — savol ekranda kamida
  // yarmi ko'rinib turgan payt scroll orqali kuzatiladi (mini appdagi
  // `IntersectionObserver(threshold:0.5)` ning Flutter ekvivalenti —
  // yangi paket qo'shmaslik uchun `RenderBox` pozitsiyasi qo'lda
  // hisoblanadi).
  final _interactedItemIds = <String>{};
  final _viewedItemIds = <String>{};

  bool _submitting = false;
  String? _submitError;
  // "Reset" bosilganda oshiriladi — `InspectItemField`larga shu qiymatni
  // o'z ichiga olgan yangi `key` beriladi, shunda ular BUTUNLAY YANGI
  // State bilan qayta yaratiladi (media/izoh ichki holati ham tozalanadi
  // — faqat `_answers`ni tozalash yetarli emas edi, chunki
  // `MediaAnswerPicker`/`DocAttachField` o'z alohida holatini saqlaydi).
  int _resetToken = 0;
  // Yuborilgandan keyin natija ekrani shu maydon orqali ko'rsatiladi —
  // Navigator push EMAS (sabab: `_replaceWithResult` izohiga qarang).
  Widget? _completedScreen;
  // Sahifa ochilishida allaqachon "tayyor" bo'lsa (masalan qoralamadan
  // tiklanganda) darhol haptic bermaslik uchun boshlang'ich holat
  // build()dan OLDIN, `initState`da hisoblanadi.
  late bool _wasReady;
  String? _flashedItemId;
  // Xato emas, faqat "aynan shu savolga keldingiz" ko'rsatkichi —
  // popover/ro'yxatdan sakraganda foydalanuvchi qaysi savolga
  // tushganini bilmay qolgan edi (qizil "chaqnash" endi faqat haqiqiy
  // xato — yetishmagan media — uchun, boshqa hech qanday belgi
  // qolmagan edi). Neytral (primary) rangda, qisqaroq davomiylikda.
  String? _jumpHighlightItemId;
  final _ringButtonKey = GlobalKey();

  late String? _subjectUserId = widget.initialSubjectUserId;
  late bool _subjectDecided = widget.initialSubjectDecided;
  bool _subjectHighlighted = false;
  // ⚠️ Mini appda `POST /employee/inspections` ("boshlash") checklist
  // to'ldirishga kirilishi bilanoq (Preview'dagi "Boshlash" tugmasi)
  // yuboriladi — natijada `GET /employee/tasks` darhol `inProgress:true`
  // qaytaradi, xodim chiqib ketsa ham. Bizning portda preview bosqichi
  // olib tashlangач bu chaqiruv FAQAT yakuniy "Yuborish"da qolib ketgan
  // edi — shu sabab "jarayonda" holati va progress-hisoblagich hech
  // qachon ishlamasdi. Endi birinchi haqiqiy javob (yoki subyekt tanlovi,
  // qay biri oldin bo'lsa) berilishi bilan bir martalik, "urinib ko'ramiz"
  // (best-effort) chaqiruv qilinadi — oflaynda yoki xato bo'lsa jimgina
  // o'tkazib yuboriladi, yakuniy yuborishda odatdagidek qayta urinilar.
  // ⚠️ Avval bitta bool bilan "bir marta urinib ko'ramiz, muvaffaqiyatli
  // bo'ldimi-yo'qmi farqi yo'q" mantig'i ishlatilgan edi — agar aynan
  // BIRINCHI javobda tarmoq vaqtincha uzilib qolsa (yoki har qanday
  // o'tkinchi server xatosi), keyingi javoblarda foydalanuvchi allaqachon
  // onlaynga qaytgan bo'lsa ham QAYTA URINILMASDI: `startedAt` faqat
  // YAKUNIY yuborishda, `completedAt` bilan deyarli bir vaqtda yozilardi
  // — natijada "0 soniyada" kabi ma'nosiz davomiylik ko'rsatilardi
  // (foydalanuvchi kuzatgan haqiqiy nosozlik). Endi faqat MUVAFFAQIYATLI
  // urinish "yakunlangan" deb hisoblanadi — muvaffaqiyatsiz bo'lsa,
  // keyingi javobda avtomatik qayta urinib ko'riladi.
  bool _earlyStartInFlight = false;
  String? _earlyInspectionId;

  /// Foydalanuvchi so'rovi: "GPS holatini ko'rsatganimiz yaxshi" — GPS
  /// hech qachon tekshiruvni to'smaydi (yuqoridagi izoh), lekin xodim
  /// olinganmi-yo'qmi bilmasdi. `null` — hali urinilmagan (birinchi
  /// haqiqiy javobgacha, pastda ko'ring); `true`/`false` — so'nggi
  /// urinish natijasi.
  bool? _gpsAvailable;
  // Chayqalishni HAR safar (hatto ketma-ket ikki marta yuborishga
  // urinilsa ham) qayta ishga tushirish uchun — `highlighted` bool'ining
  // false→true chegarasiga tayanish yetarli emas edi.
  int _subjectShakeToken = 0;
  // Subyekt maydoni `_buildContent` ro'yxatining har doim BIRINCHI
  // elementi — shu sabab unga "scroll qilish" aslida shunchaki ro'yxatni
  // tepaga qaytarish bilan bir xil. `Scrollable.ensureVisible` (GlobalKey
  // orqali) amalda ishonchsiz chiqdi (ba'zida hech narsa qilmasdi);
  // to'g'ridan-to'g'ri kontroller bilan `animateTo(0)` — oddiyroq va
  // kafolatlangan.
  final _contentScrollController = ScrollController();

  Timer? _draftDebounce;
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _wasReady = _computeReady(widget.checklist);
    // Mini app har 30s'da "N/M javob berildi" yuboradi (rahbar tomonida
    // jonli kuzatuv uchun) — `EmployeeApi`da metod tayyor edi, lekin
    // hech qayerdan chaqirilmasdi. ⚠️ Avval bu yerda `setState(() {})`
    // ham chaqirilardi (vaqt-pillini yangilash uchun) — bu BUTUN katta
    // ekranni (ro'yxat, forma) har 30s'da qayta chizishga majburlardi,
    // foydalanuvchi "ekran vaqti-vaqti bilan sakraydi" deb xabar berdi.
    // Vaqt-pilli endi `_TimeLeftPill`ning O'Z alohida taymeri bilan
    // yangilanadi — bu yerda faqat tarmoq so'rovi qoladi.
    _tickTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      _reportProgressQuietly();
    });
    _contentScrollController.addListener(_checkViewedItems);
    // Qisqa checklist umuman scroll qilinmasligi ham mumkin — birinchi
    // kadrdan keyin bir marta tekshirmasak, hammasi "ko'rilmagan" bo'lib
    // qolardi.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkViewedItems();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // ⚠️ TOPILGAN BUG (foydalanuvchi: "javob 'Ha' tanlangan bo'lib
    // qolyapti, lekin chiqib qayta kirsa yo'qolib qoladi") — yuqoridagi
    // `build()`dagi izoh "javoblar allaqachon 1s debounce + lifecycle
    // flush bilan darhol saqlanadi" deb NOTO'G'RI faraz qilgan edi.
    // Amalda: foydalanuvchi savolga javob berib, 1 soniya ICHIDA orqaga
    // qaytsa (`Navigator.pop`/swipe — bu `AppLifecycleState`ni
    // o'ZGARTIRMAYDI, shuning uchun `didChangeAppLifecycleState` flush'i
    // ISHGA TUSHMAYDI), `_draftDebounce?.cancel()` navbatdagi saqlashni
    // BAJARILMASDAN bekor qilardi — oxirgi (ba'zan bir nechta) javob
    // qoralamaga hech qachon yozilmasdi. Endi: agar debounce hali FAOL
    // bo'lsa (ya'ni saqlanmagan o'zgarish bor), cancel qilishdan oldin
    // darhol (fire-and-forget) saqlaymiz. `_saveDraftNow()` ichidagi
    // `ref.read(...)` chaqiruvlari SINXRON (birinchi `await`dan oldin)
    // ishlaydi, shuning uchun bu yerda, widget hali to'liq
    // dispose bo'lmasdan turib chaqirish xavfsiz.
    if (_draftDebounce?.isActive ?? false) {
      unawaited(_saveDraftNow());
    }
    _draftDebounce?.cancel();
    _tickTimer?.cancel();
    _contentScrollController.removeListener(_checkViewedItems);
    _contentScrollController.dispose();
    super.dispose();
  }

  /// Mini app `IntersectionObserver(threshold: 0.5)` ekvivalenti — har bir
  /// savol kartasining kamida yarmi ekranda ko'rinib turgan payt "ko'rildi"
  /// deb belgilanadi. Faqat qo'shadi (`_viewedItemIds`), hech qachon UI
  /// qayta chizmaydi — natija faqat yuborishda tekshiriladi.
  void _checkViewedItems() {
    final screenHeight = MediaQuery.of(context).size.height;
    for (final entry in _itemKeys.entries) {
      if (_viewedItemIds.contains(entry.key)) continue;
      final renderObject = entry.value.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) continue;
      final top = renderObject.localToGlobal(Offset.zero).dy;
      final height = renderObject.size.height;
      if (height <= 0) continue;
      final visibleTop = top.clamp(0, screenHeight);
      final visibleBottom = (top + height).clamp(0, screenHeight);
      final visibleHeight = (visibleBottom - visibleTop).clamp(0, height);
      if (visibleHeight / height >= 0.5) {
        _viewedItemIds.add(entry.key);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Ilova fonga ketganda/yopilganda darhol majburiy saqlash — debounce
    // taymerini kutib o'tirmaydi (reja §2.5, "lifecycle inactive/paused").
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _draftDebounce?.cancel();
      _saveDraftNow();
    }
  }

  void _scheduleDraftSave() {
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(seconds: 1), _saveDraftNow);
  }

  Future<void> _saveDraftNow() async {
    await ref
        .read(draftServiceProvider)
        .save(
          checklistId: widget.checklistId,
          taskId: widget.taskId,
          locationId: widget.locationId,
          answers: _answers.values.where((a) => a.hasContent).toList(),
          subjectUserId: _subjectUserId,
          nowMs: ref.read(clockProvider).nowMs(),
        );
  }

  /// Mini app: `POST progress` faqat haqiqiy to'ldirish paytida (yakunlanmagan,
  /// yuborilmayotgan, inspeksiya allaqachon boshlangan) — natija hech qachon
  /// UI'ga ta'sir qilmaydi, xato bo'lsa jimgina o'tkazib yuboriladi ("fire and
  /// forget", mini app xuddi shunday).
  void _reportProgressQuietly() {
    final inspectionId = _earlyInspectionId;
    if (inspectionId == null || _submitting || _completedScreen != null) return;
    final total = widget.checklist.items.length;
    final answered = widget.checklist.items.where(_isAnswered).length;
    unawaited(
      ref
          .read(employeeApiProvider)
          .reportProgress(
            inspectionId,
            answeredCount: answered,
            totalCount: total,
          )
          .catchError((_) {}),
    );
  }

  Future<void> _clearDraft() => ref
      .read(draftServiceProvider)
      .clear(
        checklistId: widget.checklistId,
        taskId: widget.taskId,
        locationId: widget.locationId,
        nowMs: ref.read(clockProvider).nowMs(),
      );

  /// Bir martalik, "urinib ko'ramiz" (fire-and-forget) chaqiruv — birinchi
  /// haqiqiy javob yoki subyekt tanlovi kelishi bilan ishga tushadi.
  /// Muvaffaqiyatli bo'lsa `_earlyInspectionId` yakuniy yuborishda (yoki
  /// oflayn navbatga qo'yishda) qayta ishlatiladi — ikkinchi marta `start`
  /// chaqirilmaydi.
  ///
  /// ⚠️ Subyekt tanlovini KUTMAYDI: backend `start`da `subjectUserId`ni
  /// `subjectEmployee` chek-list uchun ham IXTIYORIY qiladi (xodim ishga
  /// kelmagan bo'lsa ham tekshiruv boshlanaveradi). Shuning uchun xodim
  /// subyektni tanlashdan OLDIN savollarga javob bersa ham, "jarayonda"
  /// holati darhol serverga yetadi — subyekt keyinroq [_maybeUpdateSubject]
  /// orqali ulanadi.
  /// Geofencing MAJBURIY bo'lgan filialda `GeofenceGate` allaqachon GPS'ni
  /// muvaffaqiyatli olib bo'lgan — shu qiymat qayta so'ralmasdan
  /// ishlatiladi. Aks holda (majburiy emas) mavjud jim yo'l davom etadi.
  Future<({double lat, double lng})?> _resolveGps() async {
    if (widget.verifiedGpsLat != null && widget.verifiedGpsLng != null) {
      return (lat: widget.verifiedGpsLat!, lng: widget.verifiedGpsLng!);
    }
    return getGpsQuietly();
  }

  Future<void> _maybeEagerStart() async {
    if (_earlyInspectionId != null || _earlyStartInFlight) return;
    _earlyStartInFlight = true;
    try {
      final gps = await _resolveGps();
      if (mounted) setState(() => _gpsAvailable = gps != null);
      // Telefon soatida (server bilan skew-tuzatilgan) haqiqiy boshlanish
      // momenti — oflayn bo'lsa ham darhol yozib qo'yamiz, server buni
      // task vaqt oynasi ichiga tushsa qabul qiladi ([[project_client_started_at]]).
      final clientStartedAt = DateTime.fromMillisecondsSinceEpoch(
        ref.read(clockProvider).nowMs(),
      );
      final id = await ref
          .read(employeeApiProvider)
          .startInspection(
            checklistId: widget.checklistId,
            locationId: widget.locationId,
            scheduleTaskId: widget.taskId,
            subjectUserId: _subjectUserId,
            gpsLat: gps?.lat,
            gpsLng: gps?.lng,
            clientStartedAt: clientStartedAt,
          );
      if (mounted) _earlyInspectionId = id;
      // Ro'yxat (`/`) "jarayonda" holatini darhol ko'rsatsin — ekrandan
      // hali chiqmagan bo'lsak ham, keyingi safar qaytilganda yangi
      // holatni oladi (`ref.invalidate` shart emas, chunki o'sha ekran
      // qaytilganda o'zi qayta yuklaydi).
    } catch (_) {
      // Oflayn yoki server xatosi — jimgina o'tkazib yuboriladi.
      // `_earlyInspectionId` hamon `null`, shu sabab KEYINGI javobda
      // (foydalanuvchi onlaynga qaytgan bo'lishi mumkin) avtomatik
      // qayta urinib ko'riladi — yakuniy yuborish/oflayn navbat esa
      // hamon o'z zaxira `start`iga ega (butunlay oflayn qolsa ham).
    } finally {
      _earlyStartInFlight = false;
    }
  }

  /// Eager-start subyekt hal qilinishidan OLDIN yuborilgan bo'lsa (yuqoridagi
  /// izohga qarang), subyekt endi tanlanganda serverdagi inspeksiyaga
  /// ulaydi. Fire-and-forget — muvaffaqiyatsiz bo'lsa yakuniy `complete`
  /// baribir to'g'ri `subjectUserId` bilan ketmaydi, lekin bu chekka holat
  /// (tarmoq xatosi shu aniq lahzada) va navbatdagi `_saveDraftNow`/submit
  /// urinishlari ta'sir qilmaydi.
  Future<void> _maybeUpdateSubject(String? subjectUserId) async {
    final id = _earlyInspectionId;
    if (id == null) return;
    try {
      await ref.read(employeeApiProvider).updateSubject(id, subjectUserId);
    } catch (_) {
      // jimgina o'tkazib yuboriladi
    }
  }

  void _setAnswer(String itemId, InspectionAnswerDraft draft) {
    _interactedItemIds.add(itemId);
    setState(() => _answers[itemId] = draft);
    _scheduleDraftSave();
    _maybeEagerStart();
    _maybeAutoCollapseSection(itemId);
    _maybeNotifyReady();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkViewedItems();
    });
  }

  bool _computeReady(Checklist checklist) {
    final hasAnyAnswer = _answers.values.any((a) => a.hasContent);
    return hasAnyAnswer && _missingRequired(checklist).isEmpty;
  }

  /// Mini app: barcha majburiy savollar javoblanmagan → javoblangan holatiga
  /// o'tgan ("tayyor" chegarasini birinchi marta kesib o'tgan) paytda BIR
  /// MARTA muvaffaqiyat haptic'i beriladi — footer tugmasi yashilga
  /// o'tishi bilan sinxron. Faqat chegarani KESIB O'TGANDA (`!_wasReady`),
  /// har bir keyingi javobda emas.
  void _maybeNotifyReady() {
    final ready = _computeReady(widget.checklist);
    if (ready && !_wasReady) {
      notificationHaptic();
    }
    _wasReady = ready;
  }

  /// Uzoq checklist'larda (≥30 savol, ≥3 bo'lim) bo'lim to'liq javoblansa
  /// bir marta o'z-o'zidan yig'iladi — ekranni bo'shatib, keyingi bo'limga
  /// e'tiborni yo'naltiradi. `_autoCollapsedOnce` ORQALI faqat bir marta
  /// (qo'lda qayta ochilsa qayta majburlanmaydi) — manba: `Inspect.tsx`
  /// auto-collapse qoidasi.
  void _maybeAutoCollapseSection(String changedItemId) {
    final groups = buildInspectSectionGroups(widget.checklist.items);
    if (widget.checklist.items.length < 30 || groups.length < 3) return;

    for (var g = 0; g < groups.length; g++) {
      final group = groups[g];
      if (!group.items.any((i) => i.id == changedItemId)) continue;
      final collapsible = group.title.isNotEmpty && group.items.length >= 2;
      if (!collapsible) return;
      final key = 'g$g:${group.title}';
      if (_autoCollapsedOnce.contains(key)) return;
      if (group.items.every(_isAnswered)) {
        _autoCollapsedOnce.add(key);
        // Bir zumga kechiktirilgan — foydalanuvchi so'nggi javobini ko'rib
        // ulguradi, keyin bo'lim silliq yig'iladi.
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) setState(() => _collapsed.add(key));
        });
      }
      return;
    }
  }

  bool _isAnswered(ChecklistItem item) =>
      isItemAnswered(item.type, _answers[item.id]);

  bool _isViolation(ChecklistItem item) {
    final value = _answers[item.id]?.value;
    if (value == null || value.isEmpty) return false;
    return isRatingViolation(
      item.type,
      value,
      _scoreConfig,
      maxScore: item.maxScore,
    );
  }

  List<ChecklistItem> _missingRequired(Checklist checklist) {
    // ⚠️ `isItemAnswered` (izoh: `core/shared_logic/answer_completeness.dart`)
    // — progress halqasi bilan BIR XIL, turga qarab qat'iy tekshiruv.
    // Ilgari bu yerda alohida (deyarli bir xil, lekin mustaqil) mantiq
    // bor edi — ikkalasi ketma-ket tuzatilib, sinxronlikni saqlash
    // qiyinlashgandi. Endi yagona manba.
    return checklist.items
        .where(
          (item) =>
              item.required && !isItemAnswered(item.type, _answers[item.id]),
        )
        .toList();
  }

  /// ⚠️ Mobil audit topilmasi: `NUMBER` maydoni faqat klaviatura TURI
  /// (`numberWithOptions`) bilan "cheklangan" edi — bu yumshoq maslahat,
  /// haqiqiy filtr emas (joylashtirish/avtomatik to'ldirish orqali "abc"
  /// yoki "12.34.56" kabi raqam bo'lmagan matn kiritilishi mumkin edi).
  /// `_formKey`/`Form` skeleti allaqachon mavjud bo'lsa-da, HECH QACHON
  /// `.validate()` chaqirilmasdi — shu sabab bu yerda alohida, engil
  /// tekshiruv: bo'sh bo'lmagan, lekin haqiqiy son bo'lmagan `NUMBER`
  /// javoblari.
  List<ChecklistItem> _invalidNumbers(Checklist checklist) {
    return checklist.items.where((item) {
      if (item.type != 'NUMBER') return false;
      final value = _answers[item.id]?.value?.trim();
      if (value == null || value.isEmpty) return false;
      return double.tryParse(value) == null;
    }).toList();
  }

  /// `photoRequired`/`videoRequired` bayrog'i qo'shimcha dalil talab qiladi
  /// — asosiy javobdan MUSTAQIL. `PHOTO` turdagi savollar bu yerga
  /// kirmaydi (ularning yagona javobi — rasmning o'zi, allaqachon
  /// [_missingRequired] tomonidan qamrab olingan).
  List<({ChecklistItem item, bool photo, bool video})> _missingMedia(
    Checklist checklist,
  ) {
    final out = <({ChecklistItem item, bool photo, bool video})>[];
    for (final item in checklist.items) {
      if (item.type == 'PHOTO') continue;
      if (!item.photoRequired && !item.videoRequired) continue;
      final answer = _answers[item.id];
      // ⚠️ Avval bu yerda savolning O'ZI javoblanganmi tekshirilmasdi —
      // hali umuman TEGILMAGAN savol ham (masalan `required: false`
      // bo'lsa ham) darhol "rasm/video yetishmayapti" qattiq to'sig'iga
      // tushib qolardi (`_showMissingMediaSheet` — faqat "o'sha savolga
      // o'tish" imkoni bor, o'tkazib yuborib yuborish yo'q). Manba
      // (`Inspect.tsx`): `missingPhotos = ... i.photoRequired &&
      // answers[i.id!] && ...` — FAQAT savolga javob berilgan bo'lsa
      // tekshiradi. Bu tuzatilgach, hali tegilmagan majburiy savol
      // avvalgidek yumshoqroq "javobsiz savollar" tasdiq varag'iga
      // tushadi (pastda), qattiq to'siqqa emas.
      if (answer == null || answer.value == null || answer.value!.isEmpty) {
        continue;
      }
      final hasPhoto =
          answer.photoFileIds.isNotEmpty ||
          answer.pendingPhotoUploadIds.isNotEmpty;
      final hasVideo =
          answer.videoFileIds.isNotEmpty ||
          answer.pendingVideoUploadIds.isNotEmpty;
      final photoMissing = item.photoRequired && !hasPhoto;
      final videoMissing = item.videoRequired && !hasVideo;
      if (photoMissing || videoMissing) {
        out.add((item: item, photo: photoMissing, video: videoMissing));
      }
    }
    return out;
  }

  Future<void> _onSubmitPressed(Checklist checklist) async {
    // ⚠️ Mobil audit topilmasi (ixtiyoriy/himoya qatlami): `_submitting`
    // avval faqat `_submit()` ICHIDA, birinchi `setState` orqali
    // o'rnatilardi — bu `setState` keyingi frame'gacha tugmani vizual/
    // interaktiv jihatdan o'chirmaydi. Nazariy jihatdan juda tor vaqt
    // oynasida (bitta frame ichida) qo'sh bosish ikkita chaqiruvni ham
    // shu yerga kirishga imkon berardi. Endi shu yerning O'ZIDA,
    // HECH QANDAY `await`dan OLDIN sinxron himoya — `media_answer_
    // picker.dart`dagi `_picking` naqshi bilan bir xil.
    if (_submitting) return;
    final l10n = AppLocalizations.of(context);

    if (checklist.subjectEmployee && !_subjectDecided) {
      final candidates =
          ref.read(subjectCandidatesProvider(widget.checklistId)).valueOrNull ??
          const [];
      if (candidates.isNotEmpty) {
        setState(() => _subjectHighlighted = true);
        notificationHaptic(success: false);
        // Subyekt maydoni ro'yxatning har doim BIRINCHI elementi — shu
        // sabab tepaga qaytarish yetarli (`Scrollable.ensureVisible`
        // GlobalKey orqali ishonchsiz chiqdi, ba'zida hech narsa
        // qilmasdi).
        if (_contentScrollController.hasClients) {
          // Davomiylik masofaga qarab — qisqa masofada tez, uzoq
          // masofada sekinroq (haqiqiy qo'l bilan flick qilingandek,
          // doim bir xil 300ms emas). Egri chiziq ham `easeOut` o'rniga
          // `easeOutCubic` — oxiriga borgan sari sezilarli sekinlashadi,
          // "tabiiy to'xtash" hissi beradi.
          final distance = _contentScrollController.offset;
          final duration = Duration(
            milliseconds: (280 + distance * 0.35).clamp(280, 900).round(),
          );
          await _contentScrollController.animateTo(
            0,
            duration: duration,
            curve: Curves.easeOutCubic,
          );
        }
        // Chayqalish scroll TUGAGANDAN keyin — aks holda uzoq masofada
        // (foydalanuvchi pastda bo'lsa) animatsiya maydon hali ko'rinishga
        // kelmasdanoq tugab qolardi.
        if (mounted) setState(() => _subjectShakeToken++);
        return;
      }
    }

    final missingMedia = _missingMedia(checklist);
    if (missingMedia.isNotEmpty) {
      final target = await _showMissingMediaSheet(l10n, missingMedia);
      if (target != null) _scrollToItem(target, flash: true);
      return;
    }

    final invalidNumbers = _invalidNumbers(checklist);
    if (invalidNumbers.isNotEmpty) {
      notificationHaptic(success: false);
      showAppToast(context, l10n.inspectInvalidNumber, type: ToastType.error);
      _scrollToItem(invalidNumbers.first.id, flash: true);
      return;
    }

    // ⚠️ Majburiy javoblar to'liqligi (`_missingRequired`) endi BU YERDA
    // qayta tekshirilmaydi va "davom etish" varag'i ko'rsatilmaydi —
    // `_buildFooter`dagi tugma o'zi `ready` (=`_missingRequired().isEmpty`)
    // bo'lmaguncha BOSILMAYDI (izoh: o'sha yerda). Foydalanuvchi
    // topilmasi: "majburiy savollarga javob berilmasidan oldin finish
    // aktiv ko'rinyapti" — avval shu yerda "bypass" imkoni bo'lgani
    // sabab, backend baribir rad etib, chalkash (tarjima qilinmagan)
    // xato ko'rsatardi. Endi bu holatga umuman yetib bo'lmaydi.

    final blindDefaults = _blindDefaults(checklist);
    if (blindDefaults.isNotEmpty) {
      if (widget.requireViewAll) {
        notificationHaptic(success: false);
        final target = await _showBlindDefaultsBlockedSheet(
          l10n,
          blindDefaults,
        );
        _scrollToItem(target ?? blindDefaults.first.id);
        return;
      }
      final proceed = await _showBlindDefaultsConfirmSheet(l10n, blindDefaults);
      if (proceed != true) {
        _scrollToItem(blindDefaults.first.id);
        return;
      }
    }

    await _submit(checklist);
  }

  /// Mini app `blindDefaults`: `prefillYes` orqali "Ha" bilan oldindan
  /// to'ldirilgan, LEKIN xodim hech qachon qo'l bilan tegmagan VA ekranda
  /// hech qachon (kamida yarmi) ko'rinmagan majburiy YES_NO savollar —
  /// ya'ni ehtimol shunchaki rubber-stamp qilib o'tkazib yuborilgan
  /// javoblar. Faqat `widget.prefillYes` yoqilganda ma'noli (aks holda
  /// hech qanday avtomatik qiymat yo'q).
  List<ChecklistItem> _blindDefaults(Checklist checklist) {
    if (!widget.prefillYes) return const [];
    return checklist.items.where((item) {
      if (!item.required || item.type != 'YES_NO') return false;
      if (_answers[item.id]?.value != 'Ha') return false;
      return !_interactedItemIds.contains(item.id) &&
          !_viewedItemIds.contains(item.id);
    }).toList();
  }

  Future<void> _submit(Checklist checklist) async {
    setState(() {
      _submitting = true;
      _submitError = null;
    });

    final answers = checklist.items
        .map(
          (item) => _answers[item.id] ?? InspectionAnswerDraft(itemId: item.id),
        )
        .where((a) => a.hasContent)
        .toList();

    // Biror javobda hali serverga yetib bormagan (lokal navbatdagi) media
    // bo'lsa, `complete`ga umuman urinilmaydi — to'g'ridan-to'g'ri oflayn
    // navbatga o'tadi. `SyncService` mediani hal qilib bo'lgach o'zi
    // yuboradi (reja §3.2: "Media inspeksiyadan OLDIN").
    final hasUnresolvedMedia = answers.any((a) => a.hasUnresolvedMedia);
    if (hasUnresolvedMedia) {
      // ⚠️ Topilma: bu `return` avval `try` blokidan TASHQARIDA edi — pastdagi
      // `finally` (`_submitting = false`) hech qachon ishlamas, `enqueue()`
      // xato bersa tugma abadiy o'chgan holda qolar edi.
      try {
        await _enqueueOffline(checklist, answers);
      } finally {
        if (mounted) setState(() => _submitting = false);
      }
      return;
    }

    final api = ref.read(employeeApiProvider);
    // Telefon soatidagi (server bilan skew-tuzatilgan) haqiqiy tugash
    // momenti — tugmaga bosilgan aynan shu lahzada, tarmoq kutish
    // vaqtidan OLDIN olinadi ([[project_client_started_at]]).
    final clientCompletedAt = DateTime.fromMillisecondsSinceEpoch(
      ref.read(clockProvider).nowMs(),
    );
    try {
      // `_maybeEagerStart` allaqachon muvaffaqiyatli bo'lgan bo'lsa —
      // ikkinchi marta `start` chaqirilmaydi (ikkita alohida inspeksiya
      // yaratib qo'yardi).
      var inspectionId = _earlyInspectionId;
      if (inspectionId == null) {
        final gps = await _resolveGps();
        inspectionId = await api.startInspection(
          checklistId: widget.checklistId,
          locationId: widget.locationId,
          scheduleTaskId: widget.taskId,
          subjectUserId: _subjectUserId,
          gpsLat: gps?.lat,
          gpsLng: gps?.lng,
          clientStartedAt: clientCompletedAt,
        );
        // ⚠️ Topilma: `start` shu yerda muvaffaqiyatli bo'lib, keyingi
        // `completeInspection` tarmoq xatosi bilan yiqilsa, `inspectionId`
        // saqlanmasa `_enqueueOffline` `startedInspectionId: null` uzatib
        // qo'yardi — `SyncService` qayta `start` chaqirib, serverda ikkinchi,
        // yetim `IN_PROGRESS` inspeksiya yaratardi. Endi darhol saqlanadi —
        // pastdagi `catch` yo'lida ham xuddi shu ID qayta ishlatiladi.
        _earlyInspectionId = inspectionId;
      }
      final result = await api.completeInspection(
        inspectionId,
        answers,
        clientCompletedAt: clientCompletedAt,
      );

      if (!mounted) return;
      await _clearDraft();
      if (!mounted) return;
      ref.invalidate(tasksControllerProvider);
      _replaceWithResult(
        InspectionResultScreen(
          checklistTitle: checklist.title,
          score: (result['score'] as num?)?.toDouble(),
          inspectionId: inspectionId,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      // ⚠️ Foydalanuvchi topilmasi: birinchi urinish serverga YETIB
      // BORGAN va saqlangan bo'lishi mumkin, lekin javob mijozga
      // yetmagan (tarmoq/qisqa server uzilishi) — xodim qo'lda qayta
      // bossa, backend to'g'ri ravishda "allaqachon yakunlangan"
      // qaytaradi. `SyncService` (oflayn navbat, izoh: shu fayl)
      // buni ALLAQACHON muvaffaqiyat deb qabul qiladi — to'g'ridan-
      // to'g'ri (onlayn) yo'l esa yo'q edi, xodim buni yana bir xato
      // deb ko'rardi, garchi ishi aslida saqlangan bo'lsa ham.
      if (e.code == 'ALREADY_COMPLETED' && _earlyInspectionId != null) {
        await _clearDraft();
        if (!mounted) return;
        ref.invalidate(tasksControllerProvider);
        _replaceWithResult(
          InspectionResultScreen(
            checklistTitle: checklist.title,
            score: null,
            inspectionId: _earlyInspectionId!,
          ),
        );
        return;
      }
      if (e.kind == ApiErrorKind.serverReject) {
        _showRejectDialog(e);
      } else if (e.kind == ApiErrorKind.network) {
        // Tarmoq yo'q/uzildi — foydalanuvchi bloklanmaydi: to'ldirilgan
        // javob oflayn navbatga qo'yiladi va keyinroq avtomatik yuboriladi
        // (reja §0: "xodimning ishi muqaddas").
        await _enqueueOffline(checklist, answers);
      } else {
        setState(() => _submitError = e.message);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _enqueueOffline(
    Checklist checklist,
    List<InspectionAnswerDraft> answers,
  ) async {
    await ref
        .read(syncServiceProvider)
        .enqueue(
          checklistId: widget.checklistId,
          checklistTitle: checklist.title,
          locationId: widget.locationId,
          scheduleTaskId: widget.taskId,
          answers: answers,
          // `_maybeEagerStart` muvaffaqiyatli bo'lgan bo'lsa — shu ID
          // ishlatiladi, `SyncService` qayta `start` chaqirmaydi.
          startedInspectionId: _earlyInspectionId,
          // ⚠️ Topilma: avval uzatilmasdi — `subjectEmployee` checklist
          // oflayn navbatga tushganda kim tekshirilgani yo'qolib ketardi.
          subjectUserId: _subjectUserId,
        );
    if (!mounted) return;
    await _clearDraft();
    if (!mounted) return;
    ref.invalidate(tasksControllerProvider);
    _replaceWithResult(
      InspectionResultScreen(
        checklistTitle: checklist.title,
        savedOffline: true,
      ),
    );
  }

  /// Yuborilgach natija ekrani ko'rsatiladi. ⚠️ Avval bu yerda
  /// `Navigator.of(context).pop()` + `push(MaterialPageRoute(...))`
  /// ishlatilgan edi — bu XATO edi: `/inspect/:checklistId` go_router
  /// tomonidan DEKLARATIV boshqariladigan sahifa, uning ustiga
  /// IMPERATIV `push` qilingan sahifa go_router'ning `pages` ro'yxatida
  /// umuman ko'rinmaydi. Natijada natija ekranidagi "Bosh sahifa"
  /// tugmasi `context.go('/')` chaqirsa ham, go_router o'zining
  /// deklarativ ro'yxatini '/'ga moslab qayta qursa-da, o'sha imperativ
  /// sahifa Navigator tarixida ustma-ust qolib ketardi — ekran
  /// almashmasdi (foydalanuvchi xabar berdi: "u tugma ishlamas edi").
  /// Endi hech qanday Navigator chaqiruvisiz — shu SAHIFANING o'zi
  /// ichida holat almashtiriladi (`_completedScreen`), `build()` shuni
  /// tekshiradi. Shu tufayli `context.go('/')` toza, hech narsaga
  /// aralashmagan go_router holatidan chaqiriladi.
  void _replaceWithResult(Widget resultScreen) {
    if (!mounted) return;
    setState(() => _completedScreen = resultScreen);
  }

  // ⚠️ Qizil "chaqnash" (flash) FAQAT foto/video yetishmagan savolga
  // yo'naltirilganda ko'rsatiladi — mini app manbasida ("Inspect.tsx")
  // `setFlashItemId` faqat shu holatda chaqiriladi. "Savolga o'tish"
  // popoveridan va "javobsiz majburiy savollar" ro'yxatidan sakrashda
  // bu XATO emas, oddiy navigatsiya — shu sabab qizil emas. Lekin
  // hech qanday belgisiz ham bo'lmadi: foydalanuvchi qaysi savolga
  // kelganini bilolmadi (scroll pozitsiyasi yolg'iz yetarli emas ekan,
  // real sinovda aniqlandi). Shu sabab neytral (primary rangli, qisqa)
  // ko'rsatkich qo'shildi — "mana shu" degan ma'noda, xato emas.
  void _scrollToItem(String itemId, {bool flash = false}) {
    // Birinchi/oxirgi savol bo'lsa — `ensureVisible`ning "tepadan 8%"
    // tekislashi ishlay olmaydi (birinchisida tepasida, oxirgisida
    // pastida to'ldiradigan kontent yetarli emas), natijada keskin/chala
    // scroll bo'lardi. Bunday holatda ro'yxatning O'ZINI (subyekt/footer
    // bilan birga) chetigacha aylantirish tabiiyroq.
    final isFirstItem =
        _itemKeys.keys.isNotEmpty && _itemKeys.keys.first == itemId;
    final isLastItem =
        _itemKeys.keys.isNotEmpty && _itemKeys.keys.last == itemId;
    if ((isFirstItem || isLastItem) && _contentScrollController.hasClients) {
      final target = isLastItem
          ? _contentScrollController.position.maxScrollExtent
          : 0.0;
      final distance = target - _contentScrollController.offset;
      final duration = Duration(
        milliseconds: (280 + distance.abs() * 0.35).clamp(280, 900).round(),
      );
      _contentScrollController.animateTo(
        target,
        duration: duration,
        curve: Curves.easeOutCubic,
      );
    } else {
      final ctx = _itemKeys[itemId]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          alignment: 0.08,
        );
      }
    }
    if (flash) {
      setState(() => _flashedItemId = itemId);
      Future.delayed(const Duration(milliseconds: 1400), () {
        if (mounted && _flashedItemId == itemId) {
          setState(() => _flashedItemId = null);
        }
      });
      return;
    }
    setState(() => _jumpHighlightItemId = itemId);
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted && _jumpHighlightItemId == itemId) {
        setState(() => _jumpHighlightItemId = null);
      }
    });
  }

  /// "Savolga o'tish" — progress-halqa tugmasi ostida muallaq (floating)
  /// popover sifatida ochiladi. ⚠️ Avval `showMenu` (Flutter tayyor
  /// mexanizmi) ishlatilgan edi — lekin foydalanuvchi buni ham "arzon"
  /// deb topdi: orqa fon qorong'ilashmasdan popover kontent bilan
  /// aralashib ko'rinardi, tugma bilan vizual bog'liqlik (o'q/strelka)
  /// yo'q edi. Shu sabab endi to'liq qo'lda — o'z `Overlay` qatlami:
  /// xira orqa fon (barrier), tugma tomon "o'sib chiquvchi" scale+fade
  /// animatsiya, va kartaning tepasidan tugmaga qarab chiquvchi kichik
  /// uchburchak ko'rsatkich (vizual "shu tugmadan kelib chiqdi" signali).
  Future<void> _showJumpMenu(BuildContext context, Checklist checklist) async {
    final button =
        _ringButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final overlayState = Overlay.of(context);
    final overlayBox = overlayState.context.findRenderObject() as RenderBox?;
    if (button == null || overlayBox == null) return;

    // ⚠️ Avval `topRight` ishlatilgan edi — popover tugmaning YUQORISIGA
    // yopishardi, ya'ni deyarli AppBar sarlavhasi balandligida chiqib,
    // uni yopib qo'yardi ("qalqib chiquvchi oyna noto'g'ri joyga chiqib
    // qolgan"). `bottomRight` — popover tugmaning PASTIDAN, butun
    // AppBar'dan keyin boshlanadi.
    final buttonTopRight = button.localToGlobal(
      button.size.bottomRight(Offset.zero),
      ancestor: overlayBox,
    );
    final buttonCenterX = button
        .localToGlobal(Offset(button.size.width / 2, 0), ancestor: overlayBox)
        .dx;

    late OverlayEntry entry;
    final completer = Completer<void>();
    void close() {
      if (entry.mounted) entry.remove();
      if (!completer.isCompleted) completer.complete();
    }

    entry = OverlayEntry(
      builder: (overlayContext) => _JumpMenuOverlay(
        top: buttonTopRight.dy + 8,
        rightInset: overlayBox.size.width - buttonTopRight.dx,
        pointerCenterX: buttonCenterX,
        onDismiss: close,
        child: _JumpGridContent(
          items: _orderedItems(checklist),
          isAnswered: _isAnswered,
          onTapIndex: (id) {
            close();
            selectionHaptic();
            _scrollToItem(id);
          },
          // ⚠️ Avval "Boshidan boshlash" Finish tugmasi YONIDA, pastki
          // qatorda turardi — yo'q qiluvchi harakat asosiy CTA'ga juda
          // yaqin edi. Foydalanuvchi bilan kelishilgan holda bu yerga,
          // "boshqaruv" sirtiga ko'chirildi.
          onReset: _answers.isEmpty
              ? null
              : () {
                  close();
                  _confirmReset(checklist);
                },
        ),
      ),
    );
    overlayState.insert(entry);
    return completer.future;
  }

  /// Bottom sheet: foto/video kerak bo'lgan lekin yuklanmagan savollar.
  /// Qaytaradi — tanlangan savol id'si (bosilsa o'sha yerga o'tiladi) yoki
  /// `null` (shunchaki yopilgan).
  Future<String?> _showMissingMediaSheet(
    AppLocalizations l10n,
    List<({ChecklistItem item, bool photo, bool video})> missing,
  ) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      // ⚠️ `shape` — `AppTheme.bottomSheetTheme.shape` allaqachon shu
      // qiymatni global standart sifatida beradi, qo'lda takrorlash
      // ortiqcha edi.
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.inspectMissingMediaTitle,
                style: Theme.of(sheetContext).textTheme.headlineMedium,
              ),
              const SizedBox(height: 4),
              Text(
                l10n.inspectMissingMediaDesc,
                style: Theme.of(sheetContext).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              ...missing
                  .take(6)
                  .map(
                    (m) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: AppColors.danger500.withValues(
                          alpha: 0.12,
                        ),
                        child: Icon(
                          m.photo ? LucideIcons.camera : LucideIcons.video,
                          size: 13,
                          color: dark
                              ? AppColors.danger500
                              : AppColors.danger600,
                        ),
                      ),
                      title: Text(
                        m.item.question,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        m.photo
                            ? l10n.inspectPhotoRequiredLabel
                            : l10n.inspectVideoRequiredLabel,
                        style: TextStyle(
                          color: dark
                              ? AppColors.danger500
                              : AppColors.danger600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: const Icon(LucideIcons.chevronRight, size: 16),
                      onTap: () => Navigator.of(sheetContext).pop(m.item.id),
                    ),
                  ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: PlatformButton(
                  backgroundColor: AppColors.primary600,
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: Text(l10n.inspectReview),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Bottom sheet: `prefillYes` bilan to'ldirilgan, LEKIN xodim hech qachon
  /// ko'rmagan/tegmagan majburiy javoblar — YUMSHOQ tasdiq
  /// (`requireViewAll` o'chirilganda). `true` — "Ha, tasdiqlash" bosildi.
  Future<bool?> _showBlindDefaultsConfirmSheet(
    AppLocalizations l10n,
    List<ChecklistItem> blind,
  ) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      // ⚠️ `shape` — `AppTheme.bottomSheetTheme.shape` allaqachon shu
      // qiymatni global standart sifatida beradi, qo'lda takrorlash
      // ortiqcha edi.
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.inspectUnviewedTitle,
                style: Theme.of(sheetContext).textTheme.headlineMedium,
              ),
              const SizedBox(height: 4),
              Text(
                l10n.inspectUnviewedConfirm('${blind.length}'),
                style: Theme.of(sheetContext).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              ..._blindDefaultRows(
                blind,
                onTap: (id) {
                  Navigator.of(sheetContext).pop(false);
                  _scrollToItem(id);
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(false),
                      child: Text(l10n.commonCancel),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PlatformButton(
                      backgroundColor: AppColors.primary600,
                      onPressed: () => Navigator.of(sheetContext).pop(true),
                      child: Text(l10n.inspectUnviewedConfirmBtn),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Bottom sheet: xuddi shu holat, lekin `requireViewAll` yoqilgan —
  /// QATTIQ blok, "Bekor qilish" yo'q, faqat ko'rib chiqishga majburlaydi.
  /// Qaytaradi — bosilgan savol id'si (yopilsa `null`, chaqiruvchi
  /// birinchi elementga o'tadi).
  Future<String?> _showBlindDefaultsBlockedSheet(
    AppLocalizations l10n,
    List<ChecklistItem> blind,
  ) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      // ⚠️ `shape` — `AppTheme.bottomSheetTheme.shape` allaqachon shu
      // qiymatni global standart sifatida beradi, qo'lda takrorlash
      // ortiqcha edi.
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.inspectUnviewedTitle,
                style: Theme.of(sheetContext).textTheme.headlineMedium,
              ),
              const SizedBox(height: 4),
              Text(
                l10n.inspectUnviewedBlockedDesc('${blind.length}'),
                style: Theme.of(sheetContext).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              ..._blindDefaultRows(
                blind,
                onTap: (id) => Navigator.of(sheetContext).pop(id),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: PlatformButton(
                  backgroundColor: AppColors.primary600,
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: Text(l10n.inspectReview),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _blindDefaultRows(
    List<ChecklistItem> blind, {
    required ValueChanged<String> onTap,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return blind.take(6).map((item) {
      final idx = blind.indexOf(item) + 1;
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          radius: 12,
          backgroundColor: AppColors.warning500.withValues(alpha: 0.15),
          child: Text(
            '$idx',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: dark ? AppColors.warning500 : AppColors.warning600,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        title: Text(
          item.question,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(LucideIcons.chevronRight, size: 16),
        onTap: () => onTap(item.id),
      );
    }).toList();
  }

  Future<void> _showRejectDialog(ApiException e) async {
    final l10n = AppLocalizations.of(context);
    // Server "sabab" qaytardi (masalan hamkasb allaqachon bajargan) — bu
    // xato emas, tinch xabar sifatida ko'rsatiladi (reja §3.5). Terminal
    // holat (`serverReject`) — QAYTA URINISH degan tugma noto'g'ri: hech
    // narsa qayta yuborilmaydi, pastda shu ekrandan har doim chiqib
    // ketiladi. ⚠️ Avval tugma `inspectRetry` ("Qayta urinish") deb
    // nomlangan edi — real harakati faqat yopish/qaytish bo'lsa-da.
    await showInfoSheet(
      context,
      title: l10n.inspectStartErrorTitle,
      message: e.message,
      actionText: l10n.inspectUnderstood,
    );
    // Terminal rad (masalan hamkasb allaqachon bajargan) — bu holatda
    // eskirgan javoblar bilan shu ekranda qolishning ma'nosi yo'q,
    // to'g'ridan-to'g'ri Tekshiruv ro'yxatiga qaytariladi.
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_completedScreen != null) return _completedScreen!;

    final l10n = AppLocalizations.of(context);
    final checklist = widget.checklist;
    final total = checklist.items.length;
    final answered = checklist.items.where(_isAnswered).length;
    final progress = total == 0 ? 0.0 : answered / total;

    // ⚠️ Avval bu yerda `PopScope(canPop:false, ...)` + tasdiqlash oynasi
    // bor edi — "javoblar yo'qolib ketmasin" degan xavotirdan. Bu xavotir
    // asosli ekan (foydalanuvchi keyinroq aynan shuni topdi: 1s debounce
    // ichida orqaga qaytilsa oxirgi javob saqlanmasdan qolardi) — lekin
    // to'g'ri yechim PopScope BLOKLASH emas, balki `dispose()`da
    // saqlanmagan o'zgarishni darhol flush qilish edi (qarang: `dispose()`
    // ichidagi izoh). Endi bu ta'minlangan, shuning uchun orqaga/swipe
    // HAR DOIM erkin qoladi — bloklashning haqiqiy zarurati yo'q, faqat
    // saqlash o'zi ishonchli bo'lishi kerak edi.
    // Media yuklash navigatsiyadan mustaqil fon rejimida davom etadi
    // (`MediaQueueService` — natija to'g'ridan-to'g'ri bazaga yoziladi,
    // ekran ochiqmi yo'qmi buning uchun ahamiyatsiz).
    return Scaffold(
      // ⚠️ Bu ekran ilovaning "asosiy" (kanonik) orqaga+sarlavha AppBar
      // andozasi — endi umumiy `DetailAppBar`ga chiqarilgan (foydalanuvchi:
      // "keyingi andozalarni undan olsak bo'ladi"), boshqa tafsilot
      // ekranlari ham shu yerdan foydalanadi. Chap/o'ng chetlar sahifa
      // tanasi (`_buildContent`ning `ListView` padding'i) bilan bir xil
      // 16px'ga tekislangan.
      appBar: DetailAppBar(
        title: checklist.title,
        actions: [
          if (widget.taskId != null) _TimeLeftPill(taskId: widget.taskId!),
          // ⚠️ Foydalanuvchi: "ba'zi sahifalarda avvaldan to'g'irlangan
          // ekan. bo'sh joy ikki marta qo'llandi" — bu yerdagi
          // `Padding(right: 16)` `DetailAppBar`ning YANGI markazlashtirilgan
          // `actionsPadding`idan OLDIN, chekka masofasi yetarli
          // bo'lmagani uchun qo'lda qo'shilgan edi. Ikkalasi qo'shilib
          // 24px bo'lib qolgandi — endi olib tashlandi, markazlashtirilgan
          // 8px yetarli.
          KeyedSubtree(
            key: _ringButtonKey,
            child: _ProgressRingButton(
              progress: progress,
              onTap: () => _showJumpMenu(context, checklist),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(child: _buildContent(context, l10n, checklist)),
            _buildFooter(context, l10n, checklist),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    AppLocalizations l10n,
    Checklist checklist,
  ) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final groups = buildInspectSectionGroups(checklist.items);

    final hasSubject = checklist.subjectEmployee;
    final hasDescription = checklist.description?.isNotEmpty == true;

    return ListView(
      controller: _contentScrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      children: [
        // Filial/joylashuv — manba `Inspect.tsx` sarlavha ostidagi
        // `MapPin` meta-qatorining porti (⚠️ avval mobilda umuman
        // ko'rsatilmasdi). `locationName` bo'lmasa (ad-hoc checklist,
        // filialga bog'liq emas) — qator butunlay yo'q.
        if ((widget.locationName?.isNotEmpty ?? false) ||
            _gpsAvailable != null) ...[
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 4,
            children: [
              if (widget.locationName?.isNotEmpty ?? false)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.mapPin,
                      size: 13,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      widget.locationName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(height: 1),
                    ),
                  ],
                ),
              // Foydalanuvchi so'rovi: "GPS holatini ko'rsatganimiz
              // yaxshi" — GPS hech qachon tekshiruvni to'smaydi (mobil-
              // maxsus qo'shimcha, manbada yo'q), lekin xodim endi
              // olinganmi-yo'qmi biladi. Birinchi haqiqiy javobgacha
              // (`_maybeEagerStart` hali ishga tushmagan) `null` —
              // qator ko'rsatilmaydi, keraksiz "aniqlanmoqda" bezovta
              // qilmasin.
              if (_gpsAvailable != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _gpsAvailable!
                          ? LucideIcons.locateFixed
                          : LucideIcons.locateOff,
                      size: 12,
                      color: _gpsAvailable!
                          ? (dark ? AppColors.success500 : AppColors.success600)
                          : Theme.of(context).textTheme.bodySmall?.color,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      _gpsAvailable!
                          ? l10n.inspectGpsCaptured
                          : l10n.inspectGpsUnavailable,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        height: 1,
                        color: _gpsAvailable!
                            ? (dark
                                  ? AppColors.success500
                                  : AppColors.success600)
                            : Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        // ⚠️ Avval bu ikkisi (subyekt tanlovi va tavsif) oddiy Column
        // ichida, hech qanday fonsiz — to'g'ridan-to'g'ri kulrang Scaffold
        // ustida — turardi ("ajralib qolgan" ko'rinish). Bitta umumiy
        // Card'ga birlashtirib ko'rilgan edi, lekin foydalanuvchi
        // to'g'ri qayd etdi: bu ikkisi MA'NO jihatidan alohida (biri —
        // tanlov/kirish maydoni, ikkinchisi — checklist haqida ma'lumot),
        // shu sabab pastdagi bo'limlar kabi ALOHIDA-ALOHIDA kartalar.
        if (hasSubject) ...[
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: _buildSubjectPicker(context, l10n),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (hasDescription) ...[
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              // ⚠️ Foydalanuvchi to'g'ri qayd etdi: tavsif erkin uzaysa,
              // xodim savollarga yetguncha ekranni pastga surib
              // o'qib o'tirishga majbur bo'ladi — bu oqimni sekinlashtiradi
              // (checklist to'ldirish tez ish, kitob o'qish emas). Shu
              // sabab standart holatda 3 qatorga cheklangan, "ko'proq"
              // bilan kengaytiriladi.
              child: _ExpandableDescription(text: checklist.description!),
            ),
          ),
          const SizedBox(height: 16),
        ],
        for (var g = 0; g < groups.length; g++) ...[
          if (g > 0) const SizedBox(height: 20),
          _buildSection(context, l10n, groups[g], g),
        ],
      ],
    );
  }

  Widget _buildSubjectPicker(BuildContext context, AppLocalizations l10n) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final candidatesAsync = ref.watch(
      subjectCandidatesProvider(widget.checklistId),
    );
    return Container(
      key: _subjectKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.userCheck,
                size: 13,
                color: dark ? AppColors.darkLabel3 : AppColors.lightLabel3,
              ),
              const SizedBox(width: 6),
              Text(
                l10n.inspectSubjectLabel,
                // ⚠️ `bodySmall`ning qator balandligi (1.4) ikonga
                // nisbatan matnni pastroq ko'rsatardi — `height: 1` bilan
                // tuzatildi.
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: dark ? AppColors.darkLabel2 : AppColors.lightLabel2,
                  height: 1,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '(${l10n.inspectSubjectChooseHint})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: dark ? AppColors.darkLabel3 : AppColors.lightLabel3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          candidatesAsync.when(
            loading: () => const SizedBox(
              height: 44,
              child: Center(
                child: PlatformLoadingIndicator(size: 16, strokeWidth: 2),
              ),
            ),
            error: (_, _) => const SizedBox.shrink(),
            data: (candidates) => SubjectPickerField(
              candidates: candidates,
              selectedId: _subjectUserId,
              highlighted: _subjectHighlighted,
              shakeToken: _subjectShakeToken,
              onChanged: (id) {
                setState(() {
                  _subjectUserId = id;
                  _subjectDecided = true;
                  _subjectHighlighted = false;
                });
                _scheduleDraftSave();
                // Eager-start hali ishga tushmagan bo'lsa (birinchi javob
                // subyekt tanlovining o'zi bo'lsa) — shu yerda boshlaydi.
                // Agar allaqachon (subyektsiz) boshlangan bo'lsa — endi
                // tanlangan subyektni serverdagi inspeksiyaga ulaydi.
                _maybeEagerStart();
                _maybeUpdateSubject(id);
              },
            ),
          ),
          if (_subjectHighlighted) ...[
            const SizedBox(height: 4),
            Text(
              l10n.inspectSubjectRequiredHint,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: dark ? AppColors.danger500 : AppColors.danger600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    AppLocalizations l10n,
    InspectSectionGroup group,
    int groupIndex,
  ) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final key = 'g$groupIndex:${group.title}';
    final collapsible = group.title.isNotEmpty && group.items.length >= 2;
    final collapsed = collapsible && _collapsed.contains(key);

    final missingCount = group.items
        .where((i) => i.required && !_isAnswered(i))
        .length;
    final failedCount = group.items.where(_isViolation).length;
    final answeredCount = group.items.where(_isAnswered).length;

    Widget? header;
    if (collapsible) {
      header = InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(
          () => collapsed ? _collapsed.remove(key) : _collapsed.add(key),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  group.title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: dark ? AppColors.darkLabel3 : AppColors.lightLabel3,
                  ),
                ),
              ),
              if (missingCount > 0) ...[
                InspectDot(color: AppColors.warning500),
                const SizedBox(width: 3),
                Text(
                  '$missingCount',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: dark ? AppColors.warning500 : AppColors.warning600,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (failedCount > 0) ...[
                InspectDot(color: AppColors.danger500),
                const SizedBox(width: 3),
                Text(
                  '$failedCount',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: dark ? AppColors.danger500 : AppColors.danger600,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                '$answeredCount/${group.items.length}',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: answeredCount == group.items.length
                      ? (dark ? AppColors.success500 : AppColors.success600)
                      : (dark ? AppColors.darkLabel3 : AppColors.lightLabel3),
                ),
              ),
              if (answeredCount == group.items.length && failedCount == 0) ...[
                const SizedBox(width: 4),
                Icon(
                  LucideIcons.checkCircle2,
                  size: 13,
                  color: dark ? AppColors.success500 : AppColors.success600,
                ),
              ],
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: collapsed ? -0.25 : 0,
                duration: const Duration(milliseconds: 150),
                child: Icon(
                  LucideIcons.chevronDown,
                  size: 14,
                  color: dark ? AppColors.darkLabel3 : AppColors.lightLabel3,
                ),
              ),
            ],
          ),
        ),
      );
    } else if (group.title.isNotEmpty) {
      header = Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(
          group.title.toUpperCase(),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: dark ? AppColors.darkLabel3 : AppColors.lightLabel3,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (header != null) header,
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: collapsed
              ? const SizedBox(width: double.infinity)
              : Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < group.items.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        _itemContainer(
                          group.items[i],
                          group.startIndex + i + 1,
                          isFirst: i == 0,
                          isLast: i == group.items.length - 1,
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  // Card radiusi bilan bir xil (`app_theme.dart` `_radiusMd`) — savol
  // qatorining chegarasi Card ICHIDA turadi, shu sabab uning radiusi
  // faqat qator qaysi chetda turganiga (birinchi/oxirgi/o'rtada) qarab
  // mos kelishi kerak, aks holda birinchi/oxirgi bo'lmagan qatorlarda
  // ham to'liq yumaloq burchak Card ning tekis ichki chetiga mos
  // kelmay, "suzib turgandek" ko'rinardi.
  static const _cardRadius = 16.0;

  Widget _itemContainer(
    ChecklistItem item,
    int index, {
    required bool isFirst,
    required bool isLast,
  }) {
    final key = _itemKeys.putIfAbsent(item.id, () => GlobalKey());
    final flashed = _flashedItemId == item.id;
    final jumped = _jumpHighlightItemId == item.id;
    final highlightColor = flashed
        ? AppColors.danger500
        : jumped
        ? Theme.of(context).colorScheme.primary
        : null;
    final radius = BorderRadius.only(
      topLeft: Radius.circular(isFirst ? _cardRadius : 0),
      topRight: Radius.circular(isFirst ? _cardRadius : 0),
      bottomLeft: Radius.circular(isLast ? _cardRadius : 0),
      bottomRight: Radius.circular(isLast ? _cardRadius : 0),
    );
    return AnimatedContainer(
      key: key,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      // ⚠️ Avval `borderRadius` berilmagan edi — natijada chegara Card
      // ichidagi yumaloq burchaklarga mos kelmasdan, o'tkir burchakli
      // "sinib qolgan" ko'rinishda chizilardi. Endi qator Card ichida
      // qayerda turishiga (birinchi/oxirgi/o'rtada) mos radius olinadi.
      //
      // ⚠️ Chegara HAR DOIM chiziladi (shaffof rangda, faqat belgilanganda
      // ranglanadi) — aks holda chegara paydo bo'lganda konteyner
      // o'lchami (1.5px har tomondan) o'zgarib, ichidagi kontent bir oz
      // "sirg'anib" ko'rinardi (layout shift). Doim bir xil o'lchamli
      // bo'lish uchun bo'sh joy HAR DOIM band qilib qo'yiladi.
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: jumped
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.06)
            : null,
        border: Border.all(
          color: highlightColor ?? Colors.transparent,
          width: 1.5,
        ),
        borderRadius: radius,
      ),
      child: InspectItemField(
        key: ValueKey('item-${item.id}-$_resetToken'),
        item: item,
        index: index,
        answer: _answers[item.id],
        onChanged: (draft) => _setAnswer(item.id, draft),
        onNext: _isAnswered(item) ? _nextUnansweredLink(item.id) : null,
      ),
    );
  }

  /// Mini app "keyingi javobsiz savol" havolasi — checklist bo'ylab
  /// (bo'limlararo) shu savoldan KEYINGI birinchi javobsiz savolga
  /// o'tkazadi. Hech qanday javobsiz savol qolmagan bo'lsa — `null`
  /// (havola ko'rsatilmaydi).
  VoidCallback? _nextUnansweredLink(String itemId) {
    final ordered = _orderedItems(widget.checklist);
    final idx = ordered.indexWhere((i) => i.id == itemId);
    if (idx == -1) return null;
    for (var i = idx + 1; i < ordered.length; i++) {
      if (!_isAnswered(ordered[i])) {
        final targetId = ordered[i].id;
        return () {
          selectionHaptic();
          _scrollToItem(targetId);
        };
      }
    }
    return null;
  }

  Widget _buildFooter(
    BuildContext context,
    AppLocalizations l10n,
    Checklist checklist,
  ) {
    final total = checklist.items.length;
    final answered = checklist.items.where(_isAnswered).length;
    final missingRequired = _missingRequired(checklist);
    final ready = missingRequired.isEmpty;
    final hasAnyAnswer = _answers.values.any((a) => a.hasContent);

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        children: [
          if (_submitError != null) ...[
            Text(
              _submitError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: PlatformButton(
                    // ⚠️ Foydalanuvchi topilmasi: "majburiy savollarga
                    // javob berilmasidan oldin finish aktiv ko'rinyapti" —
                    // avval FAQAT `hasAnyAnswer` tekshirilardi (kamida
                    // bitta javob), `ready` (majburiy savollar TO'LIQ)
                    // umuman hisobga olinmasdi — tugma bosilib, backend
                    // baribir rad etib, chalkash xato ko'rsatardi. Endi
                    // ikkalasi ham SHART: bo'sh checklist yuborilmasin
                    // (`hasAnyAnswer`) VA majburiy javoblar to'liq bo'lsin
                    // (`ready`) — ikkalasi bajarilmaguncha tugma HAQIQATAN
                    // BOSILMAYDI (`onPressed: null`), shunchaki rang bilan
                    // emas.
                    //
                    // Rang: `PlatformButton`ning o'zi (izoh: shu fayl)
                    // `onPressed: null` bo'lganda markazlashtirilgan
                    // `disabledBackgroundColor`ga o'tadi — shu sabab bu
                    // yerda shart-band emas, faol bo'lganda doim brend
                    // rangi (avvalgi foydalanuvchi so'rovi: "brend
                    // rangida emas" — CTA holati endi ham rang, ham matn
                    // bilan mos keladi, ikkisi endi ZIDDIYATLI EMAS).
                    backgroundColor: AppColors.primary600,
                    onPressed: (_submitting || !hasAnyAnswer || !ready)
                        ? null
                        : () {
                            impactHaptic();
                            _onSubmitPressed(checklist);
                          },
                    child: _submitting
                        ? const PlatformLoadingIndicator(
                            size: 20,
                            strokeWidth: 2,
                            color: Colors.white,
                          )
                        : Text(
                            ready
                                ? l10n.inspectFinishCount('$answered', '$total')
                                : l10n.inspectFinishUnanswered(
                                    '${missingRequired.length}',
                                  ),
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Mini app "Reset": barcha javob/izoh/media tozalanadi (danger tasdiq
  /// bilan). `prefillYes` yoqilgan bo'lsa majburiy YES_NO savollar qayta
  /// "Ha" bilan to'ldiriladi — xuddi birinchi ochilishdagi kabi.
  Future<void> _confirmReset(Checklist checklist) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmSheet(
      context,
      title: l10n.inspectResetTitle,
      message: l10n.inspectResetConfirm,
      confirmText: l10n.inspectResetConfirmBtn,
      cancelText: l10n.commonCancel,
    );
    if (!confirmed || !mounted) return;
    notificationHaptic(success: false);
    setState(() {
      _resetToken++;
      _answers.clear();
      if (widget.prefillYes) {
        for (final item in checklist.items) {
          // ⚠️ `skippable` bu yerda ham chiqarib tashlanadi — yuqoridagi
          // (birinchi ochilishdagi) izoh bilan bir xil sabab.
          if (item.required && !item.skippable && item.type == 'YES_NO') {
            _answers[item.id] = InspectionAnswerDraft(
              itemId: item.id,
              value: 'Ha',
            );
          }
        }
      }
      _interactedItemIds.clear();
      _viewedItemIds.clear();
      _autoCollapsedOnce.clear();
      _collapsed.clear();
      _wasReady = _computeReady(checklist);
    });
    await _saveDraftNow();
    if (!mounted) return;
    showAppToast(context, l10n.inspectResetDone, type: ToastType.success);
  }

  List<ChecklistItem> _orderedItems(Checklist checklist) =>
      buildInspectSectionGroups(checklist.items)
          .expand((g) => g.items)
          .toList();
}

/// Bo'lim nomi bo'yicha **GLOBAL** guruhlash (birinchi-uchragan tartibda)
/// — checklist muallifi savollarni bo'lim bo'yicha ketma-ket joylamagan
/// bo'lsa ham (real ma'lumotda uchraydi), bir xil nomli bo'lim doim
/// BITTA guruhga yig'iladi. Ketma-ketlikka asoslangan (faqat qo'shni
/// elementlarni birlashtiruvchi) yondashuv qurilmada tekshirilganda
/// bitta 8-savolli bo'limni 7 ta mayda parchaga bo'lib yuborgani uchun
/// ataylab RAD ETILDI. Preview va to'ldirish ekranlari IKKALASI ham shu
/// funksiyadan foydalanadi (raqamlash izchilligi uchun).
List<InspectSectionGroup> buildInspectSectionGroups(List<ChecklistItem> items) {
  final groups = <InspectSectionGroup>[];
  final byKey = <String, InspectSectionGroup>{};
  for (final item in items) {
    final key = item.sectionId ?? item.sectionTitle ?? '';
    final existing = byKey[key];
    if (existing != null) {
      existing.items.add(item);
    } else {
      final group = InspectSectionGroup(
        title: item.sectionTitle ?? '',
        items: [item],
        startIndex: 0,
      );
      byKey[key] = group;
      groups.add(group);
    }
  }
  var idx = 0;
  for (final g in groups) {
    g.startIndex = idx;
    idx += g.items.length;
  }
  return groups;
}

class InspectSectionGroup {
  InspectSectionGroup({
    required this.title,
    required this.items,
    required this.startIndex,
  });
  final String title;
  final List<ChecklistItem> items;
  int startIndex;
}

class InspectDot extends StatelessWidget {
  const InspectDot({super.key, required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: 6,
    height: 6,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _ProgressRingButton extends StatelessWidget {
  const _ProgressRingButton({required this.progress, required this.onTap});
  final double progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // ⚠️ Avval progress to'lganda (`>= 1`) yashilga o'zgarardi — Finish
    // tugmasi bilan bir xil sabab: foydalanuvchi CTA/holat rangi doim
    // brend rangida bo'lishini xohlaydi, yashil emas.
    //
    // ⚠️ Boshqa ekranlarda topilgan bilan bir xil xato — `primary600` doim
    // (dark rejimda ham) ishlatilardi, AppBar ustidagi ikon/halqa xira
    // ko'rinardi.
    final color = dark ? AppColors.primary500 : AppColors.primary600;
    // ⚠️ Topilma ("AppBar ikonlarini... hammasini bir xil holatga
    // o'tkazaylik" auditi): bu yerda ILGARI `Padding(right: 8)` HAM bor
    // edi — yuqoridagi izohda tasvirlangan "ikki marta qo'llangan
    // bo'sh joy" xatosi aslida FAQAT yarim tuzatilgan ekan: tashqi
    // `Padding(right: 16)` olib tashlangan, lekin bu widgetning O'Z
    // ICHKI `Padding(right: 8)`i qolib ketgan — `DetailAppBar`ning
    // markazlashtirilgan `actionsPadding: 8` bilan qo'shilib, baribir
    // 16px bo'lib turardi. Endi olib tashlandi.
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: SizedBox(
        width: 38,
        height: 38,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 38,
              height: 38,
              child: CircularProgressIndicator(
                value: progress.clamp(0, 1),
                strokeWidth: 3.5,
                backgroundColor: dark
                    ? AppColors.darkFill2
                    : AppColors.lightFill2,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            Icon(LucideIcons.list, size: 14, color: color),
          ],
        ),
      ),
    );
  }
}

/// `_showJumpMenu`ning `Overlay` qatlami: xira orqa fon (bosilsa yopadi),
/// tugma tomondan "o'sib chiquvchi" scale+fade kirish animatsiyasi, va
/// kartaning yuqorisidan chiquvchi kichik uchburchak ko'rsatkich — shu
/// popover aynan qaysi tugmadan kelib chiqqanini vizual bog'laydi.
class _JumpMenuOverlay extends StatefulWidget {
  const _JumpMenuOverlay({
    required this.top,
    required this.rightInset,
    required this.pointerCenterX,
    required this.onDismiss,
    required this.child,
  });

  final double top;
  final double rightInset;
  final double pointerCenterX;
  final VoidCallback onDismiss;
  final Widget child;

  @override
  State<_JumpMenuOverlay> createState() => _JumpMenuOverlayState();
}

class _JumpMenuOverlayState extends State<_JumpMenuOverlay>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  late final _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );
  late final _scale = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutBack,
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  Future<void> _dismiss() async {
    await _controller.reverse();
    if (mounted) widget.onDismiss();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? AppColors.darkSurface : AppColors.lightSurface;
    // Ko'rsatkichning kartaga nisbatan o'ng chetdan masofasi — karta
    // o'zi kontent-o'lchamli (`right: rightInset` bilan o'ngga
    // tekislangan), shu sabab tugma markazidan popoverning o'ng
    // chetigacha bo'lgan masofani bilish kifoya (karta ENI muhim emas).
    final pointerFromRight =
        (MediaQuery.of(context).size.width -
                widget.rightInset -
                widget.pointerCenterX)
            .clamp(16.0, 200.0);

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _dismiss,
            child: AnimatedBuilder(
              animation: _fade,
              builder: (context, _) => Container(
                color: Colors.black.withValues(alpha: 0.15 * _fade.value),
              ),
            ),
          ),
        ),
        Positioned(
          top: widget.top,
          right: widget.rightInset,
          child: ScaleTransition(
            scale: Tween(begin: 0.85, end: 1.0).animate(_scale),
            alignment: Alignment.topRight,
            child: FadeTransition(
              opacity: _fade,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: -6,
                    right: pointerFromRight - 6,
                    child: Transform.rotate(
                      angle: 0.785398, // 45°
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: dark ? 0.55 : 0.16,
                          ),
                          blurRadius: 28,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Material(
                      color: Colors.transparent,
                      child: widget.child,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// "Savolga o'tish" panelining tarkibi — `_JumpMenuOverlay` ichida
/// ko'rsatiladi. Raqamli kvadratlarga bosilganda haptik+yopish+scroll —
/// barchasi `onTapIndex` chaqiruvchisi orqali (`_showJumpMenu`).
class _JumpGridContent extends StatefulWidget {
  const _JumpGridContent({
    required this.items,
    required this.isAnswered,
    required this.onTapIndex,
    this.onReset,
  });

  final List<ChecklistItem> items;
  final bool Function(ChecklistItem) isAnswered;
  final ValueChanged<String> onTapIndex;

  /// `null` bo'lsa — hali hech qanday javob yo'q, tozalash tugmasi
  /// ko'rsatilmaydi (tozalanadigan narsa yo'q).
  final VoidCallback? onReset;

  @override
  State<_JumpGridContent> createState() => _JumpGridContentState();
}

class _JumpGridContentState extends State<_JumpGridContent> {
  bool _unansweredOnly = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final unansweredCount = widget.items
        .where((i) => !widget.isAnswered(i))
        .length;
    // Mini app: uzun checklist'larda (≥8 savol) VA hammasi javoblangan/
    // javobsiz bo'lmaganda (filtr ma'noli bo'lganda) chiqadi.
    final showFilterToggle =
        widget.items.length >= 8 &&
        unansweredCount > 0 &&
        unansweredCount < widget.items.length;
    final visible = _unansweredOnly
        ? [
            for (var i = 0; i < widget.items.length; i++)
              if (!widget.isAnswered(widget.items[i])) (widget.items[i], i + 1),
          ]
        : [
            for (var i = 0; i < widget.items.length; i++)
              (widget.items[i], i + 1),
          ];

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.inspectJumpTo,
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (showFilterToggle)
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () {
                      selectionHaptic();
                      setState(() => _unansweredOnly = !_unansweredOnly);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _unansweredOnly
                            ? AppColors.warning500.withValues(alpha: 0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        l10n.inspectUnansweredOnly('$unansweredCount'),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: _unansweredOnly
                              ? (dark
                                    ? AppColors.warning500
                                    : AppColors.warning600)
                              : Theme.of(context).textTheme.labelLarge?.color,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (item, index) in visible)
                      _buildChip(context, item, index),
                  ],
                ),
              ),
            ),
            if (widget.onReset != null) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: widget.onReset,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.rotateCcw,
                        size: 14,
                        color: dark ? AppColors.danger500 : AppColors.danger600,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        l10n.inspectResetAction,
                        // ⚠️ `bodySmall`ning qator balandligi (1.4) ikonga
                        // nisbatan matnni pastroq ko'rsatardi — `height: 1`
                        // bilan tuzatildi.
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: dark
                              ? AppColors.danger500
                              : AppColors.danger600,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChip(BuildContext context, ChecklistItem item, int index) {
    final answered = widget.isAnswered(item);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final missing = !answered && item.required;

    Color bg;
    Color fg;
    BoxBorder? border;
    if (answered) {
      // ⚠️ Javob qiymati (Yes/No, reyting) bo'yicha ranglashtirish
      // (qizil=buzilish) sinab ko'rildi, lekin foydalanuvchi qaror
      // qildi: bu grid faqat "javob bor/yo'q" statusini bildiradi,
      // javobning o'zi emas — bitta rangda qoldirilsin.
      bg = AppColors.success600;
      fg = Colors.white;
    } else if (missing) {
      bg = dark ? AppColors.darkFill1 : AppColors.lightFill1;
      fg = dark ? AppColors.danger500 : AppColors.danger600;
      border = Border.all(
        color: AppColors.danger500.withValues(alpha: 0.7),
        width: 2,
      );
    } else {
      bg = dark ? AppColors.darkFill1 : AppColors.lightFill1;
      fg = dark ? AppColors.darkLabel2 : AppColors.lightLabel2;
    }

    return InkWell(
      // Yopish/haptik/scroll — barchasi `onTapIndex` chaqiruvchisi
      // (`_showJumpMenu`) tomonidan boshqariladi, bu yerda faqat tanlov.
      onTap: () => widget.onTapIndex(item.id),
      borderRadius: BorderRadius.circular(11),
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(11),
          border: border,
        ),
        child: Text(
          '$index',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(fontWeight: FontWeight.w700, color: fg),
        ),
      ),
    );
  }
}
