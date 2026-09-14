import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/haptics.dart';
import '../../core/l10n/gen/app_localizations.dart';
import '../../core/shared_logic/answer_completeness.dart';
import '../../core/shared_logic/score.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/answer_controls.dart';
import '../../data/models/checklist.dart';
import '../../data/models/inspection_answer_draft.dart';
import '../settings/profile_provider.dart';
import 'attachments_answer_field.dart';
import 'media_answer_picker.dart';

/// Mini app `CharCounter.tsx` porti — izoh/matn-javob maydonlarida
/// limitga yaqinlashganda ko'rinadigan hisoblagich. Avval bu ikkala
/// maydonda ham `counterText: ''` bilan BUTUNLAY o'chirilgan edi —
/// xodim limitga yetganini faqat yozish jim to'xtaganda bilib qolardi,
/// oldindan hech qanday ogohlantirish yo'q edi. 70%dan past —
/// ko'rinmaydi; 70–90% — amber; 90%+ — qizil (manba bilan bir xil
/// chegaralar).
Widget? _buildCharCounter(
  BuildContext context, {
  required int currentLength,
  required bool isFocused,
  int? maxLength,
}) {
  if (maxLength == null) return null;
  final ratio = currentLength / maxLength;
  if (ratio < 0.7) return null;
  final dark = Theme.of(context).brightness == Brightness.dark;
  final color = ratio >= 0.9
      ? (dark ? AppColors.danger500 : AppColors.danger600)
      : (dark ? AppColors.warning500 : AppColors.warning600);
  return Text(
    '$currentLength/$maxLength',
    style: Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: color, height: 1),
  );
}

/// Bitta savol uchun javob bloki. Dizayn manbai — `Inspect.tsx` savol
/// blokining aynan porti: raqamli holat belgisi (javob berilgan/majburiy/
/// ixtiyoriy), Ha/Yo'q/T-E tugmalari, yulduzcha reyting, to'ldiruvchi
/// fonli matn/son maydonlari, yig'iladigan izoh (note) paneli.
class InspectItemField extends StatefulWidget {
  const InspectItemField({
    super.key,
    required this.item,
    required this.index,
    required this.answer,
    required this.onChanged,
    this.onNext,
  });

  final ChecklistItem item;

  /// 1-based, butun checklist bo'ylab ketma-ket raqam (bo'lim ichida emas).
  final int index;
  final InspectionAnswerDraft? answer;
  final ValueChanged<InspectionAnswerDraft> onChanged;

  /// Mini app "keyingi javobsiz savol" havolasi — faqat shu savol
  /// JAVOBLANGAN va checklist bo'ylab keyingi javobsiz savol mavjud
  /// bo'lganda (`null` bo'lmasa) ko'rsatiladi.
  final VoidCallback? onNext;

  @override
  State<InspectItemField> createState() => _InspectItemFieldState();
}

class _InspectItemFieldState extends State<InspectItemField> {
  bool _noteOpen = false;
  bool _autoOpenedForViolation = false;

  /// `AttachmentsAnswerField` (hujjat+ovozli xabar chip'lari qatori) va
  /// `AttachmentsRowTrigger` (Note bilan bir qatordagi "Document"/"Voice
  /// message" havolalari) bir xil holatni baham ko'radi — foydalanuvchi
  /// so'rovi: "yozilgan voice messagelar uchta tugmadan yuqorida alohida
  /// qator bo'lgani yaxshi", keyin: "shu voice bilan bir qatorda chiqsa
  /// bo'lmaydimi? 6 ta icon bir qatorga sig'adiku" (izoh:
  /// `attachments_answer_field.dart`).
  final _attachmentsFieldKey = GlobalKey<AttachmentsAnswerFieldState>();

  InspectionAnswerDraft _draft(String value) =>
      (widget.answer ?? InspectionAnswerDraft(itemId: widget.item.id)).copyWith(
        value: value,
      );

