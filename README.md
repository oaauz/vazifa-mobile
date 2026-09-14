# Vazifa Mobile — kod namunasi

Flutter asosidagi **Vazifa.io** mobil ilovasidan — xodimlar uchun inspeksiya
(tekshiruv) va checklist boshqaruv platformasidan — tanlov uchun ajratib
olingan ikkita feature'ning manba kodi.

> To'liq loyiha yopiq (private) repozitoriyada saqlanadi. Ishlab turgan
> holatini ko'rish uchun demo hisob so'rov bo'yicha taqdim etiladi.

## Ilova haqida

Vazifa — tashkilotlarda (do'kon, restoran, ishlab chiqarish va h.k.) xodimlar
tomonidan bajariladigan tekshiruv/checklist vazifalarini rejalashtirish,
bajarish va nazorat qilish uchun mo'ljallangan. Mobil ilova xodimning asosiy
ish quroli: kunlik vazifalarni ko'rish, checklist to'ldirish, o'z
ko'rsatkichlarini kuzatish. Menejer/egalar uchun esa boshqaruv funksiyalari
ham (jamoa, hisobotlar) shu ilova ichida mavjud.

## Bu repoda nima bor

- **`lib/features/auth/`** — kirish oqimi: telefon raqam + OTP
  (`otp_verify_screen.dart`), parol bilan kirish muqobili
  (`password_login_screen.dart`), xatolarni foydalanuvchiga tushunarli
  qilib ko'rsatish (`auth_error_l10n.dart`), sessiya holati boshqaruvi
  (`auth_controller.dart`, `auth_state.dart`).
- **`lib/features/inspect/`** — checklist to'ldirish oqimi: turli savol
  turlari (`inspect_item_field.dart`), rasm/video/fayl biriktirish
  (`media_answer_picker.dart`, `attachments_answer_field.dart`), joylashuv
  tekshiruvi — filial hududidan tashqarida to'ldirish bloklanadi
  (`geofence_gate.dart`), tekshiriladigan sub'ekt tanlash
  (`subject_picker.dart`), yakuniy natija ekrani
  (`inspection_result_screen.dart`).

**Diqqat:** kod **standalone build qilinmaydi** — loyihaning umumiy
qismlariga (core network, dizayn tokenlari, umumiy provider'lar, data
modellar va h.k.) bog'liq, ular bu repoga kiritilmagan. Maqsad — kod
sifati, arxitektura va yozish uslubini ko'rsatish.

## Arxitektura

- **Feature-based** papka tuzilishi — har bir funksionallik (`auth`,
  `inspect`, `dashboard`, `manager`, ...) o'z papkasida: ekranlar,
  controller'lar va shu feature'ga xos widget'lar birga.
- **State management** — [Riverpod](https://riverpod.dev) (`flutter_riverpod`),
  qo'lda yozilgan `Notifier`/`AsyncNotifier`/`FutureProvider`'lar orqali;
  kod generatsiyasi (`@riverpod` annotatsiyasi) ataylab ishlatilmaydi —
  yozuv aniq va debug qilish oson bo'lishi uchun.
- **Navigatsiya** — [go_router](https://pub.dev/packages/go_router), deklarativ
  routing + auth holatiga qarab redirect.
- **Offline-first** — mahalliy ma'lumotlar bazasi ([drift](https://drift.simonbinder.eu/),
  SQLite ustida) orqali, tarmoq bo'lmaganda ham checklist to'ldirish va
  keyinroq sinxronlash imkoni.
- **Modellar** — qo'lda yozilgan `fromJson`/`toJson`, kod generatsiyasiz.
- **Xatolikni kuzatish** — [Sentry](https://sentry.io) orqali.

## Asosiy texnologiyalar

| Toifa | Paket |
|---|---|
| State management | `flutter_riverpod` |
| Navigatsiya | `go_router` |
| Tarmoq | `dio` |
| Mahalliy DB | `drift`, `sqlite3_flutter_libs` |
| Xavfsiz saqlash | `flutter_secure_storage` |
| Biometrik tasdiq | `local_auth` |
| Xarita / geofencing | `google_maps_flutter`, `geolocator` |
| Push bildirishnoma | `firebase_messaging`, `flutter_local_notifications` |
| Masofaviy konfiguratsiya | `firebase_remote_config` |
| Media | `image_picker`, `video_compress`, `video_player`, `record` |
| Grafik | `fl_chart` |
| Xatolikni kuzatish | `sentry_flutter` |

To'liq ro'yxat — asl loyihaning `pubspec.yaml` faylida.

## Demo hisob

Ilovaning ishlab turgan holatini sinab ko'rish uchun — bu istalgan
mijozga taqdim etiladigan umumiy demo hisob, boshqaruv (menejer/egasi)
huquqlari bilan:

```
Login:  cafe@demo.vazifa.io
Parol:  demo1234
```

Ilovani yuklab olish: [Google Play](https://play.google.com/store/apps/details?id=io.vazifa.app)
