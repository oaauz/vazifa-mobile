import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/haptics.dart';
import '../../core/l10n/gen/app_localizations.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers/core_providers.dart';
import '../../core/telemetry/crash_reporter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/attachment_remove_badge.dart';
import '../../core/widgets/platform_loading_indicator.dart';
import '../../core/widgets/voice_note_player.dart';
import '../../core/widgets/voice_recorder_sheet.dart';
import '../../data/models/checklist.dart';
import '../../data/models/inspection_answer_draft.dart';

/// Hujjat VA ovozli xabar biriktirmalari — BIR XIL, o'z alohida
/// to'liq eninli qatorida (Note/Document/Voice message havolalaridan
/// YUQORIDA). Ilgari ikkalasi alohida vidjet edi (`DocAttachField`,
/// `VoiceNoteAnswerField`), lekin foydalanuvchi: "shu voice bilan bir
/// qatorda chiqsa bo'lmaydimi? 6 ta icon bir qatorga sig'adiku" —
/// ikkalasini BITTA holat/qatorga birlashtirish uchun bitta vidjetga
/// qo'shildi (ikkita mustaqil `State`ni bitta vizual `Wrap`ga
/// birlashtirish `GlobalKey` orqali qiyin/beqaror bo'lardi — ikkalasi
/// bir xil "manba"da bo'lgani ancha sodda va ishonchli).
///
/// Hujjatda oflayn navbat YO'Q (mini app `Inspect.tsx`: ataylab
/// qurilmagan) — yuklash muvaffaqiyatli bo'lgandagina javobga
/// qo'shiladi. Ovozli xabarda BOR (`_PickedVoiceNote.isPending`) —
/// yozib olish o'zi tarmoqsiz ham mumkin bo'lishi kerak.
class AttachmentsAnswerField extends ConsumerStatefulWidget {
  const AttachmentsAnswerField({
    super.key,
    required this.item,
    required this.answer,
    required this.onChanged,
  });

  final ChecklistItem item;
  final InspectionAnswerDraft? answer;
  final ValueChanged<InspectionAnswerDraft> onChanged;

  @override
  ConsumerState<AttachmentsAnswerField> createState() =>
      AttachmentsAnswerFieldState();
}

class _PickedDoc {
  _PickedDoc({required this.name, this.path, this.fileId});
  final String name;

  /// Faqat shu sessiyada tanlangan fayl uchun bor (qayta urinish uchun
  /// kerak). Qoralamadan tiklangan (allaqachon yuklangan) hujjatlarda
  /// `null` — lokal fayl haqida ma'lumot saqlanmagan, lekin ularga qayta
  /// urinish ham kerak emas (`fileId` allaqachon bor).
  final String? path;
  String? fileId;
  bool uploading = false;
  String? error;
}

class _PickedVoiceNote {
  _PickedVoiceNote({
    required this.localId,
    this.localPath,
    this.fileId,
    this.waveform,
    this.error = false,
  });
  final String localId;

  /// Faqat shu sessiyada yozib olingan (yoki hali diskda turgan lokal
  /// navbat) yozuv uchun bor — `VoiceNotePlayer(localPath: ...)` orqali
  /// to'g'ridan-to'g'ri (internetga bog'liq emas) ijro qilinadi.
  /// Qoralamadan tiklangan (allaqachon yuklangan) yozuvda `null` — bu
  /// holatda `VoiceNotePlayer(fileId: ...)` tarmoqdan (tokenli URL) o'qiydi.
  final String? localPath;
  String? fileId;
  final List<double>? waveform;

  /// `_PickedDoc.error` bilan bir xil naqsh — navbat qatori topilmasa
  /// (masalan tozalab tashlangan).
  bool error;

  bool get isPending => fileId == null && !error;
}

