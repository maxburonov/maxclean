# Max Clean 0.1.9

Apple Silicon (M1–M4) Mac'lar uchun CleanMyMac alternativasi. SwiftUI'da yozilgan, obunasiz, hamma narsa lokal ishlaydi.

## Yig'ish

Xcode yoki Command Line Tools o'rnatilgan bo'lishi kerak (`xcode-select --install`).

```bash
cd MaxClean
chmod +x build.sh
./build.sh          # build/Max Clean.app + build/MaxClean-0.1.2.dmg
open "build/Max Clean.app"
```

Keyingi versiya uchun: `./build.sh 0.1.3`

Birinchi ishga tushirishda: **System Settings → Privacy & Security → Full Disk Access** → `Max Clean`ni qo'shing (Mail, Savat va konteynerlarni tozalash uchun).

### Full Disk Access har build'da so'ralmasligi uchun (bir martalik)

Keychain Access → menyu **Keychain Access → Certificate Assistant → Create a Certificate…** →
Name: `Max Clean Dev`, Identity Type: *Self Signed Root*, Certificate Type: **Code Signing** → Create.
Shundan keyin `build.sh` shu sertifikat bilan imzolaydi va ruxsat saqlanib qoladi.

## Imkoniyatlar

| Bo'lim | Nima qiladi |
|---|---|
| Aqlli yordamchi | Mac holatini tahlil qiladi (disk, RAM, Claude keshi, snapshotlar, agentlar, uptime), «salomatlik» balli va «Hal qilish» tugmalari; haftalik avtomatik tozalash; disk to'lganda bildirishnoma |
| Aqlli tekshiruv | Bitta tugma bilan skanerlash + tozalash, disk/RAM halqalari, jami tozalangan hajm |
| Tizim keraksizlari | Kesh, loglar, **Claude Desktop (vm_bundles, Cache)**, Electron ilovalar keshi (Slack, Discord, VS Code, Telegram…), Xcode, simulator, npm/pnpm/gradle/pip/go/cargo keshlari, Mail biriktirmalari, .dmg/.pkg, iOS backup, Savat |
| Katta fayllar | Hajm va yosh bo'yicha filtr; .app va Logic loyihalari kabi paketlar ham hisoblanadi |
| Dublikatlar | Hajm → birinchi 64 KB → to'liq SHA-256; eng eski nusxa saqlanadi |
| Dasturchi keraksizlari | node_modules, Pods, venv, Rust target, SwiftPM .build, Gradle build, .next…; 30 kundan eski loyihalar avtomatik belgilanadi |
| Ilovalarni o'chirish | Ilova + barcha qoldiqlari; «Reset» (faqat sozlamalarni tiklash); o'chirilgan ilovalardan qolgan «yetim» fayllar |
| Internet blokirovkasi | Tanlangan ilova internetsiz ochiladi (macOS sandbox-exec). Max Clean ochiq turganda bloklangan ilova oddiy ochilsa — avtomatik internetsiz qayta ochiladi |
| Yangilanishlar | Sparkle orqali yangilanadigan ilovalarning yangi versiyalarini topadi; App Store yangilanishlariga tugma |
| Himoya | Ma'lum adware, imzosiz yoki buzilgan fon agentlari, o'lik agentlar, shubhali Chrome/Edge/Brave kengaytmalari |
| Avto-ishga tushish | LaunchAgents/Daemons'ni yoqish/o'chirish/olib tashlash |
| Tezlik va xotira | RAM, swap, CPU yuklama, eng ko'p xotira yeyotgan jarayonlarni yopish, `purge` |
| Texnik xizmat | Time Machine lokal snapshotlari, DNS, Spotlight, Launch Services, Quick Look, shrift keshi, disk tekshiruvi |
| Disk xaritasi | Papkama-papka hajm, sichqoncha o'ng tugmasi bilan o'chirish |
| Menyu paneli | Monitor belgisi: RAM/disk holati, tezkor RAM bo'shatish va skanerlash |

## Aqlli tozalash

- Ochiq ilovalarning keshi avtomatik tanlanmaydi (izoh bilan ko'rsatiladi)
- So'nggi 24 soatda ishlatilgan kichik keshlar tegilmaydi — baribir darhol qayta yaratiladi
- Siz belgini olib tashlagan elementlar eslab qolinadi
- Oxirgi "Savatga" amalini bir tugma bilan qaytarish (Sozlamalar → Tarix)
- Fondagi og'ir jarayonlar haqida bildirishnoma; menyu panelida RAM %

## Build (GitHub Actions)

Har push'da `.github/workflows/build.yml` macOS runner'da `build.sh` ni ishga tushiradi va DMG'ni artifact qilib yuklaydi.

## Tillar

English, Русский, O'zbekcha — Sozlamalar → Til. Standart: tizim tili.

## Tezlik

Skanerlash BSD `fts` orqali (FileManager'dan bir necha barobar tez), ilova belgilari keshlanadi, jarayonlar ro'yxati faqat «Tezlik» ekrani ochiq bo'lganda yangilanadi.

## Xavfsizlik

- `/System`, `/usr`, uy papkasining asosiy papkalari va Max Clean'ning o'zi hech qachon o'chirilmaydi.
- Sozlamalarda **oq ro'yxat** — u yerdagi papkalarga tegilmaydi.
- Katta fayllar, dublikatlar va ilovalar **Savatga** yuboriladi (qaytarib olish mumkin). Keshlar standart bo'yicha butunlay o'chiriladi (sozlamada o'zgartiriladi).
- Har bir o'chirish `~/Library/Application Support/MaxClean/history.log` ga yoziladi.
- iOS backup va .dmg fayllar avtomatik belgilanmaydi.
