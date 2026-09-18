# Perfil nadador — modelo Backend (HU-14/15/16)

**Status:** migration + OpenAPI pós-S1 (não bloqueia Sprint 1).  
**Fonte produto:** `/workspace/nadaaqui/docs/hu-perfil-nadador.md`

## Colunas em `profiles`
| Campo | Tipo | Notas |
|---|---|---|
| handle | text unique CI | editável; CONFLICT se duplicado |
| bio | text | opcional |
| age | int 1–120 | idade, não DOB |
| meters_declared | int ≥0 nullable | **null = não informado** (≠ 0) |
| swimming_since | text | “desde 2019” / “há 5 anos” |
| level | enum beginner\|intermediate\|advanced | |
| styles | swimming_style[] | crawl, backstroke, breaststroke, butterfly |
| privacy_show_* | bool default true | age, meters, level_styles, swimming_since |
| show_in_presence | bool | já existia (HU-07) |

## RPCs / OpenAPI
- `GET /v1/me/profile` → `get_my_profile`
- `PATCH /v1/me/profile` → `update_my_profile` (handle CONFLICT)
- `GET /v1/profiles/{handle}` → `get_public_profile` (omite privados)
- `GET /v1/profiles/{userId}/check-ins` → lista no perfil

## Migration
`supabase/migrations/20260917230000_profiles_swimmer.sql`
