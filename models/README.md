# models/ — ML Model Dosyaları

**Bu klasördeki model dosyaları git'e commit edilmez.** Boyut sebebiyle indirme
talimatları burada tutulur.

## Şu an

Klasör boş. Projede henüz özel bir ML modeli kullanılmıyor — tek ML bileşeni Apple
Vision'ın kapalı kutu modelleridir ve o sistemle birlikte gelir.

## Planlanan

### MediaPipe Face Landmarker (MVP 2)

| Alan | Değer |
|---|---|
| Dosya | `face_landmarker.task` |
| İçerik | Face detector + face mesh + iris (attention mesh) + blendshapes |
| Çıktı | 478 landmark |
| Boyut | ~3–4 MB · **TODO: verify** |
| Kaynak | Google MediaPipe resmî model deposu |

İndirme talimatı ve beklenen SHA256 buraya yazılacak. Model sürümü sabitlenmelidir —
sürüm değişikliği landmark topolojisini veya hassasiyeti değiştirebilir ve tüm
eşiklerimizi geçersiz kılabilir.

### DeepWarp göz düzeltme ağırlıkları (MVP 7)

| Alan | Değer |
|---|---|
| Dosyalar | Sol ve sağ göz için ayrı checkpoint'ler |
| Format | TF1 checkpoint → ONNX → CoreML/TFLite |
| Kaynak | ⚠️ **Elimizde yok** — orijinal projenin GitHub Releases sayfası veya sıfırdan eğitim |

Mimari `reference/deepwarp-cam/` altında mevcut; ağırlıklar değil.
Detay: [docs/MODEL_PIPELINE.md](../docs/MODEL_PIPELINE.md)

## Kural

Model dosyalarını repository'ye ekleme. `.gitignore` bu klasörün içeriğini dışlar
(bu README hariç). Bir model eklediğinde buraya kaydet: dosya adı, sürüm, boyut,
SHA256, indirme kaynağı, ve hangi kodun beklediği.
