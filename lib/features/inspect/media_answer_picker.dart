import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart'
    show openAppSettings;
// ⚠️ `show VideoCompress` YETARLI EMAS — `getByteThumbnail()` `Compress`
// nomli EXTENSION orqali qo'shiladi (`video_compressor.dart`), uni ham
// ko'rsatish shart, aks holda metod "topilmadi" xatosi chiqadi.
import 'package:video_compress/video_compress.dart'
    show VideoCompress, Compress;

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/media/image_quality.dart';
import '../../core/providers/core_providers.dart';
import '../../core/telemetry/crash_reporter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/attachment_remove_badge.dart';
import '../../core/widgets/fade_scale_route.dart';
import '../../core/widgets/media_viewer.dart';
import '../../core/widgets/platform_loading_indicator.dart';
import '../../core/widgets/remote_media_preview.dart';
import '../../data/models/checklist.dart';
import '../../data/models/inspection_answer_draft.dart';
import '../settings/profile_provider.dart';

class _PickedMedia {
  _PickedMedia({
    required this.localId,
    this.localPath,
    this.fileId,
    this.error = false,
  });
  final String localId;

  /// Faqat shu sessiyada tanlangan (yoki hali diskda turgan lokal navbat)
  /// fayllar uchun bor — ko'rsatish uchun `Image.file`. Qoralama
  /// TIKLANGANDA (allaqachon serverga yuklangan, lokal fayl haqida
  /// ma'lumot saqlanmagan) `null` — bu holatda `fileId` orqali TOKENLI
  /// tarmoq URL'i bilan ko'rsatiladi (`_MediaThumb`).
  final String? localPath;
  String? fileId;

  /// ⚠️ Audit topilmasi: qoralama tiklanayotganda navbat qatoridagi lokal
  /// yozuv topilmasa (`MediaQueueService.getById` — `null`, masalan tozalab
  /// tashlangan/eskirgan) avval bu ham `isPending`ga tushib, doim "kutilmoqda"
  /// belgisi bilan qolar edi — qayta urinish esa mavjud bo'lmagan qatorga
  /// murojaat qilib jimgina hech narsa qilmasdi (o'lik oxir). `doc_attach_field.dart`
  /// dagi `_PickedDoc.error` naqshiga o'xshab — endi bunday holat aniq XATO
  /// sifatida belgilanadi (kutilmoqda emas) va faqat o'chirish mumkin.
  bool error;

  /// `fileId == null && !error` — hali lokal navbatda (oflayn bo'lishi
  /// mumkin, XATO EMAS). Foydalanuvchiga tinch "kutilmoqda" belgisi
  /// ko'rsatiladi. `error == true` bo'lsa endi kutilmoqda emas — navbat
  /// qatori umuman topilmadi, qayta urinishning ma'nosi yo'q.
  bool get isPending => fileId == null && !error;
}

/// Savolga rasm/video biriktirish. Fayl tanlangan ZAHOTI lokalga
/// nusxalanadi va navbatga qo'yiladi (`MediaQueueService`) — bu qadam
/// HECH QACHON internetga bog'liq emas. Yuklash esa darhol urinib
/// ko'riladi; muvaffaqiyatsiz bo'lsa (oflayn) `SyncService` keyinroq hal
/// qiladi — checklist to'ldirish shu tufayli to'liq oflayn ishlaydi
/// (reja §4, "Media inspeksiyadan oldin").
///
/// Dizayn manbai — `Inspect.tsx` `renderPhotosList`/`renderVideosList`:
/// 80x80 rounded-xl thumbnaillar, qizil doira o'chirish tugmasi, kutilmoqda
/// holati uchun kulrang-amber `CloudOff` nishonchasi, "Kamera"/"Galereya"
/// alohida ikkita tugma (oraliq tanlov varag'i YO'Q). **Ataylab farq**:
/// web'da video faqat onlaynda yuboriladi — bu ilovada video ham fotodek
/// darhol lokal navbatga qo'yiladi (`MediaQueueService.queueVideo`), ya'ni
/// video ham to'liq oflayn ishlaydi — web'dan ustun, tor emas.
class MediaAnswerPicker extends ConsumerStatefulWidget {
  const MediaAnswerPicker({
    super.key,
    required this.item,
    required this.answer,
    required this.onChanged,
  });

