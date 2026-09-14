import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/haptics.dart';
import '../../core/l10n/gen/app_localizations.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers/core_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/platform_button.dart';
import '../../core/widgets/platform_loading_indicator.dart';
import '../history/score_ring.dart';

/// Yakunlash ekrani — mini app `Inspect.tsx` "completed" bosqichi porti.
/// Avval bu yerda faqat ikonka+matn bor edi ("juda oddiy" senior UI/UX
/// auditida topilgan); endi: animatsion `ScoreRing` (mini appdagi
/// ScoreRing.tsx bilan bir xil — allaqachon `history` bo'limida bor edi,
/// shu yerga ham ulandi), "Tafsilot" tugmasi va tezkor izoh qoldirish
/// qutisi (faqat online, ball bilan yakunlangan holatda — offline
/// saqlangan/haqiqiy `inspectionId` bo'lmagan holatda ko'rsatilmaydi).
class InspectionResultScreen extends ConsumerStatefulWidget {
  const InspectionResultScreen({
    super.key,
    required this.checklistTitle,
    this.score,
    this.savedOffline = false,
    this.inspectionId,
  });

  final String checklistTitle;
  final double? score;

  /// `true` — tarmoq yo'q edi, javob lokal navbatga qo'yildi va hali
  /// serverga yetib bormagan. Bu XATO emas — tinch, ijobiy holat
  /// sifatida ko'rsatiladi.
  final bool savedOffline;

  /// Online yakunlanganda haqiqiy inspeksiya ID'si — "Tafsilot" tugmasi
  /// va izoh yuborish shu ID'ga bog'liq, shu sabab offline holatda `null`.
  final String? inspectionId;

  @override
  ConsumerState<InspectionResultScreen> createState() =>
      _InspectionResultScreenState();
}

class _InspectionResultScreenState
    extends ConsumerState<InspectionResultScreen> {
  final _commentController = TextEditingController();
  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    final inspectionId = widget.inspectionId;
    if (text.isEmpty || inspectionId == null || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    impactHaptic();
    try {
      await ref
          .read(employeeApiProvider)
          .addInspectionComment(inspectionId, text);
      if (!mounted) return;
      notificationHaptic();
      setState(() {
        _sent = true;
        _sending = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      notificationHaptic(success: false);
      final l10n = AppLocalizations.of(context);
      setState(() {
        _sending = false;
        // ⚠️ Beshinchi audit topilmasi: avval tarmoq/server xatosidan
        // qat'i nazar bir xil umumiy xabar chiqardi — `doc_attach_field
        // .dart`dagi bilan bir xil naqsh: tarmoq yo'qligi alohida,
        // tushunarli xabar bilan ajratiladi.
        _error = e.kind == ApiErrorKind.network
            ? l10n.inspectCommentNeedsInternet
            : l10n.commonLoadFailed;
      });
    } catch (_) {
      if (!mounted) return;
      notificationHaptic(success: false);
      setState(() {
        _sending = false;
        _error = AppLocalizations.of(context).commonLoadFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final showComment =
        !widget.savedOffline &&
        widget.score != null &&
        widget.inspectionId != null;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.savedOffline)
                  Container(
                    width: 88,
                    height: 88,
                    decoration: const BoxDecoration(
                      color: AppColors.warning500,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      LucideIcons.cloudUpload,
                      size: 40,
                      color: Colors.white,
                    ),
                  )
                else
                  ScoreRing(score: widget.score, size: 152, stroke: 13),
                const SizedBox(height: 20),
                Text(
                  widget.checklistTitle,
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                if (widget.savedOffline) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.inspectSavedOfflineToast,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 28),
                if (showComment) ...[
                  _CommentBox(
                    controller: _commentController,
                    sending: _sending,
                    sent: _sent,
                    error: _error,
                    onSend: _sendComment,
                    l10n: l10n,
                    dark: dark,
                  ),
                  const SizedBox(height: 16),
                ],
                if (widget.inspectionId != null) ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        selectionHaptic();
                        context.push('/inspection/${widget.inspectionId}');
                      },
                      icon: const Icon(LucideIcons.fileText, size: 18),
                      label: Text(l10n.inspectDetails),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                SizedBox(
                  width: double.infinity,
                  child: PlatformButton(
                    onPressed: () {
                      selectionHaptic();
                      context.go('/');
                    },
                    child: Text(l10n.inspectGoHome),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CommentBox extends StatelessWidget {
  const _CommentBox({
    required this.controller,
    required this.sending,
    required this.sent,
    required this.error,
    required this.onSend,
    required this.l10n,
    required this.dark,
  });

  final TextEditingController controller;
  final bool sending;
  final bool sent;
  final String? error;
  final VoidCallback onSend;
  final AppLocalizations l10n;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    if (sent) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            LucideIcons.checkCircle2,
            size: 16,
            color: AppColors.success600,
          ),
          const SizedBox(width: 6),
          Text(
            l10n.inspectCommentSent,
            // ⚠️ `bodySmall`ning qator balandligi (1.4) ikonga nisbatan
            // matnni pastroq ko'rsatardi — `height: 1` bilan tuzatildi.
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.success600,
              height: 1,
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: dark ? AppColors.darkFill1 : AppColors.lightFill1,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  hintText: l10n.inspectCommentPlaceholder,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // ⚠️ Foydalanuvchi: "hech narsa yozilmasa ham tugma aktiv
            // turibdi" — boshqa joyda topilgan bir xil naqsh (izoh/
            // hisobot varaqlari). Bu yerda `onTap` faqat `sending`ga
            // qarardi, bo'shligini FAQAT bosilgandan keyin (`_sendComment`
            // ichida) tekshirardi. `_CommentBox` `StatelessWidget` bo'lgani
            // uchun `ValueListenableBuilder` (controller o'zi
            // `ValueNotifier` — parent `setState` shart emas) orqali
            // reaktiv yoqilish/o'chirilish.
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final canSend = value.text.trim().isNotEmpty && !sending;
                return SizedBox(
                  height: 44,
                  width: 44,
                  child: Material(
                    color: canSend
                        ? AppColors.primary600
                        : (dark ? AppColors.darkFill2 : AppColors.lightFill2),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      onTap: canSend ? onSend : null,
                      child: Center(
                        child: sending
                            ? const PlatformLoadingIndicator(
                                size: 18,
                                strokeWidth: 2,
                                color: Colors.white,
                              )
                            : Icon(
                                LucideIcons.send,
                                size: 18,
                                color: canSend
                                    ? Colors.white
                                    : (dark
                                          ? AppColors.darkLabel3
                                          : AppColors.lightLabel3),
                              ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              error!,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ],
    );
  }
}
