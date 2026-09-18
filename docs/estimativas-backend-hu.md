# Estimativas Backend (S/M/L) — NadaAqui

S ≈ 0,5–1d · M ≈ 1–2d · L ≈ 3–4d

## P0
| HU | Est. | Nota |
|---|---|---|
| HU-01 Conta/sessão | M | Auth + profiles + RLS guest |
| HU-02 Mapa/proximidade | L | PostGIS + RPC nearby + seed |
| HU-03 Filtros | S | Extensão RPC |
| HU-04 Ficha | S | GET detail + fotos |

## P1
| HU | Est. |
|---|---|
| HU-05 Check-in | L |
| HU-06 Presence | M |
| HU-07 Privacy | S |

## P2
| HU | Est. |
|---|---|
| HU-08 Feed | M |
| HU-09 Like/comment | M |
| HU-10 Suggestions | L |
| HU-11 Favorites | S |
| HU-12 Profile | S |
| HU-13 LGPD exclusão | M | novo (PO) |

Contratos/mock Sprint 1: **S** (entregue).
Schema SQL+RLS+RPCs após decisão stack: **L**.
