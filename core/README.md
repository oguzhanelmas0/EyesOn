# core/ — Paylaşılan Çekirdek

**Şu an boş.** Bilinçli olarak.

## Ne olacak

Platformdan bağımsız algoritma çekirdeği: landmark → doğrulama → bakış tahmini →
davranış FSM → yumuşatma → warp → harmanlama. Bu zincir beş platformda da matematiksel
olarak aynıdır.

## Neden henüz boş

Çekirdeğin hangi dilde yazılacağı, macOS'ta MediaPipe'ı nasıl çalıştırdığımıza bağlı ve
o soru henüz açık (`.ai/DECISIONS.md` → ADR-002).

İki ihtimal:

- **C++ çekirdek** — MediaPipe'ı zaten C++ olarak bağlıyorsak doğal seçim; beş platformda
  tek kod. Bedeli: Swift/Kotlin köprüleri, daha zor derleme zinciri.
- **Platform başına port** — algoritma `docs/EYE_CONTACT.md`'de tek doğruluk kaynağı
  olarak yaşar, her platform kendi dilinde uygular. Bedeli: dört kez yazmak ve senkron
  tutmak.

Karar MVP 8'e başlamadan hemen önce verilecek — o noktada MediaPipe entegrasyonunun
gerçek maliyeti bilinir olur. **Bu bilinçli bir ertelemedir; erken soyutlama yapmıyoruz.**

Bugün algoritmanın tek doğruluk kaynağı: [docs/EYE_CONTACT.md](../docs/EYE_CONTACT.md)
