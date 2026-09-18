# Testes SQL — domínio check-in / nearby (F4)

Reproduz os 6 casos do plano. **Não** precisa de CLI besides `psql`.

## Pré-requisito

Migrations + seed no projeto live:

```bash
psql "$DATABASE_URL" -f supabase/seed/seed_sao_paulo.sql
psql "$DATABASE_URL" -f supabase/seed/seed_ipiranga_piscinas.sql
```

## Rodar

SQL editor (postgres) — cola `rpc_check_in.sql`  
**ou**

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/rpc_check_in.sql
```

O script abre `BEGIN` e termina em `ROLLBACK` — não deixa lixo (exceto se o insert em `auth.users` não entrar no mesmo snapshot; o tester `f4-tester@nadaaqui.app` pode ficar; é conta de teste).

## Casos

| # | Caso |
|---|---|
| 1 | `nearby_places` em Ipiranga retorna place Ipiranga primeiro |
| 2 | `create_check_in` OUT_OF_RANGE |
| 3 | `create_check_in` LOCATION_STALE (`captured_at` velho) |
| 4 | mesmo place = idempotente (mesmo id) |
| 5 | outro place + `end_previous=true` encerra o anterior |
| 6 | outro place + `end_previous=false` → ALREADY_CHECKED_IN |
| + | unique index: não ficam 2 `active` no mesmo user |
| + | `expire_check_ins` marca `ended` |

Falha = `ERROR` / exception. Sucesso = `NOTICE F4 ALL PASS`.
