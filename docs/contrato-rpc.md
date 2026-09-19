# Contrato canônico — RPCs (fonte da verdade do app live)

O OpenAPI em `openapi/nadaaqui-v1.yaml` descreve o mock `/v1` (WireMock).
O app em produção chama **PostgREST RPCs**. Se os dois divergirem, **a RPC + migration ganham**; depois atualize o YAML.

Base live: `{SUPABASE_URL}/rest/v1/rpc/{nome}`
Headers: `apikey`, `Authorization: Bearer {anon|access_token}`, `Content-Type: application/json`

## RPCs

| Uso | Função | Grants |
|---|---|---|
| Config | `get_remote_config()` | anon, authenticated |
| Lista | `nearby_places(...)` | anon, authenticated |
| Ficha | `get_place(p_place_id)` | anon, authenticated |
| Check-in | `create_check_in(...)` | authenticated |
| Checkout | `checkout_check_in(p_check_in_id)` | authenticated |
| Encerrar nado | `finish_swim(p_check_in_id, p_meters, p_body)` | authenticated |
| Presença | `who_is_here(p_place_id)` | anon, authenticated |
| Feed | `list_feed(p_limit, p_offset)` | anon, authenticated |
| Post | `create_feed_post(p_body, p_kind, p_place_id, p_stars)` | authenticated |
| Kudo | `toggle_kudo(p_post_id)` | authenticated |
| Meus nados | `list_my_sessions(p_limit, p_offset)` | authenticated |
| Ranking tanque | `place_board(p_place_id, p_limit)` | anon, authenticated |
| Heat horário | `place_hourly_heat(p_place_id)` | anon, authenticated |
| Expirar TTL | `expire_check_ins()` | **service_role** only |
| Meu perfil | `get_my_profile()` | authenticated |
| Perfil público | `get_public_profile(p_handle, p_user_id)` | anon, authenticated |
| Editar perfil | `update_my_profile(p_patch)` | authenticated |

`nearby_places` devolve linhas **snake_case**. O client mapeia para camelCase.
`get_place` devolve JSON camelCase com `distanceMeters: null` — distância é calculada no app.

## Encerrar nado

`finish_swim` faz checkout do check-in ativo, grava `swim_sessions` e publica um post `kind=session` no feed.

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

Exceções Postgres `P0001`: `UNAUTHORIZED`, `NOT_FOUND`, `VALIDATION_ERROR`.

## Auth

Ver `docs/auth.md`.

- Guest (`anon`): lê places publicados + `who_is_here` + config + feed + ranking.
- Check-in / post / kudo / finish_swim exigem JWT.
- Signup cria `public.profiles` via trigger `handle_new_user`.
