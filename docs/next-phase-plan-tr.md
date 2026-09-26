> 26 Eylül 2026 güncellemesi: Radar ikonu seçildi ve uygulamaya eklendi.
> vLens ile aynı Sparkle yaklaşımı uygulanıyor; güncel akış ve yayın adımları
> [automatic-updates.md](automatic-updates.md) belgesinde. Aşağıdaki metin önceki planı kaydeder.

# Sonraki aşama: kimlik, güncelleme ve yayın

Logo ve otomatik kurulum henüz uygulanmadı. Developer ID ve notarization tamamlandı; yayın öncesi açık testler sürüyor. Önce `acceptance-1.3.0.md` içindeki açık kabul kontrolleri
kapatılmalı; yerel adayın yayın sürümü olduğu varsayılmamalı.

## 1. Logo

- Kompakt ağ keşfi aracı kimliğine uygun 2–3 yön hazırla ve kullanıcıyla seç.
- macOS ikon maskesi, küçük boyutta okunurluk, açık/koyu Dock görünümü kontrol et.
- AppIcon setini, README ekranlarını ve GitHub görsellerini birlikte güncelle.

## 2. Otomatik güncelleme kurulumu

- Mevcut GitHub kontrolü ve kullanıcı kontrollü indirme korunur.
- İmzalı güncelleme, atomik değiştirme, geri alma ve başarısız indirme davranışını tasarla.
- Sparkle gibi yerleşik bir çözüm ile bağımlılıksız yaklaşımın bakım/güvenlik yükünü
  karşılaştır. Üçüncü taraf çalışma zamanı kuralı değiştirilmeden Sparkle eklenmez.
- İmzalanmamış uygulamaya otomatik kurulum ekleme. Sürüm/kanal seçimi, açık rıza,
  uygulama kullanımdayken kurulum ve standart kullanıcı hesabı ayrı kabul ölçütleri olsun.

## 3. Developer ID ve macOS 27 MAC erişimi

- Kullanıcı Apple hesabını Xcode'a ekler; sertifika/özel anahtar Keychain'de kalır.
- Network Topology Observation capability ve provisioning profile gereksinimini
  GUI ve yardımcı CLI için doğrula. Kısıtlı entitlement ad-hoc pakete eklenmez.
- Hardened Runtime, içten dışa imza, notarization ve stapling doğrulanır.
- macOS 14.4, Sequoia ve Intel kontrolü; indirilen quarantined DMG'den temiz açılış.

## 4. Yayın

- DMG ve SHA-256 üret; paketteki GUI/CLI mimarilerini, veri indeksini ve imzayı doğrula.
- Tamamlanan kabul tablosu üzerinden kullanıcıya inceleme paketi sun.
- Onaylanan sürümde Unreleased başlığını tarihli 1.3.0'a çevir; changelog'dan GitHub
  Release metni oluştur, bilinen sınırlamaları ekle.
- GitHub yayını ve #10 yanıtını hazır paket/metin üzerinden ayrı adımda yap.
