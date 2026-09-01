# .ai/ — Proje Hafızası

Bu klasör, Claude / Codex / Gemini arasında paylaşılan **canlı proje hafızasıdır.**
Sohbet geçmişi paylaşılmadığı için devir teslim buradan yapılır.

| Dosya | Ne için | Ne zaman güncellenir |
|---|---|---|
| `CURRENT_TASK.md` | Yalnız **aktif** görevin güncel durumu | Göreve **başlarken** ve ilerledikçe |
| `WORKLOG.md` | Tamamlanmış anlamlı çalışmaların kaydı | Bir görev bittiğinde |
| `DECISIONS.md` | Kalıcı mimari kararlar (ADR) | Bir karar verildiğinde |
| `EXPERIMENTS.md` | Denenmiş yöntemler — **başarısızlar dahil** | Bir deney sonuçlandığında |

## Ayrım

- `CURRENT_TASK.md` bir **günlük değildir.** Sadece şu an ne yapıldığını tutar.
  Görev bitince içeriği `WORKLOG.md`'ye özetlenip CURRENT_TASK yeni göreve göre sıfırlanır.
- `docs/` altındaki dosyalar **kalıcı bilgidir** (mimari, algoritma, platform).
  `.ai/` altındakiler **zamana bağlı durumdur** (ne yapılıyor, ne denendi, ne karar alındı).
- Aynı bilgiyi iki yerde tutma. `docs/` neyin nasıl çalıştığını, `.ai/` nerede
  kalındığını anlatır.

## EXPERIMENTS.md neden önemli

Eye-contact correction araştırma ağırlıklı bir problemdir. Bir yöntemin neden
başarısız olduğu, hangi parametrelerde denendiği ve hangi donanımda ölçüldüğü
kaybolursa bir sonraki agent aynı çıkmazı tekrar yürür. Başarısız deneyleri silmeyin.
