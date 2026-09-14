import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/haptics.dart';
import '../../core/l10n/gen/app_localizations.dart';
import '../../core/location/gps_helper.dart';
import '../../core/providers/core_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/detail_app_bar.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/platform_button.dart';
import '../../data/models/location.dart';

const _kLocationsCacheKey = 'employee_locations_cache_v1';

/// `GET /locations` — xodim uchun HAM ochiq (`LocationController.findAll`da
/// `@RequirePermissions` yo'q), geofencing konfiguratsiyasi (`latitude`/
/// `longitude`/`geofenceRadiusMeters`/`geofenceRequired`) shu orqali keladi.
///
/// ⚠️ Chekov (limitation): `EmployeeTask.locations` (`GET /employee/tasks`)
/// geofencing maydonlarini UMUMAN qaytarmaydi (backend faqat `id`+`name`
/// tanlaydi) — shu sabab bu alohida chaqiruv shart. Ilovaning boshqa
/// ma'lumotlaridan farqli (Drift orqali oflayn keshlangan), bu ro'yxat
/// hozircha faqat SESSIYA darajasida (Riverpod xotirasida, ilova qayta
/// ochilguncha) keshlanadi — to'liq oflayn-safe Drift keshi HALI qurilmagan
/// (reja: "4-bosqichda Drift kesh qatlami", `tasks_controller.dart`ga
/// qarang — vazifalar ro'yxati ham hozircha xuddi shunday onlayn-only).
/// Amaliy ta'sir: agar qurilma umuman tarmoqqa ULANMAGAN bo'lsa (shu
/// sessiyada bu ro'yxat hali bir marta ham yuklanmagan bo'lsa),
/// geofencing MAJBURIYLIGINI aniqlab bo'lmaydi — bunday holatda pastdagi
/// [GeofenceGate] xavfsiz tomonga (bloklamaslik, mavjud jim `getGpsQuietly`
/// yo'liga) qaytadi, chunki xodimning butunlay oflayn ishlash imkoniyatini
/// buzish (hech qanday tekshiruvni boshlab bo'lmaydigan qilib qo'yish)
/// geofencing foydasidan KATTA zarar bo'lardi.
///
/// ⚠️ Foydalanuvchi topilmasi: "ilova ochilganda gps tekshirilishi shart
/// bo'lgan filiallarni eslab qolsak bo'lmaydimi? har safar gps talab
/// qilinmaydigan filiallar uchun tekshirib o'tirish mantiqsizku" — avval
/// bu ro'yxat FAQAT sessiya xotirasida (yuqoridagi izoh) turardi, ya'ni
/// ilova HAR safar YANGIDAN ochilganda (jarayon qayta boshlanganda)
/// tarmoqdan qaytadan so'ralardi — shu payt `GeofenceGate` "tekshirilmoqda"
/// holatida (garchi HECH BIR filialda geofencing yoqilmagan bo'lsa ham)
/// qisqa muddat kutardi. Endi `checklist_provider.dart`dagi bilan bir xil
/// naqsh: `SharedPreferences`dagi so'nggi nusxa BOR bo'lsa DARHOL
/// qaytariladi (kutish YO'Q), tarmoqdan yangilanish esa fonda (keyingi
/// safar uchun keshni yangilaydi, joriy sessiyani bloklamaydi). Diskda
/// hech narsa yo'q bo'lsa (ilovaning ENG BIRINCHI ishga tushishi) — bu
/// gal albatta tarmoqni kutish kerak, boshqa yo'l yo'q.
final employeeLocationsProvider = FutureProvider<List<EmployeeLocation>>((
  ref,
) async {
  final prefs = await SharedPreferences.getInstance();
  final cached = prefs.getString(_kLocationsCacheKey);

  Future<void> refreshInBackground() async {
    try {
      final fresh = await ref.read(employeeApiProvider).getLocations();
      unawaited(
        prefs.setString(
          _kLocationsCacheKey,
          jsonEncode(fresh.map((l) => l.toJson()).toList()),
        ),
      );
      // ⚠️ Foydalanuvchi: "yangi ma'lumot kelganda darhol amalga
      // kiritsak zo'r bo'lar edi" — avval fon yangilanishi FAQAT
      // KEYINGI ilova ishga tushishi uchun keshni yozardi, joriy
      // sessiya esa eski nusxa bilan qolaverardi. Endi provider
      // bekor qilinadi — barcha tinglovchilar (masalan hozir ochiq
      // `GeofenceGate`) YANGI ro'yxat bilan darhol qayta hisoblanadi.
      // Vizual "chaqnash" xavfi yo'q — `AsyncValue.when()`ning sukut
      // qiymati (`skipLoadingOnRefresh: true`) shu turdagi qayta
      // yuklashda ESKI qiymatni saqlab, faqat MA'LUMOTNI almashtiradi,
      // qayta "tekshirilmoqda" ekraniga qaytmaydi.
      ref.invalidateSelf();
    } catch (_) {
      // Fon yangilanishi — muvaffaqiyatsiz bo'lsa jim o'tkaziladi, eski
      // kesh keyingi safar ham ishlatilaveradi.
    }
  }

  if (cached != null) {
    unawaited(refreshInBackground());
    final decoded = jsonDecode(cached) as List;
    return decoded
        .map((e) => EmployeeLocation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  final locations = await ref.read(employeeApiProvider).getLocations();
  unawaited(
    prefs.setString(
      _kLocationsCacheKey,
      jsonEncode(locations.map((l) => l.toJson()).toList()),
    ),
  );
  return locations;
});

enum _GateStatus { checking, tooFar, failed, ok }

/// Tekshiruv boshlanishidan OLDIN (`InspectScreen`) geofencing gate —
/// `locationId`ning `geofenceRequired == true` VA koordinata sozlangan
/// bo'lsagina ishga tushadi, aks holda [builder] darhol (`gpsLat`/
/// `gpsLng: null` bilan) chaqiriladi — boshqa filiallar uchun xatti-harakat
/// TO'LIQ o'zgarishsiz qoladi (`InspectFillScreen`ning o'zidagi
/// `getGpsQuietly` yo'li ishlaydi).
///
/// Geofencing MAJBURIY bo'lsa — GPS qurilmada (tarmoqqa bog'liqmasdan)
/// olinadi, masofa `distanceMeters` (haversine) bilan hisoblanadi. Muvaffaqiyat
/// bo'lsa aniqlangan koordinata [builder]ga uzatiladi (`InspectFillScreen`
/// uni ikkinchi marta `getGpsQuietly` chaqirmasdan ishlatadi) — muvaffaqiyatsiz
/// bo'lsa BUTUN sahifa bloklanadi, hech qanday savolga javob berib
/// bo'lmaydi.
class GeofenceGate extends ConsumerStatefulWidget {
  const GeofenceGate({
    super.key,
    required this.locationId,
    required this.builder,
    this.checklistTitle,
  });

  final String? locationId;
  final Widget Function(BuildContext context, double? gpsLat, double? gpsLng)
  builder;

  /// ⚠️ Foydalanuvchi: "baribir chaqnashdek o'tyapti gps tekshiriladigan
  /// vaqti" — haqiqiy GPS o'lchovi (real vaqt talab qiladi) o'zi
  /// muammo emas, lekin "tekshirilmoqda" ekrani bo'sh sarlavha bilan
  /// ochilib, keyin BUTUNLAY boshqa (checklist sarlavhasi + savollar)
  /// ekranga sakrashi katta vizual farq — aynan shu "begona ekran
  /// chaqnadi" hissini beradi. Sarlavha oldindan ma'lum (`InspectScreen`
  /// checklistni GeofenceGate qurilishidan OLDIN allaqachon yuklab
  /// bo'lgan) — shu sabab bu yerga uzatilib, "tekshirilmoqda" ekrani
  /// ham XUDDI SHU sarlavha bilan ochiladi: farq kamayadi, sakrash
  /// emas, TABIIY davom etish hissi beradi.
  final String? checklistTitle;

  @override
  ConsumerState<GeofenceGate> createState() => _GeofenceGateState();
}

class _GeofenceGateState extends ConsumerState<GeofenceGate> {
  _GateStatus _status = _GateStatus.checking;
  GpsFailureReason? _failure;
  double? _distance;
  int? _radius;
  double? _gpsLat;
  double? _gpsLng;

  EmployeeLocation? _target;
  bool _resolvedTarget = false;

  // ⚠️ Foydalanuvchi: "biroz pauza qo'shamizmi unda?" — GPS o'lchovi
  // ba'zida (keshlangan/aniq nuqta) DEYARLI ONIY tugaydi — natijada
  // "tekshirilmoqda" ekrani sarlavhasi mos bo'lsa ham, o'qib ulgurish
  // mumkin bo'lmagan darajada tez almashib, baribir "chaqnash" his
  // qildirardi. Endi shu holat KAMIDA shu muddat ko'rinadi — real
  // tekshiruv tezroq tugasa ham, foydalanuvchi buni ANGLAB ulguradigan
  // qasddan qo'yilgan bosqich sifatida qabul qiladi (spinner emas,
  // "nimadir bajarilyapti" degan aniq tuyg'u).
  static const _kMinCheckingDuration = Duration(milliseconds: 500);

  Future<void> _runCheck(EmployeeLocation location) async {
    if (!mounted) return;
    setState(() => _status = _GateStatus.checking);
    final started = DateTime.now();
    final result = await getGpsRequired();
    if (!mounted) return;
    final elapsed = DateTime.now().difference(started);
    if (elapsed < _kMinCheckingDuration) {
      await Future.delayed(_kMinCheckingDuration - elapsed);
      if (!mounted) return;
    }
    if (!result.ok) {
      notificationHaptic(success: false);
      setState(() {
        _status = _GateStatus.failed;
        _failure = result.failure;
      });
      return;
    }
    final lat = location.latitude!;
    final lng = location.longitude!;
    final distance = distanceMeters(lat, lng, result.lat!, result.lng!);
    if (distance > location.geofenceRadiusMeters) {
      notificationHaptic(success: false);
      setState(() {
        _status = _GateStatus.tooFar;
        _distance = distance;
        _radius = location.geofenceRadiusMeters;
      });
      return;
    }
    setState(() {
      _status = _GateStatus.ok;
      _gpsLat = result.lat;
      _gpsLng = result.lng;
    });
  }

  /// ⚠️ Foydalanuvchi topilmasi: "tekshiruv sahifasiga o'tishda location
  /// belgisi chaqnaydi" — sabab: bu metod `build()`ning O'ZIDAN
  /// (`data:` callback ichidan) sinxron chaqirilardi, va geofencing
  /// KERAK BO'LMAGAN (aksariyat) filiallarda ham `setState`ni DARHOL,
  /// build jarayonining o'zida chaqirardi — bu Flutter'da "setState
  /// build paytida" xato holati (debug'da assertion, RELEASE'da esa
  /// `assert()` o'chirilgani sabab jimgina o'tkazib yuborilib, joriy
  /// frame ESKI `_status` — `checking`, ya'ni location ikonkali to'liq
  /// ekran — bilan chizib qo'yilardi, keyingi frame'dagina to'g'irlanardi:
  /// bir frame'lik "chaqnash"). Endi: geofencing shart bo'lmasa, `_status`
  /// TO'G'RIDAN-TO'G'RI (setState'siz) o'rnatiladi — SHU build chaqiruvi
  /// ICHIDA hali ishlatiladi, hech qanday oraliq frame bo'lmaydi.
  /// Geofencing haqiqatan kerak bo'lganda esa haqiqiy GPS tekshiruvi
  /// (`_runCheck`) build TUGAGANDAN keyin (`addPostFrameCallback`)
  /// boshlanadi — bu holatda "tekshirilmoqda" ekrani LEGITIM (haqiqiy
  /// asinxron ish ketmoqda), chaqnash emas.
  void _onLocationsLoaded(List<EmployeeLocation> locations) {
    if (_resolvedTarget) return;
    _resolvedTarget = true;
    final locationId = widget.locationId;
    EmployeeLocation? match;
    if (locationId != null) {
      for (final l in locations) {
        if (l.id == locationId) {
          match = l;
          break;
        }
      }
    }
    final needsGate =
        match != null &&
        match.geofenceRequired &&
        match.latitude != null &&
        match.longitude != null;
    if (!needsGate) {
      _status = _GateStatus.ok;
      return;
    }
    _target = match;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_runCheck(match!));
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.locationId == null) {
      // Filialga bog'liq bo'lmagan (ad-hoc) checklist — geofencing
      // tekshirishning umuman ma'nosi yo'q, tarmoq chaqiruvi ham shart emas.
      return widget.builder(context, null, null);
    }

    final locationsAsync = ref.watch(employeeLocationsProvider);

    return locationsAsync.when(
      loading: () => _GeofenceCheckingScreen(title: widget.checklistTitle),
      error: (_, _) {
        // ⚠️ Yuqoridagi izohga qarang: ro'yxatni yuklab bo'lmasa (masalan
        // oflayn), geofencing majburiyligini aniqlab bo'lmaydi — xavfsiz
        // tomonga (bloklamaslik) qaytiladi, mavjud jim GPS yo'li ishlaydi.
        return widget.builder(context, null, null);
      },
      data: (locations) {
        _onLocationsLoaded(locations);
        return switch (_status) {
          _GateStatus.ok => widget.builder(context, _gpsLat, _gpsLng),
          _GateStatus.checking => _GeofenceCheckingScreen(
            title: widget.checklistTitle,
          ),
          _GateStatus.failed => _GeofenceBlockedScreen(
            title: widget.checklistTitle,
            failure: _failure,
            onRetry: () => _runCheck(_target!),
          ),
          _GateStatus.tooFar => _GeofenceBlockedScreen(
            title: widget.checklistTitle,
            distance: _distance,
            radius: _radius,
            onRetry: () => _runCheck(_target!),
          ),
        };
      },
    );
  }
}

