# NadaAqui API Mock (Sprint 1)

## Artefatos
- OpenAPI: `../openapi/nadaaqui-v1.yaml`
- WireMock: `./wiremock/` (raiz do WireMock = esta pasta `wiremock`)
- Mockoon: `./mockoon/nadaaqui.mockoon.json`

## Posição GPS de teste (QA)
- Lat/lng do usuário mock: **-23.550500, -46.633300**
- Place **IN** (`11111111-1111-1111-1111-111111111111`): ~80 m → check-in **201**
- Place **OUT** (`22222222-2222-2222-2222-222222222222`): ~450 m → **400 OUT_OF_RANGE**

## 3 filtros
1. `GET /v1/places?priceType=free` → só OUT
2. `GET /v1/places?priceType=paid` → só IN
3. `GET /v1/places?totalPass=yes` → só IN

## Cenários de erro via header
- `X-Mock-Scenario: LOCATION_STALE` no POST `/v1/check-ins`
- `X-Mock-Scenario: ALREADY_CHECKED_IN` no POST `/v1/check-ins`

## Subir WireMock
```bash
docker run --rm -p 8080:8080 \
  -v "$PWD/wiremock:/home/wiremock" \
  wiremock/wiremock:3.9.1
```

Base URL app: `http://localhost:8080/v1`

## Prioridade WireMock (check-in)
- `X-Mock-Scenario` stubs: priority **1**
- `OUT_OF_RANGE` (place OUT): priority **2**
- Happy path (place IN): priority **10** + header `X-Mock-Scenario` **absent**
