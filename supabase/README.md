# NadaAqui — Supabase (Sprint 1)

## Decisões travadas
- Stack: **Supabase**
- Cidade piloto: **São Paulo** (`city_slug = sao-paulo`)
- Feed: só cidade piloto
- Raio check-in: **150 m** · TTL: **3 h** (via `app_config` — nunca hardcodar no app)

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
5. `20260917230000_profiles_swimmer.sql`
6. `20260918001000_fix_nearby_places.sql`
(+ harden RLS / cron nas PRs F2/F3)

## RPCs ↔ app live

Contrato canônico: [`docs/contrato-rpc.md`](../docs/contrato-rpc.md).

| Uso | RPC | Grants |
|---|---|---|
| Config | `get_remote_config()` | anon, authenticated |
| Lista | `nearby_places(...)` | anon, authenticated |
| Ficha | `get_place(id)` | anon, authenticated |
| Check-in | `create_check_in(...)` | authenticated |
| Checkout | `checkout_check_in(id)` | authenticated |
| Presença | `who_is_here(id)` | anon, authenticated |

Auth: Supabase Auth (e-mail/senha) + `profiles`. Guest = `anon` só SELECT places + presence via RPC.

O YAML `openapi/nadaaqui-v1.yaml` é o mock REST `/v1`. **Não** é o que o app live chama.

## Cron TTL
Ver a migration F3 / bloco em `docs/contrato-rpc.md`. SQL para colar no editor se `pg_cron` não estiver na migration:

```sql
select cron.schedule(
  'expire-check-ins',
  '*/10 * * * *',
  $$select public.expire_check_ins()$$
);
```

`expire_check_ins()` é `service_role` only.

## Seed QA
Mesmos UUIDs do mock. GPS teste WireMock: `-23.5505, -46.6333`.

## Seed Ipiranga
```bash
psql "$DATABASE_URL" -f supabase/seed/seed_sao_paulo.sql
psql "$DATABASE_URL" -f supabase/seed/seed_ipiranga_piscinas.sql
```
Ver `docs/seed-ipiranga-notas.md`.