  final ChecklistItem item;
  final InspectionAnswerDraft? answer;
  final ValueChanged<InspectionAnswerDraft> onChanged;

  @override
  ConsumerState<MediaAnswerPicker> createState() => _MediaAnswerPickerState();
}

enum _PickKind { photo, video }

class _MediaAnswerPickerState extends ConsumerState<MediaAnswerPicker> {
  final _photos = <_PickedMedia>[];
  final _videos = <_PickedMedia>[];
  final _picker = ImagePicker();

  static const _maxPhotos = 5;
  static const _maxVideos = 5;

  // ⚠️ Mobil UX auditi topilmasi: "Kamera"/"Galereya" tugmalari to'g'ridan-
  // to'g'ri (oraliq tanlov varag'isiz) `_pickPhoto`/`_pickVideo`ni
  // chaqirardi — ikki marta tez ketma-ket bosilsa (masalan kamera ilovasi
  // ochilayotgan paytda), `ImagePicker` bir vaqtda ikki marta chaqirilib,
  // ikkinchisi odatda `PlatformException` bilan yiqilardi — foydalanuvchi
  // buni chalkash xato sifatida ko'rardi, garchi hech narsa buzilmagan
  // bo'lsa ham. `media_attachment_picker.dart`dagi bilan bir xil himoya.
  //
  // ⚠️ Ikkinchi audit topilmasi (o'sha faylda topilgan bir xil xato
  // klassi): bitta umumiy bayroq ham Foto, ham Video bo'limining
  // Kamera/Galereya tugmalariga uzatilardi — foto tanlanayotganda
  // (masalan galereyada uzoq ko'rib chiqilsa) Video bo'limining
  // tugmalari ham keraksiz o'chib qolardi. Endi ANIQ qaysi turi band
  // ekanini bildiradi (bir vaqtning o'zida faqat bittasi bo'lishi
  // mumkin — yuqoridagi himoya sabab — shu uchun oddiy nullable enum
  // yetarli, to'plam shart emas).
  _PickKind? _pickingKind;

  @override
  void initState() {
    super.initState();
    // ⚠️ Xato: qoralama tiklanganda (masalan checklist yopib qayta
    // ochilganda) `_photos`/`_videos` doim BO'SH boshlanardi — javob
    // "berilgan" (yashil belgi) ko'rinardi, lekin rasmning o'zi hech
    // qachon chizilmasdi, chunki bu ro'yxatlar faqat SHU sessiyada
    // tanlangan fayllardan to'ldirilardi. Endi `widget.answer`dagi
    // (allaqachon saqlangan) fayl ID'lari asosida qayta tiklanadi.
    // ⚠️ Topilma: fire-and-forget bo'lgani uchun ichkaridagi xato
    // (masalan DB o'qish muvaffaqiyatsiz) ushlanmagan qolib, tiklangan
    // biriktirmalar jimgina yo'qolib ketardi.
    _rehydrate().catchError(
      (e, st) => CrashReporter.report(e, st, zone: 'media:rehydrate'),
    );
  }

  Future<void> _rehydrate() async {
    final answer = widget.answer;
    if (answer == null) return;
    final queue = ref.read(mediaQueueServiceProvider);

    Future<_PickedMedia> pendingEntry(String localId) async {
      final row = await queue.getById(localId);
      // ⚠️ Audit topilmasi: `row == null` bo'lsa (lokal navbat qatori
      // yo'qolgan/tozalangan) avval jimgina abadiy "kutilmoqda" holati
      // yaratilardi. Endi `_PickedDoc.error`ga o'xshab aniq xato sifatida
      // belgilanadi — foydalanuvchi buni ko'radi va o'chirishi mumkin.
      return _PickedMedia(
        localId: localId,
        localPath: row != null ? await queue.absolutePath(row.relPath) : null,
        fileId: row?.fileId,
        error: row == null,
      );
    }

    final photos = <_PickedMedia>[
      for (final fileId in answer.photoFileIds)
        _PickedMedia(localId: fileId, fileId: fileId),
      for (final localId in answer.pendingPhotoUploadIds)
        await pendingEntry(localId),
    ];
    final videos = <_PickedMedia>[
      for (final fileId in answer.videoFileIds)
        _PickedMedia(localId: fileId, fileId: fileId),
      for (final localId in answer.pendingVideoUploadIds)
        await pendingEntry(localId),
    ];
    if (!mounted) return;
    setState(() {
      _photos.addAll(photos);
      _videos.addAll(videos);
    });
  }

