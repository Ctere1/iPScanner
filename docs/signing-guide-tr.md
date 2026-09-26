# iPScanner 1.3.0 — imzalama ve yayın rehberi

Bu adımlar DMG GitHub'a yüklenmeden önce tamamlanır. Sertifika oluşturma ve Apple
hesabına giriş adımlarını kendi Mac'inde yap. Parolanı veya özel anahtarını sohbete yazma.

## 1. Xcode'u hazırlama

1. Xcode'u aç. Lisans ekranı çıkarsa metni incele ve kabul ediyorsan onayla.
2. Alternatif: Terminal'de `sudo xcodebuild -license` çalıştır. Mac giriş parolanı
   yaz; yazarken ekranda karakter görünmez. Metni incele ve kabul ediyorsan `agree` yaz.
3. Xcode ilk açılışta ek bileşen isterse kurulumu tamamla.
4. Tamamlandığında Codex'e “lisans tamam” de. Kod ve testler bundan sonra derlenebilir.

## 2. Apple Developer hesabını Xcode'a ekleme

1. Xcode → Settings → Apple Accounts (bazı sürümlerde Accounts) bölümünü aç.
2. `+` ile ücretli Apple Developer Program hesabını ekle; giriş ve doğrulamayı tamamla.
3. Ücretli üyeliğin bağlı olduğu takımı seç. Personal Team seçme.
4. Manage Certificates düğmesine, sonra `+` düğmesine bas.
5. **Developer ID Application** seç. GitHub'dan dağıtılan bu uygulama için gereken tür budur.
6. Oluşturma bitince Terminal'de şu salt okunur komutu çalıştır:

```bash
security find-identity -v -p codesigning
```

`Developer ID Application: ... (TAKIMKODU)` satırı görünmeli. Sertifikanın özel
anahtarı da bu Mac'te bulunmalı; yalnızca `.cer` indirmek her durumda yeterli değildir.
Developer ID seçeneği çıkmıyorsa takımın Account Holder rolünü ve üyelik durumunu kontrol et.
Mevcut sertifikaları silme veya iptal etme.

