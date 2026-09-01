# reference/ — Referans Projeler

Buradaki kod **okumak ve port etmek içindir.** Derlenmez, çalıştırılmaz, çağrılmaz.
Build sisteminin bir parçası değildir.

| Klasör | Kaynak | Lisans | Yaklaşım |
|---|---|---|---|
| `gaze-corrector/` | github.com/dkohn1337/gaze-corrector | MIT | Geometrik warp + davranış FSM'i |
| `deepwarp-cam/` | github.com/WangWilly/gaze-correction-cam | MIT | Öğrenilmiş warp (DeepWarp) + 3B geometri |

İkisi de MIT lisanslıdır ve `LICENSE` dosyalarıyla birlikte kopyalanmıştır.
**Türetilen kodda atıf koruyun.**

## Neden buradalar

Bu projeler `Examples/` klasöründen damıtıldı. `Examples/` 4.9 GB'tı (çoğu Python venv'i)
ve silinecektir. İhtiyacımız olan ~4900 satır kaynak kod buraya kopyalandı ve git'e
alındı, böylece `Examples/` silindikten sonra da erişilebilir kalır.

**Hiçbir kod, doküman veya betik `Examples/` içine referans veremez** (ADR-005).

## Ne alınmadı

- Python venv'leri, `.git` klasörleri, `poetry.lock`
- Model ağırlıkları — **zaten yoktular**, arandı

## Hangi parça nereye gidiyor

Detaylı eşleme: [docs/REFERENCE_PROJECTS.md](../docs/REFERENCE_PROJECTS.md)

Algoritmanın damıtılmış hali (bu klasör silinse bile yeniden inşa edilebilecek şekilde):
[docs/EYE_CONTACT.md](../docs/EYE_CONTACT.md)
