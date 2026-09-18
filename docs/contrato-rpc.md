# Contrato canônico — RPCs (fonte da verdade do app live)

O OpenAPI em `openapi/nadaaqui-v1.yaml` descreve o mock `/v1` (WireMock).
O app em produção chama **PostgREST RPCs**. Se os dois divergirem, **a RPC + migration ganham**; depois atualize o YAML.

Base live: `{SUPABASE_URL}/rest/v1/rpc/{nome}`
Headers: `apikey`, `Authorization: Bearer {anon|access_token}`, `Content-Type: application/json`

## RPCs

| Uso | Função | Grants |
|---|---|---|
| Config | `get_remote_config()` | anon, authenticated |
| Lista | `nearby_places(p_lat, p_lng, p_radius_meters, p_bbox, p_city_slug, p_price_types, p_total_pass, p_limit, p_offset)` | anon, authenticated |
| Ficha | `get_place(p_place_id)` | anon, authenticated |
| Check-in | `create_check_in(p_place_id, p_lat, p_lng, p_accuracy_meters, p_captured_at, p_end_previous)` | authenticated |
| Checkout | `checkout_check_in(p_check_in_id)` | authenticated |
| Presença | `who_is_here(p_place_id)` | anon, authenticated |
| Expirar TTL | `expire_check_ins()` | **service_role** only |

`nearby_places` devolve linhas **snake_case**. O client mapeia para camelCase.
`get_place` devolve JSON camelCase com `distanceMeters: null` — distância é calculada no app.

## Erros de `create_check_in`

HTTP 200 com corpo:

```json
{
  "error": {
    "code": "OUT_OF_RANGE | LOCATION_STALE | ALREADY_CHECKED_IN",
    "message": "...",
    "details": {}
  }
}
```

Exceções Postgres `P0001`: `UNAUTHORIZED`, `NOT_FOUND`.

## Auth

- Guest (`anon`): lê places publicados + `who_is_here` + config.
- Check-in exige JWT de `auth.users`.
- `check_ins` crus: só o dono (`authenticated` + `user_id = auth.uid()`). Presença pública só via `who_is_here`.
