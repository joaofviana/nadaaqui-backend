# Contrato canônico — RPCs (fonte da verdade do app live)

O OpenAPI em `openapi/nadaaqui-v1.yaml` descreve o mock `/v1` (WireMock).
O app em produção chama **PostgREST RPCs**. Se os dois divergirem, **a RPC + migration ganham**; depois atualize o YAML.

Base live: `{SUPABASE_URL}/rest/v1/rpc/{nome}`
Headers: `apikey`, `Authorization: Bearer {anon|access_token}`, `Content-Type: application/json`

## RPCs

Grants de EXECUTE (migrations `20260926140000_rpc_permissions_anon.sql` e `20260926140100_who_is_here_authenticated_only.sql`).
Coluna **Grants**: estado final (depois das duas). Coluna **Até a B**: diferença enquanto só a migration A estiver aplicada.

| Uso | Função | Grants | Até a B |
|---|---|---|---|
| Config | `get_remote_config()` | anon, authenticated | |
| Lista | `nearby_places(...)` | anon, authenticated | |
| Ficha | `get_place(p_place_id)` | anon, authenticated | |
| Check-in | `create_check_in(...)` | authenticated | |
| Checkout | `checkout_check_in(p_check_in_id)` | authenticated | |
| Encerrar nado | `finish_swim(p_check_in_id, p_meters, p_body)` | authenticated | |
| Presença | `who_is_here(p_place_id)` | authenticated | anon também |
| Feed | `list_feed(p_limit, p_offset)` | authenticated | |
| Post | `create_feed_post(p_body, p_kind, p_place_id, p_stars)` | authenticated | |
| Kudo | `toggle_kudo(p_post_id)` | authenticated | |
| Meus nados | `list_my_sessions(p_limit, p_offset)` | authenticated | |
| Ranking tanque | `place_board(p_place_id, p_limit)` | authenticated | anon também |
| Heat horário | `place_hourly_heat(p_place_id)` | authenticated | anon também |
| Expirar TTL | `expire_check_ins()` | **service_role** only (job pg_cron roda como postgres) | |
| Meu perfil | `get_my_profile()` | authenticated | |
| Perfil público | `get_public_profile(p_handle, p_user_id)` | authenticated | |
| Editar perfil | `update_my_profile(p_patch)` | authenticated | |
| Check-ins do perfil | `list_profile_public_check_ins(p_user_id, p_limit, p_offset)` | authenticated | |
| Perfil social | `get_user_profile(p_user_id)` | authenticated | |
| Stats | `get_user_stats(p_user_id)` | authenticated | |
| Seguir | `follow_user(p_follower_id, p_following_id)` | authenticated | |
| Deixar de seguir | `unfollow_user(p_follower_id, p_following_id)` | authenticated | |
| Segue? | `is_following(p_follower_id, p_following_id)` | authenticated | |
| Comentários | `list_comments(p_post_id)` | authenticated | |
| Comentar | `create_comment(p_post_id, p_text)` | authenticated | |
| Like comentário | `toggle_comment_like(p_comment_id)` | authenticated | |
| Notificações | `list_notifications(p_user_id)` | authenticated | |
| Ler notificação | `mark_notification_read(p_notification_id)` | authenticated | |
| Ler todas | `mark_all_notifications_read()` | authenticated | |
| Salvar treino | `save_workout_plan(p_name, p_pool_length, p_focus, p_blocks, p_plan_id)` | authenticated | |
| Meus treinos | `list_my_workouts(p_limit, p_offset)` | authenticated | |
| Ver treino | `get_workout_plan(p_plan_id)` | authenticated | |
| Apagar treino | `delete_workout_plan(p_plan_id)` | authenticated | |
| Iniciar treino | `start_workout(...)` | authenticated | |

Funções internas (ninguém do app executa — nem PUBLIC, nem anon, nem authenticated):
triggers `handle_new_user`, `set_updated_at`, `sync_presence_visibility`, `protect_curator_flag`,
`increment_posts_count`, `protect_profile_counters` e helpers `_workout_plan_json`, `profile_stats`.

**RPC nova:** funções criadas pelo `postgres` nascem **sem** EXECUTE para PUBLIC e anon
(default privileges). Na migration da RPC, dê `grant execute ... to authenticated`
(e `to anon` só se for liberada para visitante).

### `get_user_stats` e privacidade

Devolve `sessions`, `places`, `streak_days`, `posts`, `minutes`, `meters`.
Para **outro usuário**, se `profiles.privacy_show_meters = false`, as chaves `minutes` e `meters`
**não vêm** no JSON (`meters` é calculado dos minutos). O dono sempre recebe tudo.
`p_user_id` null → `VALIDATION_ERROR`; usuário inexistente → `null`.

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

Exceções Postgres `P0001` (o app lê a mensagem): `UNAUTHORIZED`, `FORBIDDEN`, `NOT_FOUND`, `VALIDATION_ERROR`.

- `UNAUTHORIZED`: sem usuário logado.
- `FORBIDDEN`: logado, mas tentando agir em nome de outro usuário (ex.: `list_notifications(p_user_id)` de outro, `follow_user`/`unfollow_user` com `p_follower_id` de outro).
- `VALIDATION_ERROR`: parâmetro inválido (ex.: `follow_user` com `p_following_id` null ou inexistente, `get_user_stats(null)`).

Sem EXECUTE na função (ex.: anon chamando RPC só de authenticated) o PostgREST responde erro `42501` (permission denied) — isso não é do contrato, é do banco.

## Auth

Ver `docs/auth.md` para fluxos completos de signup/login/logout/recover.

- Guest (`anon`): só `get_remote_config`, `nearby_places` e `get_place` (e, até a migration `20260926140100`, também `who_is_here`, `place_board` e `place_hourly_heat`). Feed, perfil e o resto exigem JWT.
- Check-in / post / kudo / finish_swim exigem JWT.
- Signup cria `public.profiles` via trigger `handle_new_user`.
- Logout: chamar `POST /auth/v1/logout` diretamente (não é RPC).
