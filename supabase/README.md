# NadaAqui — Supabase (Sprint 1)

## Decisões travadas
- Stack: **Supabase**
- Cidade piloto: **São Paulo** (`city_slug = sao-paulo`)
- Feed: só cidade piloto
- Raio check-in: **150 m** · TTL: **3 h** (via `app_config`, nunca hardcodar no app)

## Ordem de apply
```bash
supabase db reset
psql "$DATABASE_URL" -f supabase/seed/seed_sao_paulo.sql
psql "$DATABASE_URL" -f supabase/seed/seed_ipiranga_piscinas.sql
```

Migrations (ordem do timestamp):
1. `20260917220000_extensions.sql`
2. `20260917220100_schema.sql`
3. `20260917220200_rls.sql`
4. `20260917220300_rpcs.sql`
5. `20260917230000_profiles_swimmer.sql`
6. `20260918001000_fix_nearby_places.sql`
7. `20260918020000_harden_rls.sql` — F2: anon não lê check_ins; flag curator protegida
8. `20260918020100_expire_cron.sql` — F3: pg_cron a cada 10 min (no-op se a extensão não existir)

## RPCs ↔ app live
Ver [`docs/contrato-rpc.md`](../docs/contrato-rpc.md). OpenAPI `/v1` é só o mock.

Auth: Supabase Auth (e-mail/senha) + `profiles`. Guest = `anon` lê places + `who_is_here` + config.

## Cron TTL
No projeto hosted com `pg_cron`, a migration `20260918020100_expire_cron.sql` agenda:

```sql
select cron.schedule(
  'expire-check-ins',
  '*/10 * * * *',
  $$select public.expire_check_ins()$$
);
```

Se o plano não tiver cron: rode `select public.expire_check_ins();` no SQL editor (ou Edge scheduled). O app também respeita `expires_at` na UI.

Smoke manual da função:

```sql
update public.check_ins
set expires_at = now() - interval '1 minute'
where status = 'active'
limit 1;
select public.expire_check_ins();
```

## Testes de domínio
Checklist em [`supabase/tests/check_in.sql`](tests/check_in.sql).

## Seed QA
Mesmos UUIDs do mock. GPS WireMock: `-23.5505, -46.6333`.
Live: use um place real do seed Ipiranga e anote a distância.

```bash
psql "$DATABASE_URL" -f supabase/seed/seed_sao_paulo.sql
psql "$DATABASE_URL" -f supabase/seed/seed_ipiranga_piscinas.sql
```
