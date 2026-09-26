# Yayın sonrası işler

[1.3.0](https://github.com/canberkys/iPScanner/releases/tag/v1.3.0) 26 Eylül 2026'da
yayınlandı. Yeni radar ikonu, Sparkle güncellemeleri, Developer ID imzası,
notarization, DMG ve checksum tamamlandı. #10'daki paketleme hatası giderildi ve
issue kapatıldı. Üçüncü taraf bağımlılığı eklememe kararı Sparkle için değiştirildi;
CLI'ye Sparkle bağımlılığı eklenmedi.

## Doğrulama öncelikleri

- macOS 27 MAC erişimi için Network Topology Observation capability ve GUI/CLI
  provisioning gereksinimini doğrula. Terminal üzerinden erişim kısıtını aşma.
- Intel, macOS 14.4 ve Sequoia üzerinde indirilen DMG'den temiz açılışı dene.
- 800 / 960 / 1280 genişliklerde açık/koyu tema, klavye ve VoiceOver matrisini tamamla.
- Canlı Bonjour kaydı kaybolması, ağ değişimi ve fiziksel Wake-on-LAN kontrollerini tamamla.
- Sparkle indirme iptali, kesilen kurulum ve herkese açık eski→yeni sürüm geçişini doğrula.
- GitHub Actions imzalı dağıtımı için release ortamındaki güvenli anahtar kurulumunu doğrula.

Her sonucun kanıtını [kabul tablosuna](acceptance-1.3.0.md) ekle. Henüz denenmemiş
senaryoları geçmiş sayma. Gelecek yayınlar [güncelleme sırasını](automatic-updates.md)
izlemeli: önce imzalı dosya, ardından doğrulama ve en son appcast.

## Kapsam dışında kalan fikirler

Cihaz geçmişi, IPv6 ve menü çubuğu modu henüz uygulanmadı; bunlar için yayın tarihi
belirlenmedi. Yeni talepler GitHub issue'larında değerlendirilir.
