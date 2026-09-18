# NadaAqui — Supabase (Sprint 1)

## Decisões travadas
- Stack: **Supabase**
- Cidade piloto: **São Paulo** (`city_slug = sao-paulo`)
- Feed: só cidade piloto
- Raio check-in: **150 m** · TTL: **3 h** (via `app_config`)

## Ordem de apply
```bash
# No projeto Supabase linkado:
supabase db reset   # ou apply migrations em ordem
psql "$DATABASE_URL" -f supabase/seed/seed_sao_paulo.sql
```

Migrations:
1. `20260917220000_extensions.sql` — postgis, trgm, pgcrypto
2. `20260917220100_schema.sql` — tables + trigger profile
3. `20260917220200_rls.sql`
4. `20260917220300_rpcs.sql`

## RPCs ↔ OpenAPI
| OpenAPI | RPC |
|---|---|
| `GET /v1/config` | `get_remote_config()` |
| `GET /v1/places` | `nearby_places(...)` |
| `GET /v1/places/{id}` | `get_place(id)` |
| `POST /v1/check-ins` | `create_check_in(...)` |
| `POST /v1/check-ins/{id}/checkout` | `checkout_check_in(id)` |
| `GET /v1/places/{id}/presence` | `who_is_here(id)` |

Auth: Supabase Auth (e-mail/senha) + `profiles`. Guest = `anon` só SELECT places + presence.

## Cron TTL
Agendar `select public.expire_check_ins();` a cada 5–10 min (pg_cron ou Edge scheduled).

## Seed QA
Mesmos UUIDs do mock. GPS teste: `-23.5505, -46.6333`.
