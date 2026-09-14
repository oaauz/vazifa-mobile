import 'package:flutter/material.dart';

import '../../core/widgets/auth_brand_header.dart';
import '../../core/widgets/auth_chrome.dart';

/// Ilova ochilganda saqlangan sessiya tekshirilayotgan bosqich.
/// ⚠️ Avval oq/qorong'i fonda faqat spinner ko'rinardi — brendsiz
/// "yalang'och" ekran birinchi soniyadanoq "premium" tuyg'usini buzardi.
/// Keyin brend qo'shilgach spinner qoldirilgan edi — foydalanuvchi: "senior
/// darajadagi developer ishlatadigan narsa emas". Bosqich juda qisqa
/// (`auth_controller.dart`dagi minimal 700ms) — aylanuvchi ko'rsatkichga
/// ehtiyoj yo'q, brend belgisining o'zi yetarli.
///
/// ⚠️ Native ochilish ekrani (`flutter_native_splash`) bilan bu ekran
/// orasida SEZILARLI "sakrash" bor edi — real qurilmada ikkita rasm bir
/// lahzada bir-biriga qoплanib ko'rinardi (screenshot bilan tasdiqlangan):
/// native FAQAT ikonka (150pt, matnsiz) ko'rsatadi, bu yerda esa boshqa
/// o'lchamdagi (84pt) ikonka + "Vazifa" nomi birdan chiqardi — iOS'ning
/// tizim darajasidagi crossfade animatsiyasi ikkalasini aralashtirib
/// ko'rsatgan. Endi bu ekran ham `logoOnly` + native bilan BIR XIL
/// o'lcham (150 — `ios/Runner/Assets.xcassets/LaunchImage.imageset`
/// @1x) — o'tish deyarli sezilmaydi.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuthGradientBackground(
        // ⚠️ Yalang'och `Center` ekran yuqorisiga yopishib qoldi (real
        // qurilmada tasdiqlangan) — `Scaffold.body`ning cheklovlari bu
        // marshrutda (`/splash`, shell/AppBar'siz) kutilganidek uzatilmadi.
        // `SizedBox.expand` mavjud bo'sh joyni SO'ZSIZ egallashga majbur
        // qiladi — shundan keyin `Center` chekli o'lchamga ega bo'ladi.
        child: SizedBox.expand(
          child: const Center(
            child: AuthBrandHeader(logoOnly: true, size: 150),
          ),
        ),
      ),
    );
  }
}