class AttachmentsAnswerFieldState
    extends ConsumerState<AttachmentsAnswerField> {
  final _docs = <_PickedDoc>[];
  final _notes = <_PickedVoiceNote>[];

  // Chaqiruvchi (`InspectItemField`) `AttachmentsRowTrigger.atMax`ni
  // hisoblashda ham ishlatadi (izoh: o'sha yerda) — shu sabab ochiq.
  static const maxDocs = 3;
  static const maxVoiceNotes = 3;
  static const _maxDocBytes = 10 * 1024 * 1024;
  static const _allowedDocExt = [
    'pdf',
    'docx',
    'xlsx',
    'doc',
    'xls',
    'csv',
    'txt',
  ];

  @override
  void initState() {
    super.initState();
    // Hujjat — sinxron (qoralama tiklanganda darhol tayyor, tarmoq
    // so'rovi shart emas), ovozli xabar — asinxron (`MediaQueueService`
    // navbatidan o'qiydi). Ikkalasi bir xil `initState`da.
    final answer = widget.answer;
    if (answer != null) {
      for (var i = 0; i < answer.docFileIds.length; i++) {
        _docs.add(
          _PickedDoc(
            name: i < answer.docNames.length
                ? answer.docNames[i]
                : answer.docFileIds[i],
            fileId: answer.docFileIds[i],
          ),
        );
      }
    }
    _rehydrateVoiceNotes().catchError(
      (e, st) => CrashReporter.report(e, st, zone: 'voiceNote:rehydrate'),
    );
  }

  Future<void> _rehydrateVoiceNotes() async {
    final answer = widget.answer;
    if (answer == null) return;
    final queue = ref.read(mediaQueueServiceProvider);

    final notes = <_PickedVoiceNote>[
      for (final fileId in answer.voiceNoteFileIds)
        _PickedVoiceNote(localId: fileId, fileId: fileId),
      for (final localId in answer.pendingVoiceNoteUploadIds)
        await () async {
          final row = await queue.getById(localId);
          return _PickedVoiceNote(
            localId: localId,
            localPath: row != null
                ? await queue.absolutePath(row.relPath)
                : null,
            fileId: row?.fileId,
            error: row == null,
          );
        }(),
    ];
    if (!mounted) return;
    setState(() => _notes.addAll(notes));
  }

  void _emitChange() {
    final draft =
        (widget.answer ?? InspectionAnswerDraft(itemId: widget.item.id))
            .copyWith(
              docFileIds: _docs
                  .where((d) => d.fileId != null)
                  .map((d) => d.fileId!)
                  .toList(),
              docNames: _docs
                  .where((d) => d.fileId != null)
                  .map((d) => d.name)
                  .toList(),
              voiceNoteFileIds: _notes
                  .where((n) => n.fileId != null)
                  .map((n) => n.fileId!)
                  .toList(),
              pendingVoiceNoteUploadIds: _notes
                  .where((n) => n.isPending)
                  .map((n) => n.localId)
                  .toList(),
            );
    widget.onChanged(draft);
  }

  void _showError(String message) {
    showAppToast(context, message, type: ToastType.error);
  }

  // ── Hujjat ────────────────────────────────────────────────────────

  /// `AttachmentsRowTrigger` (Note/Voice message bilan bir qatordagi
  /// "Document" havolasi) `GlobalKey` orqali chaqiradi.
  Future<void> pickDocument() async {
    final l10n = AppLocalizations.of(context);
    if (_docs.length >= maxDocs) {
      _showError(l10n.inspectDocLimitReached('$maxDocs'));
      return;
    }
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedDocExt,
    );
    if (result.isEmpty) return;
    final picked = result.first;
    if (picked.path == null) return;
    if (await picked.length() > _maxDocBytes) {
      _showError(l10n.inspectDocTooLarge);
      return;
    }

    final doc = _PickedDoc(name: picked.name, path: picked.path!);
    setState(() {
      doc.uploading = true;
      _docs.add(doc);
    });
    await _uploadDoc(doc);
  }

  Future<void> _uploadDoc(_PickedDoc doc) async {
    final path = doc.path;
    if (path == null) return; // Tiklangan (allaqachon yuklangan) hujjat.
    final l10n = AppLocalizations.of(context);
    setState(() {
      doc.uploading = true;
      doc.error = null;
    });
    try {
      final fileId = await ref.read(uploadApiProvider).uploadDocument(path);
      if (!mounted) return;
      setState(() {
        doc.fileId = fileId;
        doc.uploading = false;
      });
      notificationHaptic();
      _emitChange();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        doc.uploading = false;
        doc.error = e.kind == ApiErrorKind.network
            ? l10n.inspectDocNeedsInternet
            : l10n.inspectDocUploadError;
      });
      notificationHaptic(success: false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        doc.uploading = false;
        doc.error = l10n.inspectDocUploadError;
      });
      notificationHaptic(success: false);
    }
  }

  Future<void> _openDoc(_PickedDoc doc) async {
    if (doc.fileId == null) return;
    final url = await ref
        .read(fileTokenServiceProvider)
        .fileUrlAsync(doc.fileId!);
    if (url.isEmpty) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _removeDoc(_PickedDoc doc) {
    setState(() => _docs.remove(doc));
    _emitChange();
  }

  // ── Ovozli xabar ─────────────────────────────────────────────────

  /// `AttachmentsRowTrigger` (Note/Document bilan bir qatordagi "Voice
  /// message" havolasi) `GlobalKey` orqali chaqiradi.
  Future<void> recordVoice() async {
    final l10n = AppLocalizations.of(context);
    if (_notes.length >= maxVoiceNotes) {
      _showError(l10n.voiceNoteLimitReached('$maxVoiceNotes'));
      return;
    }
    final result = await showVoiceRecorderSheet(context);
    if (result == null || !mounted) return;
    final (path, _, waveform) = result;
    try {
      final queued = await ref.read(mediaQueueServiceProvider).queueAudio(path);
      if (!mounted) return;
      setState(
        () => _notes.add(
          _PickedVoiceNote(
            localId: queued.localId,
            localPath: path,
            fileId: queued.fileId,
            waveform: waveform,
          ),
        ),
      );
      _emitChange();
    } catch (e) {
      if (!mounted) return;
      _showError('${l10n.inspectDocUploadError}: $e');
    }
  }

  Future<void> _retryVoice(_PickedVoiceNote note) async {
    final fileId = await ref
        .read(mediaQueueServiceProvider)
        .retry(note.localId);
    if (!mounted) return;
    if (fileId != null) {
      setState(() => note.fileId = fileId);
      _emitChange();
    }
  }

  void _removeVoice(_PickedVoiceNote note) {
    setState(() => _notes.remove(note));
    _emitChange();
  }

  @override
  Widget build(BuildContext context) {
    if (_docs.isEmpty && _notes.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final doc in _docs)
            _DocIconChip(
              doc: doc,
              onRemove: () => _removeDoc(doc),
              onRetry: () => _uploadDoc(doc),
              onOpen: () => _openDoc(doc),
            ),
          for (final note in _notes)
            _VoiceNoteItem(
              note: note,
              onRemove: () => _removeVoice(note),
              onRetry: () => _retryVoice(note),
            ),
        ],
      ),
    );
  }
}

