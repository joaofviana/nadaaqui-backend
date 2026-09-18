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
5. `20260917230000_profiles_swimmer.sql`
6. `20260918001000_fix_nearby_places.sql`
7. `20260918040000_expire_cron.sql` — pg_cron + expire no write

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

## Cron TTL — ligar no projeto live

`expire_check_ins()` já existe. **Fonte da verdade = job no banco.**

### 1. Tentar via Dashboard (Pro / pg_cron)

Database → Extensions → ligar `pg_cron` se aparecer. Depois SQL editor (role postgres):

```sql
select cron.schedule(
  'expire-check-ins',
  '*/10 * * * *',
  $$select public.expire_check_ins()$$
);

-- conferir
select jobid, jobname, schedule, command from cron.job;
```

A migration `20260918040000_expire_cron.sql` tenta o mesmo; se o plano **Free** não tiver `pg_cron`, ela só emite NOTICE e segue.

### 2. Fallback Free (sem cron)

- Edge Function scheduled (Dashboard → Edge Functions → cron) chamando `expire_check_ins` com **service_role**.
- **e/ou** o app trata `expires_at` na UI + botão “atualizar presença”.
- `who_is_here` já filtra `expires_at > now()`.
- `create_check_in` agora chama `expire_stale_for_user(auth.uid())` antes do unique index — write não fica preso num TTL morto.

O job no banco continua a fonte da verdade quando disponível.

### 3. Smoke (SQL editor, uma vez)

```sql
-- inserir ativo já expirado (postgres)
insert into public.check_ins (
  user_id, place_id, lat, lng, distance_meters,
  expires_at, status
) values (
  (select id from public.profiles limit 1),
  '11111111-1111-1111-1111-111111111111',
  -23.5505, -46.6333, 10,
  now() - interval '1 minute',
  'active'
)
returning id, status, expires_at;

select public.expire_check_ins();

-- esperado: status = ended
select id, status, ended_at from public.check_ins
where expires_at < now()
order by started_at desc
limit 5;
```

`expire_check_ins` é **service_role** (e postgres no SQL editor). Anon/authenticated não executam.

## Seed QA
Mesmos UUIDs do mock. GPS teste: `-23.5505, -46.6333`.

## Seed Ipiranga
```bash
psql "$DATABASE_URL" -f supabase/seed/seed_sao_paulo.sql
psql "$DATABASE_URL" -f supabase/seed/seed_ipiranga_piscinas.sql
```
Ver `docs/seed-ipiranga-notas.md` (Clube Ipiranga pendente; Sesc fechado p/ manutenção).