  void _emitChange() {
    final draft =
        (widget.answer ?? InspectionAnswerDraft(itemId: widget.item.id))
            .copyWith(
              photoFileIds: _photos
                  .where((p) => p.fileId != null)
                  .map((p) => p.fileId!)
                  .toList(),
              videoFileIds: _videos
                  .where((v) => v.fileId != null)
                  .map((v) => v.fileId!)
                  .toList(),
              pendingPhotoUploadIds: _photos
                  .where((p) => p.isPending)
                  .map((p) => p.localId)
                  .toList(),
              pendingVideoUploadIds: _videos
                  .where((v) => v.isPending)
                  .map((v) => v.localId)
                  .toList(),
            );
    widget.onChanged(draft);
  }

  Future<void> _pickPhoto(ImageSource source) async {
    if (_pickingKind != null) return;
    setState(() => _pickingKind = _PickKind.photo);
    try {
      // ⚠️ Tashkilot `imageQuality` sozlamasi (STANDARD/HIGH/MAX) —
      // `maxVideoSeconds`ga o'xshab, avval BUTUNLAY e'tiborsiz
      // qoldirilgan edi (qarang: `image_quality.dart`).
      final maxSize = maxImagePixelsFor(
        ref.read(profileProvider).valueOrNull?.imageQuality,
      );
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: maxSize.toDouble(),
        maxHeight: maxSize.toDouble(),
      );
      if (picked == null) return;
      final result = await ref
          .read(mediaQueueServiceProvider)
          .queuePhoto(picked.path);
      if (!mounted) return;
      setState(
        () => _photos.add(
          _PickedMedia(
            localId: result.localId,
            localPath: picked.path,
            fileId: result.fileId,
          ),
        ),
      );
      _emitChange();
    } catch (e) {
      if (!mounted) return;
      _showPickError(e, camera: source == ImageSource.camera);
    } finally {
      if (mounted) setState(() => _pickingKind = null);
    }
  }

  Future<void> _pickVideo(ImageSource source) async {
    if (_pickingKind != null) return;
    setState(() => _pickingKind = _PickKind.video);
    try {
      // ⚠️ Avval qattiq 60s yozilgan edi — tashkilotning
      // `organization.maxVideoSeconds` sozlamasi (mini app `Inspect.tsx`
      // `readMaxVideoSeconds()` bilan bir xil, standart 30s) butunlay
      // e'tiborsiz qoldirilardi: admin cheklagan bo'lsa ham, mobilda
      // har doim 2 barobar uzunroq video yozib olish mumkin edi.
      final maxSeconds =
          ref.read(profileProvider).valueOrNull?.maxVideoSeconds ?? 30;
      final picked = await _picker.pickVideo(
        source: source,
        maxDuration: Duration(seconds: maxSeconds),
      );
      if (picked == null) return;
      final result = await ref
          .read(mediaQueueServiceProvider)
          .queueVideo(
            picked.path,
            orgImageQuality: ref
                .read(profileProvider)
                .valueOrNull
                ?.imageQuality,
          );
      if (!mounted) return;
      setState(
        () => _videos.add(
          _PickedMedia(
            localId: result.localId,
            localPath: picked.path,
            fileId: result.fileId,
          ),
        ),
      );
      _emitChange();
    } catch (e) {
      if (!mounted) return;
      _showPickError(e, camera: source == ImageSource.camera);
    } finally {
      if (mounted) setState(() => _pickingKind = null);
    }
  }

  /// `image_picker` avval jimgina hech narsa qilmasdi — foydalanuvchi
  /// "bosdim, hech narsa bo'lmadi" deb xabar berdi. Sabab noaniq edi
  /// (ruxsat rad etilganmi, kamera topilmadimi, plagin registratsiyasi
  /// muvaffaqiyatsiz bo'ldimi — masalan release'da SPM/CocoaPods aralash
  /// registratsiya, `MissingPluginException`) — endi HAR QANDAY xato
  /// tutiladi va aniq sabab bilan ko'rsatiladi; ruxsat rad etilgan bo'lsa
  /// — bevosita qurilma sozlamalariga o'tkazuvchi tugma bilan.
  void _showPickError(Object e, {required bool camera}) {
    final l10n = AppLocalizations.of(context);
    final denied =
        e is PlatformException &&
        (e.code.contains('access_denied') || e.code.contains('permission'));
    final baseMessage = denied
        ? (camera
              ? l10n.inspectCameraPermissionDenied
              : l10n.inspectGalleryPermissionDenied)
        : (camera ? l10n.inspectCameraError : l10n.inspectGalleryError);
    // Ruxsat rad etilmagan (kutilmagan) xatolarda texnik tafsilot ham
    // qo'shiladi — masalan `MissingPluginException` (plagin ro'yxatdan
    // o'tmagan) release'da diagnostika qilishning yagona yo'li shu,
    // ekranga ulangan debugger yo'q.
    final message = denied ? baseMessage : '$baseMessage: $e';
    showAppToast(
      context,
      message,
      type: ToastType.error,
      onUndo: denied ? () => openAppSettings() : null,
      undoLabel: denied ? l10n.inspectGpsOpenSettings : null,
    );
  }

  void _remove(_PickedMedia media, List<_PickedMedia> list) {
    setState(() => list.remove(media));
    _emitChange();
  }

  Future<void> _retry(_PickedMedia media) async {
    final fileId = await ref
        .read(mediaQueueServiceProvider)
        .retry(media.localId);
    if (!mounted) return;
    if (fileId != null) {
      setState(() => media.fileId = fileId);
      _emitChange();
    }
    // `fileId == null` bo'lsa — hali oflayn, jim qoladi (holat o'zgarmadi,
    // qayta bosish yana urinadi).
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final item = widget.item;
    // `type == 'PHOTO'` savollarda javobning o'zi rasm — `photoRequired`
    // bayrog'idan qat'i nazar rasm qatori ko'rsatiladi.
    final showPhotoRow = item.photoRequired || item.type == 'PHOTO';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showPhotoRow) ...[
          const SizedBox(height: 8),
          _MediaSection(
            items: _photos,
            isVideo: false,
            max: _maxPhotos,
            cameraLabel: l10n.inspectPhotoCamera,
            galleryLabel: l10n.inspectPhotoGallery,
            cameraOnly: item.photoCameraOnly,
            onCamera: () => _pickPhoto(ImageSource.camera),
            onGallery: () => _pickPhoto(ImageSource.gallery),
            onRemove: (m) => _remove(m, _photos),
            onRetry: _retry,
            picking: _pickingKind == _PickKind.photo,
          ),
        ],
        if (item.videoRequired) ...[
          const SizedBox(height: 8),
          _MediaSection(
            items: _videos,
            isVideo: true,
            max: _maxVideos,
            cameraLabel: l10n.inspectVideoCamera,
            galleryLabel: l10n.inspectVideoGallery,
            cameraOnly: item.videoCameraOnly,
            onCamera: () => _pickVideo(ImageSource.camera),
            onGallery: () => _pickVideo(ImageSource.gallery),
            onRemove: (m) => _remove(m, _videos),
            onRetry: _retry,
            picking: _pickingKind == _PickKind.video,
          ),
        ],
      ],
    );
  }
}