/// Note/Document/Voice message havolalari qatorida turadigan tanlash
/// tugmasi — o'zining mustaqil "band" (loading) holati bor
/// (`AttachmentsAnswerFieldState` esa faqat chip'larni chizadi).
class AttachmentsRowTrigger extends StatefulWidget {
  const AttachmentsRowTrigger({
    super.key,
    required this.fieldKey,
    required this.kind,
    this.atMax = false,
  });

  final GlobalKey<AttachmentsAnswerFieldState> fieldKey;
  final AttachmentTriggerKind kind;

  /// ⚠️ Foydalanuvchi: "3 ta voice message attach qilingan bo'lsa
  /// voice messageni disable qilib qo'yamizmi? baribir ishlamaydigan
  /// tugma active turishi shart emasku" — chegara (max 3) allaqachon
  /// `AttachmentsAnswerFieldState.pickDocument`/`recordVoice` ICHIDA
  /// tekshirilardi (bosilsa toast chiqarardi), lekin havolaning O'ZI
  /// har doim FAOL ko'rinardi — bosish HECH NARSA qilmasligini
  /// (haqiqiy natija bermasligini) oldindan bilib bo'lmasdi. Endi
  /// chaqiruvchi (`InspectItemField`, `widget.answer`dan hisoblab)
  /// chegaraga yetganini oldindan biladi va shu yerda kulrang/bosilmas
  /// qilib ko'rsatadi.
  final bool atMax;

  @override
  State<AttachmentsRowTrigger> createState() => _AttachmentsRowTriggerState();
}

enum AttachmentTriggerKind { document, voice }

class _AttachmentsRowTriggerState extends State<AttachmentsRowTrigger> {
  bool _busy = false;