  /// Mini app: oddiy javobga yengil `hapticSelection()`, "buzilish"
  /// (masalan YES_NO "Yo'q") javobga kuchliroq haptic — xodim diqqatini
  /// tortish uchun. Avval bu yerda umuman haptic yo'q edi (`selectAnswer`
  /// chaqirilmasdi), xuddi bosh sahifadagi kartalar bilan bo'lgani kabi
  /// "hech qanday hissiyot bermaydi" muammosi.
  void _selectAnswer(String value) {
    final violation = isRatingViolation(
      widget.item.type,
      value,
      kDefaultScoreConfig,
      maxScore: widget.item.maxScore,
    );
    if (violation) {
      notificationHaptic(success: false);
    } else {
      selectionHaptic();
    }
    widget.onChanged(_draft(value));
  }

  bool get _isViolation {
    final value = widget.answer?.value;
    if (value == null || value.isEmpty) return false;
    return isRatingViolation(
      widget.item.type,
      value,
      kDefaultScoreConfig,
      maxScore: widget.item.maxScore,
    );
  }

  @override
  void didUpdateWidget(covariant InspectItemField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Mini app: javob "buzilish" (masalan YES_NO "Yo'q") bo'lsa va izoh
    // hali bo'sh bo'lsa, izoh paneli bir marta avtomatik ochiladi —
    // xodimni sababni yozishga undaydi. Faqat bir marta (qayta yopilsa
    // qayta majburlanmaydi).
    if (!_autoOpenedForViolation &&
        _isViolation &&
        (widget.answer?.note == null || widget.answer!.note!.isEmpty)) {
      _autoOpenedForViolation = true;
      _noteOpen = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final item = widget.item;
    // ⚠️ Turga qarab qat'iy tekshiruv (izoh: `answer_completeness.dart`)
    // — rasm/video biriktirilgani BOSHQA turdagi savolning haqiqiy
    // javobini almashtirmaydi, shu sabab bu yerda "javoblangan" belgisi
    // ham (yakunlash tugmasi bilan bir xil mezon) faqat haqiqiy qiymat
    // bo'lsa yonadi.
    final answered = isItemAnswered(item.type, widget.answer);
    final dark = Theme.of(context).brightness == Brightness.dark;
    // ⚠️ Avval bu yerda xom `item.required` ishlatilardi — `skippable`
    // (T/E bilan o'tkazib yuborish mumkin) savol ham "majburiy" (amber
    // belgi + qizil `*`) qilib ko'rsatilardi, garchi foydalanuvchida
    // haqiqiy chiqish yo'li (N/A) bor bo'lsa ham. Manba `Inspect.tsx`:
    // `isRequired = item.required !== false && !item.skippable`.
    final isRequired = item.required && !item.skippable;

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _NumberBadge(
                index: widget.index,
                answered: answered,
                required: isRequired,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        // Mini appda savol matni `text-card` (13px) — lekin
                        // real qurilmada dalada o'qib-teginib turadigan
                        // ASOSIY matn shu, va ikkita mijoz aynan buni
                        // "kichik" deb shikoyat qildi. Shu sabab bu yerda
                        // ataylab mini appdan KATTAROQ (o'qilishi uchun).
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                        children: [
                          TextSpan(text: item.question),
                          if (isRequired)
                            const TextSpan(
                              text: ' *',
                              style: TextStyle(color: AppColors.danger500),
                            ),
                        ],
                      ),
                    ),
                    if (item.description?.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.description!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: dark
                              ? AppColors.darkLabel3
                              : AppColors.lightLabel3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildAnswerControl(context, l10n),
          if (answered && widget.onNext != null) ...[
            const SizedBox(height: 6),
            InkWell(
              onTap: widget.onNext,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.inspectNextUnanswered,
                      // ⚠️ `bodySmall`ning qator balandligi (1.4) ikonga
                      // nisbatan matnni pastroq ko'rsatardi — `height: 1`
                      // bilan tuzatildi.
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      LucideIcons.arrowRight,
                      size: 12,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
          ],
          MediaAnswerPicker(
            key: ValueKey('media-${item.id}'),
            item: item,
            answer: widget.answer,
            onChanged: widget.onChanged,
          ),
          const SizedBox(height: 8),
          // Foydalanuvchi so'rovi: "yozilgan voice messagelar uchta
          // tugmadan yuqorida alohida qator bo'lgani yaxshi", keyin:
          // "shu voice bilan bir qatorda chiqsa bo'lmaydimi? 6 ta icon
          // bir qatorga sig'adiku" — hujjat VA ovozli xabar chip'lari
          // endi BIR XIL qatorda, Note/Document/Voice message
          // havolalaridan YUQORIDA. Bo'sh bo'lsa nol balandlik (izoh:
          // `AttachmentsAnswerFieldState.build`).
          AttachmentsAnswerField(
            key: _attachmentsFieldKey,
            item: item,
            answer: widget.answer,
            onChanged: widget.onChanged,
          ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 6,
            children: [
              _NoteToggle(
                open: _noteOpen,
                hasContent: widget.answer?.note?.isNotEmpty == true,
                onToggle: () => setState(() => _noteOpen = !_noteOpen),
              ),
              AttachmentsRowTrigger(
                fieldKey: _attachmentsFieldKey,
                kind: AttachmentTriggerKind.document,
                atMax:
                    (widget.answer?.docFileIds.length ?? 0) >=
                    AttachmentsAnswerFieldState.maxDocs,
              ),
              // ⚠️ Foydalanuvchi: "hammasini boshqaradigan qilamiz. hozir
              // o'chirilgan modul jimgina ko'rinmay qoladi" — Ovozli
              // xabar `voice_notes` bayrog'iga qarab yashiriladi. Widget
              // Riverpod'siz (`StatefulWidget`) qurilgani uchun faqat
              // shu tugma atrofida `Consumer` ishlatiladi — butun
              // ekranni qayta yozish shart emas. Profil hali
              // yuklanmagan bo'lsa — ko'rinadi (xavfsiz standart).
              Consumer(
                builder: (context, ref, _) {
                  final profile = ref.watch(profileProvider).valueOrNull;
                  if (profile != null &&
                      !profile.moduleEnabled('voice_notes')) {
                    return const SizedBox.shrink();
                  }
                  return AttachmentsRowTrigger(
                    fieldKey: _attachmentsFieldKey,
                    kind: AttachmentTriggerKind.voice,
                    atMax:
                        ((widget.answer?.voiceNoteFileIds.length ?? 0) +
                            (widget.answer?.pendingVoiceNoteUploadIds.length ??
                                0)) >=
                        AttachmentsAnswerFieldState.maxVoiceNotes,
                  );
                },
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topLeft,
            child: _noteOpen
                ? Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextFormField(
                      key: ValueKey('note-${item.id}'),
                      initialValue: widget.answer?.note,
                      minLines: 2,
                      maxLines: 6,
                      maxLength: 500,
                      buildCounter: _buildCharCounter,
                      style: Theme.of(context).textTheme.bodySmall,
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: dark
                            ? AppColors.darkFill1
                            : AppColors.lightFill1,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusSm,
                          ),
                          borderSide: BorderSide.none,
                        ),
                        hintText: l10n.inspectNotePlaceholder,
                      ),
                      onChanged: (v) => widget.onChanged(
                        (widget.answer ??
                                InspectionAnswerDraft(itemId: item.id))
                            .copyWith(note: v),
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _buildAnswerControl(BuildContext context, AppLocalizations l10n) {
    switch (widget.item.type) {
      case 'YES_NO':
        return YesNoControl(
          value: widget.answer?.value,
          skippable: widget.item.skippable,
          onSelect: _selectAnswer,
          yesLabel: l10n.inspectAnswerYes,
          noLabel: l10n.inspectAnswerNo,
          naLabel: l10n.inspectAnswerNA,
        );
      case 'RATING':
        return RatingControl(
          value: widget.answer?.value,
          maxScore: widget.item.maxScore,
          skippable: widget.item.skippable,
          onSelect: _selectAnswer,
          naLabel: l10n.inspectAnswerNA,
        );
      case 'TEXT':
        return _FilledField(
          initialValue: widget.answer?.value,
          maxLength: 200,
          maxLines: 4,
          minLines: 2,
          hintText: l10n.inspectTextPlaceholder,
          onChanged: (v) => widget.onChanged(_draft(v)),
        );
      case 'NUMBER':
        return _FilledField(
          initialValue: widget.answer?.value,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          hintText: l10n.inspectNumberPlaceholder,
          onChanged: (v) => widget.onChanged(_draft(v.replaceAll(',', '.'))),
        );
      case 'PHOTO':
        // Bu turdagi savolning javobi rasmning o'zi — pastdagi
        // `MediaAnswerPicker` (har doim qo'shiladi) buni ko'rsatadi.
        return const SizedBox.shrink();
      default:
        return const SizedBox.shrink();
    }
  }
}

class _NumberBadge extends StatelessWidget {
  const _NumberBadge({
    required this.index,
    required this.answered,
    required this.required,
  });
  final int index;
  final bool answered;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    if (answered) {
      return Container(
        width: 20,
        height: 20,
        margin: const EdgeInsets.only(top: 2),
        // ⚠️ Avval `success500` edi — ekranning qolgan qismi (Ha tugmasi,
        // Finish tugmasi, progress-halqa) `success600` ishlatadi, ikkisi
        // yonma-yon turganda sal farqli yashil ko'rinardi.
        decoration: const BoxDecoration(
          color: AppColors.success600,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.check, size: 12, color: Colors.white),
      );
    }
    final color = required
        ? (dark ? AppColors.warning500 : AppColors.warning600)
        : (dark ? AppColors.darkLabel3 : AppColors.lightLabel3);
    final borderColor = required
        ? (dark ? AppColors.warning500 : AppColors.warning600)
        : (dark ? AppColors.darkFill2 : AppColors.lightFill2);
    return Container(
      width: 20,
      height: 20,
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        '$index',
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

class _FilledField extends StatelessWidget {
  const _FilledField({
    required this.initialValue,
    required this.hintText,
    required this.onChanged,
    this.maxLength,
    this.maxLines = 1,
    this.minLines,
    this.keyboardType,
  });

  final String? initialValue;
  final String hintText;
  final ValueChanged<String> onChanged;
  final int? maxLength;
  final int maxLines;
  final int? minLines;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return TextFormField(
      initialValue: initialValue,
      maxLength: maxLength,
      maxLines: maxLines,
      minLines: minLines,
      keyboardType: keyboardType,
      buildCounter: _buildCharCounter,
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: dark ? AppColors.darkFill1 : AppColors.lightFill1,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.all(12),
        hintText: hintText,
      ),
      onChanged: onChanged,
    );
  }
}

class _NoteToggle extends StatelessWidget {
  const _NoteToggle({
    required this.open,
    required this.hasContent,
    required this.onToggle,
  });
  final bool open;
  final bool hasContent;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final active = open || hasContent;
    final color = active
        ? (dark ? AppColors.darkLabel2 : AppColors.lightLabel2)
        : (dark ? AppColors.darkLabel3 : AppColors.lightLabel3);
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.messageSquare, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              l10n.inspectNote,
              // ⚠️ `labelLarge`ning qator balandligi (1.3) ikonlarga
              // nisbatan matnni pastroq ko'rsatardi — `height: 1` bilan
              // tuzatildi.
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w500,
                color: color,
                height: 1,
              ),
            ),
            const SizedBox(width: 2),
            AnimatedRotation(
              turns: open ? 0.5 : 0,
              duration: const Duration(milliseconds: 150),
              child: Icon(LucideIcons.chevronDown, size: 12, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
