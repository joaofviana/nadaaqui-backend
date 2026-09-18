# Contrato canônico — RPCs PostgREST

Fonte da verdade para o app live: **migrations + RPCs** em `supabase/migrations/`.
O YAML em `openapi/nadaaqui-v1.yaml` descreve o mock REST `/v1` (WireMock).
Se OpenAPI e RPC divergirem, **a RPC ganha** — depois atualiza o YAML.

Base live: `{SUPABASE_URL}/rest/v1/rpc/{nome}`  
Headers: `apikey` + `Authorization: Bearer <anon | access_token>`  
`Content-Type: application/json`

Guest (`anon`) lê mapa/ficha/presença. Check-in exige `authenticated`.

## RPCs

| Uso no app | RPC | Grants |
|---|---|---|
| Config | `get_remote_config()` | anon, authenticated |
| Lista | `nearby_places(p_lat, p_lng, p_radius_meters, p_bbox, p_city_slug, p_price_types, p_total_pass, p_limit, p_offset)` | anon, authenticated |
| Ficha | `get_place(p_place_id uuid)` | anon, authenticated |
| Check-in | `create_check_in(p_place_id, p_lat, p_lng, p_accuracy_meters, p_captured_at, p_end_previous)` | authenticated |
| Checkout | `checkout_check_in(p_check_in_id uuid)` | authenticated |
| Presença | `who_is_here(p_place_id uuid)` | anon, authenticated |

Job interno (não chamar do app):

| Job | Função | Grants |
|---|---|---|
| TTL | `expire_check_ins()` | **service_role only** |

## Params (body JSON)

### `nearby_places`

```json
{
  "p_lat": -23.5802452,
  "p_lng": -46.6058969,
  "p_radius_meters": 5000,
  "p_city_slug": "sao-paulo",
  "p_limit": 50,
  "p_offset": 0
}
```

Resposta: **array** de rows (PostgREST). Colunas snake_case:

`id, name, place_type, lat, lng, price_type, total_pass, distance_meters, thumbnail_url, total_count`

Cidade piloto default: `app_config.city_slug` (`sao-paulo`).

### `get_place`

```json
{ "p_place_id": "952f671d-fb18-46eb-a45a-e0897e925650" }
```

JSON camelCase. `distanceMeters` é **sempre `null`** — o app calcula no client
(`geo_math.dart`) com GPS atual. Place inexistente / não publicado → `null`.

### `get_remote_config`

Body `{}`. JSON camelCase: `checkInRadiusMeters`, `locationMaxAgeSeconds`,
`checkInTtlSeconds`, `presencePollSeconds`, `citySlug`.

Defaults de produto (não hardcodar no app): **150 m / 3 h**.

### `create_check_in`

```json
{
  "p_place_id": "…",
  "p_lat": -23.5802,
  "p_lng": -46.6059,
  "p_accuracy_meters": 12.0,
  "p_captured_at": "2026-09-18T03:00:00Z",
  "p_end_previous": true
}
```

`p_end_previous` default `true`: novo check-in **encerra** o anterior.
`ALREADY_CHECKED_IN` só quando `p_end_previous=false` e já existe ativo noutro place.
Mesmo place + ativo = **idempotente** (devolve o mesmo id).

HTTP 200 mesmo em erro de domínio. Corpo:

```json
{ "checkIn": { "id": "…", "placeId": "…", "userId": "…", "status": "active", "startedAt": "…", "expiresAt": "…", "endedAt": null, "distanceMeters": 42, "visibleInPresence": true }, "endedPreviousCheckInId": null }
```

ou

```json
{ "error": { "code": "OUT_OF_RANGE", "message": "…", "details": {} } }
```

### `who_is_here`

```json
{ "p_place_id": "…" }
```

```json
{
  "placeId": "…",
  "visibleCount": 2,
  "hiddenCount": 1,
  "people": [
    { "userId": "…", "displayName": "Ana", "avatarUrl": null, "checkedInAt": "…" }
  ]
}
```

Ocultos entram em `hiddenCount`, **sem** nome/avatar. Sem e-mail.

## Erros JSON (`create_check_in`)

Envelope sempre `{ "error": { "code", "message", "details" } }` no HTTP 200.

| code | Quando | details |
|---|---|---|
| `OUT_OF_RANGE` | distância > `app_config.check_in_radius_meters` | `distanceMeters`, `radiusMeters`, `placeId` |
| `LOCATION_STALE` | `captured_at` mais velho que `location_max_age_seconds` (ou >30s no futuro) | `maxAgeSeconds` |
| `ALREADY_CHECKED_IN` | ativo noutro place e `endPrevious=false` | `activePlaceId`, `activeCheckInId` |

Mensagens (pt-BR, como a RPC devolve hoje):

- `OUT_OF_RANGE`: `Você precisa estar mais perto do local para fazer check-in.`
- `LOCATION_STALE`: `Sua localização está desatualizada. Atualize o GPS e tente de novo.`
- `ALREADY_CHECKED_IN`: `Você já tem um check-in ativo em outro local.`

Exceções SQL (`raise exception`, PostgREST ~400/401, **não** envelope `{error}`):

| code (mensagem) | Quando |
|---|---|
| `UNAUTHORIZED` | `auth.uid()` nulo em write (`create_check_in`, `checkout_check_in`) |
| `NOT_FOUND` | place inexistente / não publicado |

## Mock vs live

| | Live | Dev fallback |
|---|---|---|
| Base | `{SUPABASE_URL}/rest/v1/rpc/…` | WireMock `{host}:8080/v1` (REST OpenAPI) |
| Onde mora o mock | — | **este repo:** `mock/wiremock/` |
| App | `--dart-define=SUPABASE_URL` + `SUPABASE_ANON_KEY` | sem defines → WireMock |

Não há dois YAMLs. O mobile **não** carrega cópia do contrato.