  Future<void> _tap() async {
    final state = widget.fieldKey.currentState;
    if (state == null || _busy) return;
    setState(() => _busy = true);
    try {
      switch (widget.kind) {
        case AttachmentTriggerKind.document:
          await state.pickDocument();
        case AttachmentTriggerKind.voice:
          await state.recordVoice();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = dark ? AppColors.darkLabel3 : AppColors.lightLabel3;
    final color = widget.atMax ? baseColor.withValues(alpha: 0.4) : baseColor;
    final label = widget.kind == AttachmentTriggerKind.document
        ? l10n.inspectDocAttach
        : l10n.voiceNoteAdd;
    final icon = widget.kind == AttachmentTriggerKind.document
        ? LucideIcons.paperclip
        : LucideIcons.mic;

    return InkWell(
      onTap: (_busy || widget.atMax) ? null : _tap,
      borderRadius: BorderRadius.circular(6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_busy)
            PlatformLoadingIndicator(size: 12, strokeWidth: 1.5, color: color)
          else
            Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w500,
              color: color,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Hujjat — kichik doiraviy belgi, ovozli xabar bilan bir xil vizual
/// til (izoh: fayl klassi darajasida, `AttachmentsAnswerField`).
class _DocIconChip extends StatelessWidget {
  const _DocIconChip({
    required this.doc,
    required this.onRemove,
    required this.onRetry,
    required this.onOpen,
  });
  final _PickedDoc doc;
  final VoidCallback onRemove;
  final VoidCallback onRetry;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final hasError = doc.error != null;
    final primary = Theme.of(context).colorScheme.primary;
    final bg = hasError
        ? AppColors.danger500.withValues(alpha: 0.12)
        : primary.withValues(alpha: 0.12);
    final fg = hasError ? AppColors.danger600 : primary;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Semantics(
          button: true,
          label: doc.name,
          child: InkWell(
            onTap: doc.uploading ? null : (hasError ? onRetry : onOpen),
            customBorder: const CircleBorder(),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: Center(
                child: doc.uploading
                    ? PlatformLoadingIndicator(
                        size: 16,
                        strokeWidth: 2,
                        color: fg,
                      )
                    : Icon(
                        hasError
                            ? LucideIcons.circleAlert
                            : LucideIcons.fileText,
                        size: 18,
                        color: fg,
                      ),
              ),
            ),
          ),
        ),
        // Yuklash tugamaguncha o'chirib bo'lmaydi — izoh: eski
        // `DocAttachField`dagi bilan bir xil qaror (fon rejimida
        // davom etaveradi, bekor qilish mexanizmi yo'q).
        if (!doc.uploading)
          Positioned(
            top: AttachmentRemoveBadge.defaultPositionedOffset,
            right: AttachmentRemoveBadge.defaultPositionedOffset,
            child: AttachmentRemoveBadge(onTap: onRemove),
          ),
      ],
    );
  }
}

/// Ovozli xabar — kichik doiraviy belgi. Foydalanuvchi: "attach
/// bo'lish yaxshi ko'rinmayapti... premium va jozibador emas"
/// (uch marta qayta ko'rilgan — statik matn → rangli chip → to'liq
/// pleer → OXIRIDA shu, kichik ikonka, bosilsa premium "tinglash"
/// varag'i — `showVoiceNotePreviewSheet` — ochiladi).
class _VoiceNoteItem extends StatelessWidget {
  const _VoiceNoteItem({
    required this.note,
    required this.onRemove,
    required this.onRetry,
  });
  final _PickedVoiceNote note;
  final VoidCallback onRemove;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasError = note.error;
    final primary = theme.colorScheme.primary;
    final bg = hasError
        ? AppColors.danger500.withValues(alpha: 0.12)
        : primary.withValues(alpha: 0.12);
    final fg = hasError ? AppColors.danger600 : primary;

    Future<void> openPreview() async {
      if (hasError) {
        onRetry();
        return;
      }
      await showVoiceNotePreviewSheet(
        context,
        fileId: note.fileId,
        localPath: note.localPath,
        waveform: note.waveform,
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Semantics(
          button: true,
          label: AppLocalizations.of(context).voiceNoteAdd,
          child: InkWell(
            onTap: openPreview,
            customBorder: const CircleBorder(),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: Icon(
                hasError ? LucideIcons.circleAlert : LucideIcons.mic,
                size: 18,
                color: fg,
              ),
            ),
          ),
        ),
        if (note.isPending)
          Positioned(
            left: -2,
            bottom: -2,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AppColors.warning500.withValues(alpha: 0.95),
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
              child: const Icon(
                LucideIcons.cloudOff,
                color: Colors.white,
                size: 9,
              ),
            ),
          ),
        Positioned(
          top: AttachmentRemoveBadge.defaultPositionedOffset,
          right: AttachmentRemoveBadge.defaultPositionedOffset,
          child: AttachmentRemoveBadge(onTap: onRemove),
        ),
      ],
    );
  }
}
