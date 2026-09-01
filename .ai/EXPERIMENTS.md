# Experiments

Denenmiş yöntemler — **başarısız olanlar dahil.** Eye-contact correction araştırma
ağırlıklı bir problemdir; bir yaklaşımın neden işe yaramadığı kaybolursa bir sonraki
agent aynı çıkmazı tekrar yürür.

**Format kuralı:** Ölçüm yapılmadıysa "Not measured" yaz, sayı uydurma. Hangi donanımda
ölçtüğünü mutlaka belirt.

---

## Henüz deney kaydı yok

Bu dosya MVP 1 ile dolmaya başlayacak. İlk planlanan deney:

### EXP-001 (planlandı) — Mevcut Metal Gaussian warp'ın baseline'ı

**Hypothesis:** Mevcut `GaussianEyeWarp.metal` düzeltmesi ya hiç görünür etki üretmiyor
ya da yanlış yönde/miktarda uyguluyor (son commit mesajının iddiası).

**Method:** Uygulamayı derle, çalıştır, "⚡ Düzeltme" toggle'ını aç. Aynı sabit poz için
düzeltme kapalı ve açık ekran görüntülerini karşılaştır. Sonra kafayı hareket ettirerek
kısa bir video kaydı al ve temporal davranışı incele.

**Ölçülecekler:** görsel etki var mı · yön doğru mu · jitter/flicker var mı · göz kırpma
sırasında ne oluyor · FPS düşüşü.

**Neden önemli:** MediaPipe'a geçmeden (ADR-001) önce mevcut durumun baseline'ını
kaydetmezsek, iyileşmenin gerçekten MediaPipe'tan mı yoksa başka bir düzeltmeden mi
geldiğini bilemeyiz.

**Not:** ADR-001 "Apple Vision'ın kaba pupil noktası kök nedendir" hipotezine dayanıyor.
Bu deney o hipotezi test eder. Eğer düzeltme başka bir sebeple (örn. koordinat ekseni
hatası, kernel parametresi) bozuksa MediaPipe'a geçmek sorunu çözmez — bunu önceden
bilmek çok değerlidir.