class _GeofenceCheckingScreen extends StatelessWidget {
  const _GeofenceCheckingScreen({this.title});

  final String? title;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: DetailAppBar(title: title ?? ''),
      body: EmptyState(
        icon: LucideIcons.locateFixed,
        title: l10n.inspectGeofenceCheckingTitle,
        description: l10n.inspectGeofenceCheckingMessage,
      ),
    );
  }
}

/// Geofencing MAJBURIY filialda GPS olinmadi (ruxsat/xizmat/timeout) yoki
/// xodim radiusdan tashqarida — tekshiruv boshlash BUTUNLAY bloklanadi.
/// Foydalanuvchi so'rovi (reja): "toast emas, aniq harakatga chorlovchi
/// UI" — shu sabab to'liq ekran holati (mini app'dagi `EmptyState` naqshi,
/// `ListErrorState` bilan bir xil til), pastda "Qayta urinish" (har doim)
/// va sabab ruxsatga bog'liq bo'lsa "Sozlamalarni ochish" tugmasi.
class _GeofenceBlockedScreen extends StatelessWidget {
  const _GeofenceBlockedScreen({
    this.title,
    this.failure,
    this.distance,
    this.radius,
    required this.onRetry,
  });

  /// AppBar sarlavhasi (checklist nomi) — `_GeofenceCheckingScreen`dagi
  /// bilan bir xil sabab: bo'sh AppBar "begona ekran" hissi berardi
  /// (foydalanuvchi: "bu sahifani premium va jozibadorlik uchun
  /// tekshirmaganmiz").
  final String? title;
  final GpsFailureReason? failure;
  final double? distance;
  final int? radius;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tone = dark ? AppColors.danger500 : AppColors.danger600;