class _MediaSection extends StatelessWidget {
  const _MediaSection({
    required this.items,
    required this.isVideo,
    required this.max,
    required this.cameraLabel,
    required this.galleryLabel,
    required this.cameraOnly,
    required this.onCamera,
    required this.onGallery,
    required this.onRemove,
    required this.onRetry,
    required this.picking,
  });

  final List<_PickedMedia> items;
  final bool isVideo;
  final int max;
  final String cameraLabel;
  final String galleryLabel;
  final bool cameraOnly;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final ValueChanged<_PickedMedia> onRemove;
  final ValueChanged<_PickedMedia> onRetry;

  /// Boshqa tanlash so'rovi (kamera/galereya) hali kutilmoqda — ikkinchi
  /// tez bosishdan himoya (izoh: sinf-darajasidagi audit topilmasi).
  final bool picking;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fillColor = dark ? AppColors.darkFill1 : AppColors.lightFill1;
    final labelColor = dark ? AppColors.darkLabel2 : AppColors.lightLabel2;

    Widget captureButton(IconData icon, String label, VoidCallback onTap) {
      return InkWell(
        onTap: picking ? null : onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: labelColor),
              const SizedBox(width: 6),
              Text(
                label,
                // ⚠️ `bodyMedium`ning qator balandligi (1.35) ikonga
                // nisbatan matnni pastroq ko'rsatardi — `height: 1` bilan
                // tuzatildi.
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: labelColor,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (items.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final media in items)
                _MediaThumb(
                  media: media,
                  isVideo: isVideo,
                  onRemove: () => onRemove(media),
                  onRetry: () => onRetry(media),
                ),
            ],
          ),
        if (items.length < max) ...[
          if (items.isNotEmpty) const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              captureButton(
                isVideo ? LucideIcons.video : LucideIcons.camera,
                cameraLabel,
                onCamera,
              ),
              if (!cameraOnly)
                captureButton(
                  // ⚠️ Avval ikkala tarmoq ham bir xil `image` ikonaga
                  // tushib qolardi (o'lik ternary). Mini app manbasida
                  // (`Inspect.tsx:1091`) video-galereya tugmasi ham
                  // `Video` ikonasidan foydalanadi — lekin foydalanuvchi
                  // buni noto'g'ri topdi: "Galereya" degan tugmada
                  // GALEREYA ikonasi bo'lishi kerak, kamera bilan bir xil
                  // (video-yozish) ikonasi emas — ataylab manbadan farq
                  // qilingan qaror. `images` (ko'plik) — foto galereyasi
                  // (`image`, birlik)dan vizual ajratish uchun.
                  isVideo ? LucideIcons.images : LucideIcons.image,
                  galleryLabel,
                  onGallery,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _MediaThumb extends ConsumerWidget {
  const _MediaThumb({
    required this.media,
    required this.isVideo,
    required this.onRemove,
    required this.onRetry,
  });

  final _PickedMedia media;
  final bool isVideo;
  final VoidCallback onRemove;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            // ⚠️ Avval eskizga bosish hech narsa qilmasdi — xodim rasm/
            // videoni faqat 80x80 kichik nusxada ko'rardi, dalilni
            // YUBORISHDAN OLDIN tekshirib ko'rish imkoni umuman yo'q
            // edi (xira/noto'g'ri rasm bo'lsa ham sezmasdan yuborardi).
            // Kerakli vositalar (`photo_lightbox.dart`, `video_player`
            // paketi) allaqachon loyihada bor edi, faqat shu yerga
            // ulanmagan edi.
            child: Semantics(
              image: true,
              button: true,
              label: isVideo
                  ? l10n.inspectionDetailVideoLabel
                  : l10n.inspectPhoto,
              child: GestureDetector(
                onTap: () =>
                    _showMediaPreview(context, ref, media, isVideo: isVideo),
                child: isVideo
                    ? (media.localPath != null
                          // Faqat lokal fayl mavjud bo'lganda (shu
                          // sessiyada olingan/hali navbatdagi) — server
                          // video uchun eskiz umuman generatsiya
                          // qilmaydi (faqat rasm), shu sabab qoralamadan
                          // tiklangan (allaqachon yuklangan) videoda
                          // hamon oddiy belgi qoladi.
                          ? _VideoThumb(localPath: media.localPath!)
                          : Container(
                              width: 80,
                              height: 80,
                              color: Colors.black87,
                              child: const Icon(
                                LucideIcons.circlePlay,
                                color: Colors.white,
                                size: 24,
                              ),
                            ))
                    : _PhotoThumb(media: media),
              ),
            ),
          ),
          if (media.error)
            // ⚠️ Navbat qatori topilmadi (`queue.getById` — `null`) — bu
            // "kutilmoqda" emas, haqiqiy xato: qayta urinishning ma'nosi
            // yo'q (lokal ma'lumot allaqachon yo'qolgan), shu sabab bu
            // belgi `onRetry`ga ulanmagan — faqat holatni ko'rsatadi,
            // o'chirish esa yuqoridagi (o'ng-tepa) tugma orqali bo'ladi.
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.danger500.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  LucideIcons.circleAlert,
                  color: Colors.white,
                  size: 11,
                ),
              ),
            )
          else if (media.isPending)
            // Xato EMAS — lokal navbatda, oflayn bo'lishi mumkin. Bosilsa
            // darhol qayta urinadi, aks holda `SyncService` keyinroq hal qiladi.
            Positioned(
              left: 4,
              bottom: 4,
              child: InkWell(
                onTap: onRetry,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warning500.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    LucideIcons.cloudOff,
                    color: Colors.white,
                    size: 11,
                  ),
                ),
              ),
            ),
          Positioned(
            top: AttachmentRemoveBadge.defaultPositionedOffset,
            right: AttachmentRemoveBadge.defaultPositionedOffset,
            child: AttachmentRemoveBadge(
              onTap: onRemove,
              color: AppColors.danger500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Rasm kichik nusxasi — ikkita manba: shu sessiyada tanlangan/hali
/// diskdagi lokal fayl (`Image.file`) yoki qoralamadan tiklangan,
/// allaqachon serverga yuklangan fayl (tokenli tarmoq URL'i, xuddi
/// `photo_lightbox.dart`dagi kabi — kesh kaliti `fileId`ga bog'langan,
/// token aylanishidan mustaqil).
/// Lokal video faylning haqiqiy kadri — avval `video_thumbnail` paketi
/// ishlatilardi (video biriktirilganda shunchaki qora fon + play belgisi
/// ko'rinardi, chunki paket hech qayerda chaqirilmagan edi). Release
/// build'da aniqlandi: `video_thumbnail` (eng so'nggi 0.5.6 versiyasi
/// ham) Android'da yopilgan `jcenter()` repozitoriyasiga tayanadi —
/// zamonaviy Gradle (9.x) bu metodni UMUMAN tanimaydi, `bundleRelease`
/// darhol qulaydi. Paket 2+ yildan beri yangilanmagan (qoldirilgan).
/// `video_compress` (siqish uchun ALLAQACHON bog'liqlik) o'zining
/// `getByteThumbnail()`ini beradi — bir xil natija, yangi paket shart
/// emas, Android build'i buzilmaydi.
/// Kadr FAQAT bir marta (`initState`da) hisoblanadi — parent qayta
/// chizilganda (masalan boshqa maydonga matn kiritilganda) qayta
/// generatsiya qilinmasin.
class _VideoThumb extends StatefulWidget {
  const _VideoThumb({required this.localPath});
  final String localPath;

  @override
  State<_VideoThumb> createState() => _VideoThumbState();
}

class _VideoThumbState extends State<_VideoThumb> {
  // ⚠️ Foydalanuvchi: "video davomiyligi ko'rinsa" — kadr bilan BIRGA,
  // bitta so'rovda (`VideoCompress.getMediaInfo` — lokal fayl uchun
  // arzon, tarmoq so'rovi shart emas). Faqat LOKAL video uchun mumkin —
  // serverga yuklangan (tarmoq) videolar uchun (Tarix/chora tafsiloti)
  // davomiylikni oldindan bilish uchun har bir eskiz uchun to'liq
  // `VideoPlayerController` ochish kerak bo'lardi — bu amaliy emas,
  // shu sabab u yerlarga QO'SHILMAGAN.
  late final Future<(Uint8List?, Duration?)> _future = _load();

  Future<(Uint8List?, Duration?)> _load() async {
    final bytes = await VideoCompress.getByteThumbnail(
      widget.localPath,
      quality: 60,
    );
    Duration? duration;
    try {
      final info = await VideoCompress.getMediaInfo(widget.localPath);
      if (info.duration != null) {
        duration = Duration(milliseconds: info.duration!.round());
      }
    } catch (_) {
      // Davomiylik ixtiyoriy tafsilot — olib bo'lmasa eskiz baribir
      // ko'rsatiladi, faqat yorliqsiz.
    }
    return (bytes, duration);
  }

  static String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString();
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(Uint8List?, Duration?)>(
      future: _future,
      builder: (context, snapshot) {
        final bytes = snapshot.data?.$1;
        final duration = snapshot.data?.$2;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (bytes != null)
              // ⚠️ Topilma: `cacheWidth`siz thumbnail baytlari to'liq
              // o'lchamda dekodlanardi (`quality: 60` faqat siqishga
              // tegishli, o'lchamga emas).
              Image.memory(bytes, fit: BoxFit.cover, cacheWidth: 160)
            else
              Container(color: Colors.black87),
            const Center(
              child: Icon(
                LucideIcons.circlePlay,
                color: Colors.white,
                size: 24,
              ),
            ),
            if (duration != null)
              Positioned(
                right: 3,
                bottom: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _formatDuration(duration),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PhotoThumb extends ConsumerStatefulWidget {
  const _PhotoThumb({required this.media});
  final _PickedMedia media;

  @override
  ConsumerState<_PhotoThumb> createState() => _PhotoThumbState();
}

class _PhotoThumbState extends ConsumerState<_PhotoThumb> {
  // ⚠️ `fileUrlAsync` `State`da BIR MARTA (`late final`) so'raladi, ota
  // vidjet qayta qurilganda (masalan boshqa rasm qo'shilishi/o'chirilishi)
  // eskiz miltillab/qayta so'rov yubormaydi (`media_thumb_tile.dart`dagi
  // `PhotoThumbTile` bilan bir xil naqsh).
  late final Future<String>? _future = widget.media.fileId == null
      ? null
      : ref
            .read(fileTokenServiceProvider)
            .fileUrlAsync(widget.media.fileId!, thumb: true);

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    final localPath = media.localPath;
    if (localPath != null) {
      return Image.file(
        File(localPath),
        width: 80,
        height: 80,
        // ⚠️ Topilma: to'liq o'lchamli (`image_quality.dart` bo'yicha
        // 3200px'gacha) JPEG 80×80 ko'rinish uchun dekodlanardi.
        cacheWidth: 160,
        fit: BoxFit.cover,
      );
    }
    final fileId = media.fileId;
    if (fileId == null) {
      // ⚠️ Avval qattiq `Colors.black12` yozilgan edi — bu fayl
      // ichidagi qolgan barcha fonlar (`fillColor`, `_MediaSection`)
      // temaga mos `AppColors.darkFill1`/`lightFill1` ishlatadi. Qorong'i
      // rejimda `black12` deyarli karta foni bilan aralashib ketib,
      // "rasm topilmadi" holati sezilarsiz bo'lib qolardi.
      final dark = Theme.of(context).brightness == Brightness.dark;
      return Container(
        width: 80,
        height: 80,
        color: dark ? AppColors.darkFill1 : AppColors.lightFill1,
        child: Icon(
          LucideIcons.imageOff,
          size: 20,
          color: dark ? AppColors.darkLabel3 : AppColors.lightLabel3,
        ),
      );
    }
    return FutureBuilder<String>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
            width: 80,
            height: 80,
            child: Center(child: PlatformLoadingIndicator(strokeWidth: 2)),
          );
        }
        return CachedNetworkImage(
          imageUrl: snapshot.data!,
          cacheKey: 'file:$fileId:thumb',
          width: 80,
          height: 80,
          fit: BoxFit.cover,
          placeholder: (_, _) =>
              const Center(child: PlatformLoadingIndicator(strokeWidth: 2)),
          errorWidget: (_, _, _) => const Icon(LucideIcons.imageOff, size: 20),
        );
      },
    );
  }
}

/// Eskizga bosilganda to'liq ekranda ko'rsatish. Rasm — lokal fayl bo'lsa
/// to'g'ridan-to'g'ri (internetga bog'liq emas), aks holda mavjud
/// `photo_lightbox.dart` (tokenli tarmoq) qayta ishlatiladi. Video — ham
/// lokal, ham tarmoq manbasidan `video_player` bilan o'ynatiladi.
Future<void> _showMediaPreview(
  BuildContext context,
  WidgetRef ref,
  _PickedMedia media, {
  required bool isVideo,
}) async {
  if (isVideo) {
    String? source = media.localPath;
    var isLocal = true;
    if (source == null && media.fileId != null) {
      source = await ref
          .read(fileTokenServiceProvider)
          .fileUrlAsync(media.fileId!);
      isLocal = false;
    }
    if (source == null || source.isEmpty || !context.mounted) return;
    // ⚠️ `barrierColor: transparent` — marshrutning O'ZI qora parda
    // chizmasin, buni `MediaViewer` o'zi (karta/to'liq ekran holatiga
    // qarab dinamik xiralik bilan) boshqaradi. Aks holda ikkalasi
    // ustma-ust qo'shilib, "karta" holati ham to'liq qora ko'rinardi.
    await Navigator.of(context).push(
      fadeScaleRoute(
        VideoPreviewScreen(source: source, isLocal: isLocal),
        barrierColor: Colors.transparent,
        instant: true,
      ),
    );
    return;
  }

  if (media.localPath != null) {
    await Navigator.of(context).push(
      fadeScaleRoute(
        _LocalPhotoPreview(path: media.localPath!),
        barrierColor: Colors.transparent,
        instant: true,
      ),
    );
  } else if (media.fileId != null && context.mounted) {
    // ⚠️ Avval bu yerda `showPhotoLightbox` (ko'p-rasmli galereya uchun
    // mo'ljallangan, `MediaViewer`ga umuman ulanmagan eski komponent)
    // chaqirilardi — natijada allaqachon yuklangan (yoki qoralamadan
    // tiklangan) rasmga bosilganda to'g'ridan-to'g'ri to'liq ekranga
    // sakrardi, karta bosqichi umuman ko'rinmasdi. Checklist ichida
    // har doim BITTA fayl ko'riladi, shu sabab endi shu yerning O'ZIDA,
    // `MediaViewer` bilan — lokal rasm bilan bir xil "his".
    await Navigator.of(context).push(
      fadeScaleRoute(
        RemotePhotoPreview(fileId: media.fileId!),
        barrierColor: Colors.transparent,
        instant: true,
      ),
    );
  }
}

/// Lokal rasm uchun — foydalanuvchi so'rovi bo'yicha `MediaViewer`
/// (Photos-uslubidagi karta→to'liq ekran→pastga-tortib-yopish) bilan
/// o'raladi. Pinch-zoom faqat TO'LIQ EKRAN holatida yoqiladi (`expanded`).
class _LocalPhotoPreview extends StatelessWidget {
  const _LocalPhotoPreview({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    final provider = FileImage(File(path));
    return FutureBuilder<double?>(
      future: resolveImageAspectRatio(provider),
      builder: (context, snapshot) {
        return MediaViewer(
          aspectRatio: snapshot.data,
          builder: (expanded) => InteractiveViewer(
            panEnabled: expanded,
            scaleEnabled: expanded,
            minScale: 1,
            maxScale: 5,
            child: Image(image: provider, fit: BoxFit.contain),
          ),
        );
      },
    );
  }
}
