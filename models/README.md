# models/ — ML Model Dosyaları

**Bu klasördeki model dosyaları git'e commit edilmez.** Boyut sebebiyle indirme
talimatları burada tutulur.

## Şu an

| Dosya | Ne | Boyut |
|---|---|---|
| `face_landmarks_detector.onnx` | MediaPipe Face Landmarker, 478 nokta | 4.7 MB |
| `deepwarp/weights/warping_model/flx/12/{L,R}` | DeepWarp TF1 checkpoint'leri (kaynak) | ~6 MB |
| `deepwarp/onnx/deepwarp_{L,R}.onnx` | Dönüştürülmüş DeepWarp modelleri | ~1.05 MB ×2 |

### ⚠️ Git istisnası

Uygulamanın çalışması için gereken **üç `.onnx` dosyası** `apps/macos/EyesOn/` altında
bulunur ve **git'te izlenir** (toplam ~6.7 MB). Sebebi pratik: bunlar olmadan uygulama
derlense de çalışmaz, ve boyutları git için sorun çıkarmayacak kadar küçük.

Bu klasördeki (`models/`) her şey git dışıdır — burası kaynak checkpoint'ler ve dönüşüm
çıktıları için çalışma alanıdır.

### DeepWarp ağırlıklarını yeniden edinme

```bash
gh release download v0.1.1 -R WangWilly/gaze-correction-cam -p weights.zip
unzip weights.zip -d models/deepwarp/
```

Dönüşüm: `scratchpad/convert_deepwarp.py` (TF 2.19.1 + tf2onnx 1.17.0, opset 13).
Betik TF ve ONNX çıktılarını aynı girdide karşılaştırır — model güncellenirse bu
karşılaştırma tekrar çalıştırılmalıdır (bkz. EXP-007).

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