    final String headline;
    final String message;
    final bool showOpenSettings;
    final bool openAppSettingsNotLocation;

    if (distance != null) {
      headline = l10n.inspectGeofenceTooFarTitle;
      // ⚠️ Foydalanuvchi: "bu sahifani premium va jozibadorlik uchun
      // tekshirmaganmiz" — xom metr (masalan "23363 m") o'qish qiyin,
      // km'ga aylantirilmagan edi. Boshqa hech qayerda ishlatilmagani
      // sabab bu yerning o'zida (alohida umumiy util shart emas).
      final metersRounded = distance!.round();
      final distanceLabel = metersRounded >= 1000
          ? '${(metersRounded / 1000).toStringAsFixed(1)} km'
          : '$metersRounded m';
      message = l10n.inspectGeofenceTooFarMessage(distanceLabel);
      showOpenSettings = false;
      openAppSettingsNotLocation = false;
    } else {
      headline = l10n.inspectGeofenceRequiredTitle;
      openAppSettingsNotLocation =
          failure == GpsFailureReason.permissionDeniedForever;
      showOpenSettings =
          failure == GpsFailureReason.permissionDenied ||
          failure == GpsFailureReason.permissionDeniedForever ||
          failure == GpsFailureReason.serviceDisabled;
      message = switch (failure) {
        GpsFailureReason.serviceDisabled => l10n.inspectGeofenceServiceDisabled,
        GpsFailureReason.permissionDenied =>
          l10n.inspectGeofencePermissionDenied,
        GpsFailureReason.permissionDeniedForever =>
          l10n.inspectGeofencePermissionDeniedForever,
        GpsFailureReason.timeout => l10n.inspectGeofenceTimeout,
        _ => l10n.inspectGeofenceUnknownError,
      };
    }

