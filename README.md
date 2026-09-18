# nadaaqui-backend

Backend do MVP **NadaAqui** (rede social de locais para nadar — BR).

## Stack
- **Supabase** (Postgres + PostGIS + Auth + RLS + Realtime)
- Cidade piloto: **São Paulo** (`city_slug = sao-paulo`)
- Check-in: raio **150 m**, TTL **3 h** (via `app_config` / `get_remote_config()`)

## Source of truth
- **Live (app):** RPCs em [`docs/contrato-rpc.md`](docs/contrato-rpc.md) + SQL em [`supabase/migrations/`](supabase/migrations/)
- **Mock / contrato REST:** [`openapi/nadaaqui-v1.yaml`](openapi/nadaaqui-v1.yaml) — só WireMock. Se divergir da RPC, **a RPC ganha**.
- O mobile **não** deve manter cópia do YAML.

## Layout
```
openapi/          Contrato REST do mock
supabase/         Migrations, seed SP, testes SQL, README de apply
mock/             WireMock + Mockoon
docs/             Contrato RPC, refinamento, plano de gaps
```

## Quick start (mock)
```bash
docker run --rm -p 8080:8080 \
  -v "$PWD/mock/wiremock:/home/wiremock" \
  wiremock/wiremock:3.9.1
```
Base URL: `http://localhost:8080/v1`

## Quick start (Supabase)
Ver [`supabase/README.md`](supabase/README.md).

## Docs
- [Contrato RPC](docs/contrato-rpc.md)
- [Refinamento técnico](docs/refinamento-tecnico-backend.md)
- [Estimativas por HU](docs/estimativas-backend-hu.md)
- [Mock QA](mock/README.md)
