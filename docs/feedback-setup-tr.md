# Geri bildirim kanalını etkinleştirme

Cloudflare Worker kuruldu:
https://ipscanner-feedback-relay.ck-7fa.workers.dev

Akış: uygulamada **Send Feedback** → Cloudflare → `canberkys/iPScanner`
deposunda **herkese açık GitHub issue**. E-posta/Telegram servisi değildir.
GitHub bildirimleri için depo sayfasında Watch → Custom → Issues seçilebilir.

## Kalan adım: GitHub erişimi

1. GitHub → profil resmi → Settings → Developer settings → Personal access tokens
   → Fine-grained tokens → Generate new token.
2. İsim: `iPScanner feedback relay`. Bir son kullanma tarihi belirle.
3. Repository access: **Only select repositories** → **iPScanner**.
4. Repository permissions → **Issues: Read and write**. Diğer yazma yetkilerini açma.
5. Token oluştur. Sohbete, kaynak koda veya komut satırına yapıştırma.
6. Terminal'de şu komutları çalıştır:

```bash
cd '/Users/c.kilicarsl/Documents/Codex/2026-09-26/https-github-com-canberkys-ipscanner-https/outputs/iPScanner/feedback-relay'
npx wrangler secret put GITHUB_PAT
```

7. Wrangler gizli değer istediğinde token'ı oraya yapıştırıp Enter'a bas.
   Bu işlem token'ı Cloudflare secret olarak kaydeder; uygulama paketine girmez.
8. Tamamlanınca haber ver. Servisin hazır durumunu kontrol edip bir kontrollü
   test issue gönderimiyle canlı teslimi doğrulayacağız.

Anahtar eklenene kadar servis HTTP 503 döndürür; uygulama hata gösterir ve taslağı
korur. Token süresi dolduğunda yenisini aynı komutla yükle.
