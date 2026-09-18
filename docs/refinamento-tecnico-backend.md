# NadaAqui — Refinamento técnico (Backend)

**Para:** Po / Joãozinho  
**De:** Backend  
**Data:** 2026-09-17  
**Base:** `backlog-mvp.md`

---

## Recomendação de stack (decisão #1)

**Recomendo Supabase (Postgres + Auth + Storage + Realtime) para o MVP.**

| Critério | Supabase | Firebase | Spring Boot (custom) |
|---|---|---|---|
| Proximidade (mapa) | PostGIS nativo, simples | Geohash / GeoFire, mais frágil | PostGIS possível, mais infra |
| Guest / RLS | RLS por role, leitura pública fácil | Rules por collection | API + JWT, mais código |
| “Quem está aqui” | Realtime + índice `place_id` | Firestore listeners | WebSocket/SSE próprios |
| Time Flutter MVP | Bom (supabase_flutter) | Excelente (FlutterFire) | Precisa API REST completa |
| Custo/ops MVP | Baixo | Baixo | Alto (hosting, deploy, ops) |

**Spring Boot** fica como caminho natural se o produto sair do BaaS (billing, anti-fraude forte, multi-região). **Não** é o melhor atalho para o MVP Android.

**Decisão pendente de Joãozinho:** Supabase vs Firebase. Abaixo assume **Supabase**; se escolher Firebase, a lógica de negócio se mantém e a geo vira geohash.

---

## 1) Modelo de dados

### Enums
- `price_type`: `free` | `paid` | `unknown`
- `total_pass`: `yes` | `no` | `unknown`
- `place_type`: `pool` | `beach` | `lake` | `river` | `club` | `other` (ajustável)
- `suggestion_status`: `pending` | `approved` | `rejected`
- `suggestion_kind`: `new_place` | `correction`

### `profiles` (1:1 com `auth.users`)
| Campo | Tipo | Notas |
|---|---|---|
| id | uuid PK = auth.uid | |
| display_name | text | |
| avatar_url | text nullable | |
| show_in_presence | bool default true | HU-07 |
| created_at / updated_at | timestamptz | |

### `places`
| Campo | Tipo | Notas |
|---|---|---|
| id | uuid PK | |
| name | text | |
| place_type | enum | |
| description | text nullable | |
| address | text nullable | |
| location | geography(Point, 4326) | lat/lng |
| price_type | enum | HU-03 |
| total_pass | enum | HU-03 |
| price_note | text nullable | “aprox. R$ …” |
| opening_hours | jsonb nullable | |
| photos | text[] | URLs Storage |
| rating_avg | numeric nullable | só exibir no MVP |
| rating_count | int default 0 | |
| city_slug | text | cidade piloto |
| is_published | bool default true | seed = true |
| created_at / updated_at | timestamptz | |

**Índices:** GIST em `location`; btree em `(city_slug, is_published)`; btree em `price_type`, `total_pass`.

### `check_ins`
| Campo | Tipo | Notas |
|---|---|---|
| id | uuid PK | |
| user_id | uuid FK profiles | |
| place_id | uuid FK places | |
| lat / lng | float | snapshot no momento |
| distance_m | int | audit |
| started_at | timestamptz | |
| expires_at | timestamptz | started_at + TTL |
| ended_at | timestamptz nullable | checkout / novo check-in |
| visible_in_presence | bool | cópia do toggle no momento + updates |
| status | `active` \| `ended` | |

**Índices:** `(place_id, status, expires_at)` onde `status = active`; unique parcial: **um check-in `active` por `user_id`**.

### `posts`
| Campo | Notas |
|---|---|
| id, user_id, place_id nullable, body, photo_url, created_at | body ≤ 500 chars; 1 foto opcional |

### `comments`
| Campo | Notas |
|---|---|
| id, post_id (ou target polimórfico), user_id, body, created_at | MVP: só em `posts`; check-in no feed pode ser card sem comentário no P2 inicial, ou `target_type`/`target_id` |

### `likes`
- `(user_id, target_type, target_id)` unique — `post` | `check_in`

### `favorites`
- `(user_id, place_id)` unique

### `place_suggestions`
| Campo | Notas |
|---|---|
| id, user_id, kind | new_place / correction |
| place_id nullable | correction |
| payload | jsonb (nome, tipo, lat/lng, price_type, total_pass, notas) |
| status | pending / approved / rejected |
| reviewer_id, review_note, created_at, reviewed_at | |

### `curators` (ou claim em profile)
- `user_id` com `role = curator` para moderação HU-10

### Seed
- Tabela `places` com `city_slug` da piloto; JSON/CSV importado uma vez via script SQL ou Edge Function admin.

---

## 2) Auth + guest mode

