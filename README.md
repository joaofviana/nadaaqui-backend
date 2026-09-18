# nadaaqui-backend

Backend do MVP **NadaAqui** (rede social de locais para nadar — BR).

## Stack
- **Supabase** (Postgres + PostGIS + Auth + RLS + Realtime)
- Cidade piloto: **São Paulo** (`city_slug = sao-paulo`)
- Check-in: raio **150 m**, TTL **3 h** (via `app_config` / `GET /v1/config`)

## Source of truth
- **OpenAPI:** [`openapi/nadaaqui-v1.yaml`](openapi/nadaaqui-v1.yaml) — o front só consome cópia/docs.
- **SQL:** [`supabase/migrations/`](supabase/migrations/) + [`supabase/seed/`](supabase/seed/)

## Layout
```
openapi/          Contratos REST (Sprint 1+)
supabase/         Migrations, seed SP, README de apply
mock/             WireMock + Mockoon (sem .jar/.runtime)
docs/             Refinamento técnico e estimativas
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
- [Refinamento técnico](docs/refinamento-tecnico-backend.md)
- [Estimativas por HU](docs/estimativas-backend-hu.md)
- [Mock QA](mock/README.md)

## Time
Repo do agente **Backend**. Contrato OpenAPI é a fonte da verdade; mudanças de API entram aqui primeiro.