    return Scaffold(
      appBar: DetailAppBar(title: title ?? ''),
      body: Column(
        children: [
          Expanded(
            child: EmptyState(
              icon: LucideIcons.mapPinOff,
              tint: tone,
              title: headline,
              description: message,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: PlatformButton(
                    // ⚠️ Foydalanuvchi: "bu sahifani premium va
                    // jozibadorlik uchun tekshirmaganmiz" — avval bu
                    // tugma ham qizil (xato) rangda edi. Boshqa
                    // ekranlardagi CTA konvensiyasi bilan bir xil
                    // (`inspect_fill_screen.dart`dagi "Finish" tugmasi
                    // izohiga qarang: "CTA har doim brend rangida
                    // qoladi") — "Qayta urinish" halokatli/xavfli
                    // amal emas, oddiy qayta so'rov, shu sabab brend
                    // rangida. Faqat IKONKA (yuqorida, `tint: tone`)
                    // qizil qolaveradi — bu holat jiddiyligini
                    // bildiradi, tugma esa oddiy harakat sifatida.
                    backgroundColor: AppColors.primary600,
                    onPressed: onRetry,
                    child: Text(l10n.inspectGeofenceRetry),
                  ),
                ),
                if (showOpenSettings) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => openAppSettingsNotLocation
                          ? Geolocator.openAppSettings()
                          : Geolocator.openLocationSettings(),
                      child: Text(l10n.inspectGeofenceOpenSettings),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: Text(l10n.inspectGeofenceCancel),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