**Proposta**
- **Auth:** e-mail/senha no MVP (OAuth Google opcional se sobrar tempo — Sprint 1 não depende).
- **Guest (obrigatório):** sem conta no servidor. App lê `places` públicos (RLS: `is_published = true` para `anon` + `authenticated`).
- Ações que **exigem login:** check-in, favorito, post, like, comment, sugerir local/correção, editar perfil.
- Sessão: refresh token persistido no app (supabase_flutter); logout limpa.

**RLS (resumo)**
- `places` published: SELECT para `anon` e `authenticated`
- `check_ins` active: SELECT de linhas `visible_in_presence = true` (ou agregados); próprio user vê o seu sempre
- writes: só `authenticated` e dono do row

**Erro de credencial:** mapear códigos Auth para mensagens PT-BR no app (não vazar detalhe interno).

---

## 3) Query de locais por proximidade + filtros

**RPC sugerida:** `nearby_places(lat, lng, radius_m, price_types[], total_pass_values[], limit, offset)`

```sql
-- conceito
ST_DWithin(location, ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography, radius_m)
ORDER BY location <-> ponto
```

**Defaults MVP**
- Raio inicial mapa: **5 km** (ajustável); lista “perto de mim” mesma query
- Paginação: 50 itens; clustering no client se zoom out
- Filtros combináveis:
  - `price_type IN (...)` se usuário marcar Grátis/Pago
  - `total_pass`: “Aceita” → só `yes`; “Não aceita” → só `no`; **`unknown` fora dos dois** (regra documentada)
- Sem GPS: fallback **cidade piloto** (`city_slug = :piloto`) ordenado por nome; busca manual por texto depois se couber

Distância formatada no **client** (m / km).

---

## 4) Check-in (raio + TTL + checkout + presença)

**Constantes (confirmar com Joãozinho)**
- Raio: **200 m** (meio-termo 150–300)
- TTL: **3 h**
- Regra multi-check-in: **novo check-in encerra o anterior** (`ended_at = now()`, `status = ended`)

**Fluxo server (Edge Function ou RPC `create_check_in`)**
1. Exigir auth + lat/lng do device
2. Carregar `places.location`; calcular distância
3. Se `distance_m > 200` → 400 com código `OUT_OF_RANGE`
4. Encerrar check-in active anterior do user
5. Inserir com `expires_at = now() + interval '3 hours'`, `visible_in_presence` do profile
6. Retornar check-in + presença resumida do place

**Checkout:** `end_check_in(id)` seta `ended_at`, `status = ended`.

**Expiração:** job periódico (pg_cron / Edge scheduled) a cada 5–10 min: `UPDATE check_ins SET status = 'ended', ended_at = now() WHERE status = 'active' AND expires_at < now()`.  
App também trata `expires_at` localmente para UX.

**Presença por `placeId`:** query `WHERE place_id = ? AND status = 'active' AND expires_at > now()`.

**Anti-fraude MVP:** só distância + timestamp + 1 active/user. Sem attestation de device.

**HU-07:** toggle atualiza `profiles.show_in_presence` e o check-in active (`visible_in_presence`).  
**Sugestão alinhada ao PO:** ocultos **contam** no total anônimo (`visible_count` + `hidden_count`), sem nome/avatar.

---

## 5) Realtime vs polling (“quem está aqui”)

**Recomendação híbrida (MVP)**
1. Ao abrir ficha: fetch presence (RPC)
2. Subscribe Realtime em `check_ins` filtrado por `place_id` (INSERT/UPDATE/DELETE)
3. Pull-to-refresh + re-fetch ao voltar à tela
4. Se Realtime falhar: polling a cada **30 s** só com a ficha aberta

**Não** usar Realtime global de todos os places no mapa no MVP (custo/bateria).

Feed (HU-08): **polling / fetch on open** no MVP; Realtime opcional depois.

---

## 6) Moderação de sugestão de local

**Fluxo**
1. User autenticado cria `place_suggestions` (`pending`)
2. Curator lista pendentes (app admin mínimo **ou** Table Editor + filtro no Supabase Studio no MVP)
3. Approve:
   - `new_place` → INSERT `places` + `is_published = true` (ou false se quiser double-check)
   - `correction` → UPDATE campos permitidos (`price_type`, `total_pass`, opcionalmente nome/endereço)
4. Reject + `review_note` opcional
5. User vê status no perfil (lista das próprias suggestions)

**Dedup (leve):** ao aprovar `new_place`, avisar se existe place com mesmo `city_slug` a &lt; **100 m** e nome similar (trigram/`pg_trgm`). Curator decide merge/reject.

**Fora do MVP:** app admin polido, fila com SLA, ML.

---

## 7) Estimativa Backend por HU

Escala: **S / M / L** (esforço backend+dados, 1 dev).  
S ≈ 0,5–1d · M ≈ 1–2d · L ≈ 3–4d

