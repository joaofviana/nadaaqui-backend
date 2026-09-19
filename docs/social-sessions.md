# Social + sessão (Strava-lite)

Migration: `supabase/migrations/20260919180000_social_sessions.sql`

Aplicar no projeto Supabase (SQL editor ou `supabase db push`).

## Fluxo app

1. `create_check_in` — igual Sprint 1.
2. `finish_swim(p_check_in_id, p_meters, p_body)` — checkout + `swim_sessions` + post `session`.
3. `list_feed` — timeline.
4. `toggle_kudo` — like.
5. `create_feed_post` — texto / check-in / review (recalcula `rating_avg` do place).
6. `list_my_sessions` — perfil.
7. `place_board` / `place_hourly_heat` — ficha do tanque.

Tudo camelCase no JSON das RPCs novas.
