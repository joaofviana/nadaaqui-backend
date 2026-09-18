# Auth — e-mail e senha

Live usa **Supabase Auth (GoTrue)**. O mock WireMock espelha o contrato que o app
usa quando `SUPABASE_URL` não está no build.

## Live (GoTrue)

Base: `{SUPABASE_URL}/auth/v1`
Headers: `apikey: {ANON}`, `Authorization: Bearer {ANON}`

| Ação | Método | Path | Body |
|---|---|---|---|
| Entrar | POST | `/token?grant_type=password` | `{ email, password }` |
| Criar conta | POST | `/signup` | `{ email, password, data: { display_name } }` |
| Recuperar senha | POST | `/recover` | `{ email }` |

Signup grava `display_name` em `raw_user_meta_data`.
O trigger `on_auth_user_created` cria `public.profiles` com esse nome.

`/recover` responde **200** mesmo se o e-mail não existir (não vaza cadastro).
O e-mail de reset é o template padrão do projeto Supabase.

Check-in e mutações de perfil exigem `Authorization: Bearer {access_token}`.
Guest (anon) continua lendo mapa, ficha e presença.

## Mock WireMock (`/v1`)

| Ação | Path | Status |
|---|---|---|
| Entrar | `POST /v1/auth/login` | 200 `auth-session.json` |
| Criar conta | `POST /v1/auth/signup` | 200 `auth-session.json` |
| Recuperar | `POST /v1/auth/recover` | 200 `{ ok: true }` |

O mock não valida senha. Serve só para exercitar a UI sem projeto live.