### P0
| HU | Esforço | Escopo backend |
|---|---|---|
| HU-01 Conta/sessão | **M** | Auth e-mail/senha, profiles, RLS guest vs auth, mensagens erro |
| HU-02 Mapa/proximidade | **L** | Schema places + PostGIS, RPC nearby, seed cidade, índices |
| HU-03 Filtros | **S** | Estende RPC; enums e regras `unknown` |
| HU-04 Ficha | **S** | GET place by id; Storage URLs fotos seed |

**P0 total ≈ L+M+S+S → ~1 sprint backend** (com seed e RLS feitos direito).

### P1
| HU | Esforço | Escopo |
|---|---|---|
| HU-05 Check-in GPS | **L** | RPC create, raio, unique active, checkout |
| HU-06 Quem está aqui | **M** | Query presença, cron TTL, Realtime channel |
| HU-07 Privacidade | **S** | Toggle + update presence visibility + contadores |

**P1 total ≈ L+M+S → ~1 sprint.**

### P2
| HU | Esforço | Escopo |
|---|---|---|
| HU-08 Feed | **M** | posts + cards check-in; feed por `city_slug` |
| HU-09 Curtir/comentar | **M** | likes/comments + RLS |
| HU-10 Sugestões | **L** | suggestions + approve/reject + dedup leve |
| HU-11 Favoritos | **S** | tabela + RLS |
| HU-12 Perfil | **S** | update profile + list suggestions/favorites |

**P2 total ≈ 2 sprints** se HU-10 for bem feito; dá para paralelizar 08/09/11/12.

---

## Riscos

1. **Decisão Firebase vs Supabase em aberto** — bloqueia schema e SDKs no Flutter.
2. **GPS impreciso / indoor** — falsos OUT_OF_RANGE; mitigar raio 200 m + mensagem clara; não apertar demais no MVP.
3. **Presença “fantasma”** — TTL + cron; senão lista mente.
4. **Abuso de check-in** (mock location) — aceitar no MVP; documentar dívida.
5. **Seed de qualidade** — 20–50 locais com foto/Total Pass `unknown` demais mata o filtro; curadoria manual é caminho crítico.
6. **Realtime + bateria** — limitar subscribe à ficha aberta.
7. **Moderação sem curator** — HU-10 não fecha sem alguém aprovando (Studio ok no início).
8. **Escopo do feed** indefinido — muda índice e volume.

---

## Decisões técnicas (propostas para fechar)

| # | Tema | Proposta Backend |
|---|---|---|
| D1 | BaaS | **Supabase** |
| D2 | Auth MVP | E-mail/senha; guest só leitura |
| D3 | Raio check-in | **200 m** |
| D4 | TTL | **3 h** + checkout manual |
| D5 | Multi check-in | Novo **encerra** o anterior |
| D6 | Ocultos | Contam no total anônimo |
| D7 | Presença | Realtime na ficha + fetch inicial + refresh |
| D8 | Feed MVP | Só **cidade piloto** (`city_slug`) |
| D9 | Avaliações | Só **exibir** seed; criar = fora MVP |
| D10 | Moderação | Supabase Studio + role curator no início |

---

## O que falta no brief (bloqueadores / esclarecimentos)

1. **Cidade piloto** (slug + bounding box)
2. **Firebase vs Supabase** (Joãozinho)
3. Confirmar **raio 200 m** e **TTL 3 h**
4. Confirmar **ocultos no contador anônimo**
5. **Escopo do feed** (piloto vs perto de mim)
6. Quem é **curator** no MVP (Joãozinho só?)
7. Formato do **seed** (CSV/GeoJSON) e dono da curadoria
8. Provider de **mapa** no app (afeta só front, mas lat/lng padrão WGS84)
9. Limite de **tamanho de foto** / compressão
10. Política de **conta excluída** / LGPD mínimo (apagar profile + anonimizar posts?) — nem citado

---

## Próximos passos (Backend)

1. Joãozinho fecha D1–D6 (e cidade piloto).
2. Backend entrega: schema SQL + RLS + RPC `nearby_places` + `create_check_in` + seed script stub.
3. Alinhar contratos com Front End Mobile Android (DTOs / erros).
4. QA: bateria de casos GPS / TTL / filtros / guest (pedir ao QA Test quando HUs P0 fecharem contrato).


---

## Atualização PO (2026-09-17)

- Raio: **config `checkInRadiusMeters`** (Front default **150**; range 80–150 até Joãozinho fechar). Não hardcodar 200.
- Novo check-in encerra o anterior; `ALREADY_CHECKED_IN` só com `endPrevious=false`.
- **HU-13 (P2):** exclusão de conta / LGPD mínimo — anotar no backlog PO.
- Contratos: `openapi/nadaaqui-v1.yaml` + mock em `mock/`.
