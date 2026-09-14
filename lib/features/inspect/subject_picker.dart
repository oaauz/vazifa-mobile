import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/haptics.dart';
import '../../core/l10n/gen/app_localizations.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/tonal_avatar.dart';
import '../../data/models/subject_candidate.dart';

const _searchThreshold = 10;

/// `checklist.subjectEmployee` bo'lgan checklist'lar uchun "tekshirilayotgan
/// xodim" tanlovi. Manba — `apps/employee` `components/SubjectPicker.tsx`:
/// pastdagi tugma (avatar+ism yoki bo'sh holat) + bottom sheet (≥10
/// nomzodda qidiruv, "xodim tanlamasdan davom etish" birinchi qator).
class SubjectPickerField extends StatefulWidget {
  const SubjectPickerField({
    super.key,
    required this.candidates,
    required this.selectedId,
    required this.onChanged,
    this.highlighted = false,
    this.shakeToken = 0,
  });

  final List<SubjectCandidate> candidates;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  /// Tanlanmasdan yuborishga urinilganda qizil chegara bilan diqqat
  /// tortadi (web: `ring-2 ring-red-500/70`).
  final bool highlighted;

  /// Har o'zgarishida (hatto qiymati o'sha-o'sha `highlighted: true`
  /// bo'lib qolsa ham — masalan ketma-ket ikki marta yuborishga
  /// urinilganda) chayqalish animatsiyasini qayta ishga tushiradi.
  /// Faqat `highlighted`ning false→true chegarasiga tayanish yetarli
  /// emas edi.
  final int shakeToken;

  @override
  State<SubjectPickerField> createState() => _SubjectPickerFieldState();
}

class _SubjectPickerFieldState extends State<SubjectPickerField>
    with SingleTickerProviderStateMixin {
  late final _shakeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );
  late final _shake = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: -8.0), weight: 1),
    TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 8.0, end: -6.0), weight: 1),
    TweenSequenceItem(tween: Tween(begin: -6.0, end: 6.0), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 6.0, end: 0.0), weight: 1),
  ]).animate(CurvedAnimation(parent: _shakeController, curve: Curves.easeOut));

  @override
  void didUpdateWidget(covariant SubjectPickerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shakeToken != oldWidget.shakeToken) {
      _shakeController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  SubjectCandidate? get _selected => widget.selectedId == null
      ? null
      : widget.candidates.where((c) => c.id == widget.selectedId).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final selected = _selected;

    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) =>
          Transform.translate(offset: Offset(_shake.value, 0), child: child),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: () => _openSheet(context, l10n),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(
              color: widget.highlighted
                  ? AppColors.danger500.withValues(alpha: 0.7)
                  : Theme.of(context).dividerColor,
              width: widget.highlighted ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              if (selected != null) ...[
                TonalAvatar(name: selected.fullName, radius: 14),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selected.fullName,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (selected.group?.isNotEmpty == true)
                        Text(
                          selected.group!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ] else
                Expanded(
                  child: Text(
                    l10n.inspectSubjectPlaceholder,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: dark
                          ? AppColors.darkLabel3
                          : AppColors.lightLabel3,
                    ),
                  ),
                ),
              Icon(
                LucideIcons.chevronDown,
                size: 16,
                color: dark ? AppColors.darkLabel3 : AppColors.lightLabel3,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openSheet(BuildContext context, AppLocalizations l10n) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // ⚠️ `shape` — `AppTheme.bottomSheetTheme.shape` allaqachon shu
      // qiymatni global standart sifatida beradi, qo'lda takrorlash
      // ortiqcha edi.
      builder: (sheetContext) => _SubjectSheet(
        candidates: widget.candidates,
        selectedId: widget.selectedId,
        onSelect: (id) {
          widget.onChanged(id);
          Navigator.of(sheetContext).pop();
        },
      ),
    );
  }
}

class _SubjectSheet extends StatefulWidget {
  const _SubjectSheet({
    required this.candidates,
    required this.selectedId,
    required this.onSelect,
  });
  final List<SubjectCandidate> candidates;
  final String? selectedId;
  final ValueChanged<String?> onSelect;

  @override
  State<_SubjectSheet> createState() => _SubjectSheetState();
}

class _SubjectSheetState extends State<_SubjectSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final showSearch = widget.candidates.length >= _searchThreshold;
    // ⚠️ Avval faqat `fullName` bo'yicha qidirilardi — bo'lim/guruh nomi
    // (masalan filial) bo'yicha yozilsa hech narsa topilmasdi, garchi
    // manba (`SubjectPicker.tsx`: `` `${fullName} ${group ?? ''}` ``)
    // ikkalasini ham birlashtirib qidirsa ham.
    final query = _query.toLowerCase();
    final filtered = _query.isEmpty
        ? widget.candidates
        : widget.candidates
              .where(
                (c) => '${c.fullName} ${c.group ?? ''}'.toLowerCase().contains(
                  query,
                ),
              )
              .toList();

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.76,
        ),
        child: Padding(
          // ⚠️ `confirm_sheet.dart`dagi bilan bir xil bug — `SafeArea`
          // faqat tizim chetini biladi, klaviaturani emas — qidiruv
          // maydoniga bosilganda ro'yxat klaviatura ostida qolib
          // ketardi. `viewInsets.bottom` qo'shildi.
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            8 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.inspectSubjectPick,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              if (showSearch) ...[
                const SizedBox(height: 10),
                TextField(
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: dark
                        ? AppColors.darkFill1
                        : AppColors.lightFill1,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      borderSide: BorderSide.none,
                    ),
                    hintText: l10n.inspectSubjectSearch,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ],
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (_query.isEmpty)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: dark
                              ? AppColors.darkFill2
                              : AppColors.lightFill2,
                          child: Icon(
                            LucideIcons.userX,
                            size: 15,
                            color: dark
                                ? AppColors.darkLabel2
                                : AppColors.lightLabel2,
                          ),
                        ),
                        title: Text(l10n.inspectSubjectPlaceholder),
                        trailing: widget.selectedId == null
                            ? const Icon(
                                LucideIcons.check,
                                size: 18,
                                color: AppColors.primary600,
                              )
                            : null,
                        onTap: () {
                          selectionHaptic();
                          widget.onSelect(null);
                        },
                      ),
                    if (filtered.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            l10n.inspectSubjectNotFound,
                            style: TextStyle(
                              color: dark
                                  ? AppColors.darkLabel3
                                  : AppColors.lightLabel3,
                            ),
                          ),
                        ),
                      )
                    else
                      for (final c in filtered)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: TonalAvatar(name: c.fullName),
                          title: Text(
                            c.fullName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: c.group?.isNotEmpty == true
                              ? Text(c.group!)
                              : null,
                          trailing: widget.selectedId == c.id
                              ? const Icon(
                                  LucideIcons.check,
                                  size: 18,
                                  color: AppColors.primary600,
                                )
                              : null,
                          onTap: () {
                            selectionHaptic();
                            widget.onSelect(c.id);
                          },
                        ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
