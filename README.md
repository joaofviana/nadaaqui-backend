# nadaaqui-backend

Backend do MVP **NadaAqui** (rede social de locais para nadar — BR).

## Stack
- **Supabase** (Postgres + PostGIS + Auth + RLS + Realtime)
- Cidade piloto: **São Paulo** (`city_slug = sao-paulo`)
- Check-in: raio **150 m**, TTL **3 h** — vêm de `app_config` / RPC `get_remote_config()` (nunca hardcodar no app)

## Source of truth

O app **live** fala **RPC PostgREST**, não `/v1/places`.

| Camada | Onde | Papel |
|---|---|---|
| **RPC + SQL** | [`supabase/migrations/`](supabase/migrations/) | **Ganha** se divergir |
| **Contrato RPC** | [`docs/contrato-rpc.md`](docs/contrato-rpc.md) | Lista canônica das 6 RPCs + erros JSON |
| OpenAPI REST | [`openapi/nadaaqui-v1.yaml`](openapi/nadaaqui-v1.yaml) | Mock WireMock `/v1` apenas |
| Seed | [`supabase/seed/`](supabase/seed/) | SP QA + Ipiranga |

## Layout
```
openapi/          REST /v1 (WireMock) — não é o caminho feliz do app
supabase/         Migrations, seed SP, README de apply
mock/             WireMock + Mockoon (fallback de dev; este repo)
docs/             Contrato RPC, refinamento, seeds
```

## Quick start (Supabase — caminho feliz)

Ver [`supabase/README.md`](supabase/README.md) e [`docs/contrato-rpc.md`](docs/contrato-rpc.md).

O mobile injeta:

```
--dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co
--dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

## Quick start (mock — fallback de dev)

O WireMock mora **aqui**, não no repo mobile.

```bash
docker run --rm -p 8080:8080 \
  -v "$PWD/mock/wiremock:/home/wiremock" \
  wiremock/wiremock:3.9.1
```

Base URL: `http://localhost:8080/v1` (emulador Android: `http://10.0.2.2:8080/v1`).

## Docs
- [Contrato RPC (app live)](docs/contrato-rpc.md)
- [Supabase apply](supabase/README.md)
- [Refinamento técnico](docs/refinamento-tecnico-backend.md)
- [Estimativas por HU](docs/estimativas-backend-hu.md)
- [Mock QA](mock/README.md)