Kaynak: [Apple — Developer ID sertifikaları](https://developer.apple.com/help/account/certificates/create-developer-id-certificates),
[Xcode — sertifikaları yönetme](https://help.apple.com/xcode/mac/current/en.lproj/dev154b28f09.html).

## 3. Notarization erişimini Anahtar Zinciri'ne kaydetme

1. [Apple Account](https://account.apple.com/) hesabında Sign-In and Security →
   App-Specific Passwords bölümünden `iPScanner notarization` için uygulamaya özel parola oluştur.
2. Terminal'de şu komutu çalıştır:

```bash
xcrun notarytool store-credentials "ipscanner-notary"
```

3. Araç sorduğunda Apple hesabı e-postanı, ücretli takımının Team ID değerini ve
   uygulamaya özel parolayı Terminal'e gir. Normal Apple hesabı parolanı kullanma.
4. Araç kimlik bilgilerini doğrulayıp Anahtar Zinciri'ne kaydetmeli.

Kaynak: [Apple — notarization iş akışı](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

Not: 2026-09-26 yerel GUI ve CLI Developer ID ile imzalandı ve doğrulandı.
`ipscanner-notary` profili kaydedildi; uygulama ve DMG Apple tarafından kabul edildi, stapling ve Gatekeeper kontrolleri geçti. Sertifika adında Türkçe karakter
kodlaması sorunu yaşanırsa `security find-identity -v -p codesigning` çıktısındaki
40 karakterlik sertifika parmak izi SIGNING_IDENTITY olarak kullanılabilir.

## 4. İmzalı DMG'yi üretme

Codex'e sertifika ve `ipscanner-notary` profilinin hazır olduğunu söylemen yeterli.
Kendin çalıştırmak istersen, bu kopyanın `iPScanner` klasöründe Terminal aç ve
sertifika adını ikinci adımdaki çıktıyla birebir değiştir:

```bash
export SIGNING_IDENTITY='Developer ID Application: AD SOYAD (TEAMID)'
export NOTARY_PROFILE='ipscanner-notary'
./scripts/build-dmg.sh 1.3.0
```

Bu işlem testleri çalıştırır; GUI ve CLI'ı ayrı derler; içten dışa imzalar;
uygulamayı Apple'a gönderir, onay biletini ekler; DMG'yi oluşturup imzalar,
notarize eder ve tekrar doğrular. Sparkle yardımcılarını da içten dışa imzalar;
son DMG için Ed25519 imzası ve güncelleme kaydı üretir. Başarısız imza veya Apple onayında durur.
Aynı sürümün önceki build klasörü varsa üzerine yazmaz; onu arşivleyip temiz
bir çalışma dizininden yeniden başlat.

Çıktılar: `build/release-1.3.0/iPScanner-v1.3.0.dmg` ve yanındaki `.sha256` dosyası.
Bu script GitHub'a yayın yapmaz. Yerel Sparkle özel anahtarı Keychain içindeki
`ipscanner` hesabında bulunmalıdır. Sonraki sürümde `project.yml` içindeki
`CURRENT_PROJECT_VERSION` değerini artır. Dosyalar yayınlandıktan ve indirilebilirliği
doğrulandıktan sonra üretilen appcast ana dala alınır; [ayrıntılı sıra](automatic-updates.md).

## 5. Paylaşmadan önce

- Temiz bir kullanıcı hesabında veya ikinci Mac'te DMG'yi aç, uygulamayı Applications'a taşı.
- Finder'dan aç: ana pencere görünmeli. CLI kullanım metniyle kapanmamalı.
- Browser üzerinden indirilen imzalı DMG'de açılışı doğrula; quarantine kaldırma komutu kullanma.
- Sequoia 15 ve desteklenen minimum macOS 14.4 üzerinde açılışı kontrol et.
- Tarama, Stop, Deep, snapshot ve dışa aktarmayı dene.
- Codex'teki doğrulama raporunu ve sürüm notlarını incele.
- Sonrasında DMG ve SHA-256 dosyasını GitHub sürümüne ekleyip yayınla.

GitHub Actions kullanılırsa `release` environment altında şu secrets gerekir:
`DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD`, `DEVELOPER_ID_IDENTITY`,
`NOTARY_API_KEY_P8_BASE64`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`, `SPARKLE_PRIVATE_KEY`.
Yerel imzalama için bunları GitHub'a eklemek gerekmez. Workflow yalnızca taslak
release oluşturur; yayın ayrı bir adımdır.


## macOS 27: MAC bilgisi için ek yayın koşulu

Bu Mac'te Terminal ARP kayıtlarını gösterirken uygulamanın başlattığı aynı komut
başarı koduyla boş çıktı verdi. Apple'ın Network Topology Observation yetkisi
(`com.apple.developer.networking.topology-observation`) ve uygun provisioning
profile koşulu imzalama aşamasında değerlendirilmelidir. Yetkiyi ad-hoc uygulamaya
eklemek yeterli değildir. GUI ve paket içindeki CLI ayrı ayrı gerçek MAC erişimiyle
doğrulanmalı; CLI için Apple'ın açıkladığı profile/app-like wrapper gereksinimi
kontrol edilmelidir. Yayınlanan Developer ID imzalı 1.3.0 paketine bu kısıtlı yetki henüz eklenmedi.

- https://developer.apple.com/forums/thread/841958
- https://developer.apple.com/forums/thread/822025?page=2

macOS 27'de MAC ve üretici bilgisi bu kontrol tamamlanana kadar yayın kabulünden
geçmiş sayılmaz. Bu kısıt tek başına IP keşfinin başarısız olduğu anlamına gelmez.
