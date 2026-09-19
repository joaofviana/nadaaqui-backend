# Autenticação NadaAqui

## Stack

- **Provedor**: Supabase GoTrue (PostgREST Auth)
- **Projeto Live**: `hanqanaaimzthlqtrmks` (sa-east-1)
- **URL Base**: `https://hanqanaaimzthlqtrmks.supabase.co`
- **Auth Endpoint**: `{SUPABASE_URL}/auth/v1`

## Flow de Signup

1. **App chama**: `POST /auth/v1/signup`
   ```json
   {
     "email": "user@example.com",
     "password": "password123",
     "data": {
       "display_name": "Nome do Usuário"
     }
   }
   ```
2. **GoTrue**: Cria usuário em `auth.users`
3. **Trigger**: `handle_new_user()` cria perfil em `public.profiles`
4. **Response**: 
   - Se email confirmation desativado: retorna session completa
   - Se email confirmation ativada: retorna session sem access_token (user precisa confirmar email)

## Flow de Login

1. **App chama**: `POST /auth/v1/token?grant_type=password`
   ```json
   {
     "email": "user@example.com",
     "password": "password123"
   }
   ```
2. **GoTrue**: Valida credenciais
3. **Response**: Session completa com access_token e refresh_token

## Flow de Logout

1. **App chama**: `POST /auth/v1/logout`
   - Headers: `Authorization: Bearer {access_token}`
2. **GoTrue**: Revoga tokens no servidor
3. **App**: Limpa session local (SharedPreferences)

## Flow de Recuperação de Senha

1. **App chama**: `POST /auth/v1/recover`
   ```json
   {
     "email": "user@example.com"
   }
   ```
2. **GoTrue**: Envia email de recuperação (se email existir)
3. **Nota**: Sempre retorna 200 para não vazar se email existe

## Perfil de Usuário

### Tabela `public.profiles`

```sql
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT NOT NULL,
  handle TEXT UNIQUE,
  avatar_url TEXT,
  bio TEXT,
  age INTEGER,
  meters_declared INTEGER,
  swimming_since TEXT,
  level swimming_level,
  styles swimming_style[],
  show_in_presence BOOLEAN DEFAULT true,
  privacy JSONB,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
```

### Trigger `handle_new_user()`

- **Evento**: `AFTER INSERT` em `auth.users`
- **Ação**: Cria perfil automaticamente
- **Prioridade de nome**:
  1. `raw_user_meta_data->>'display_name'`
  2. `raw_user_meta_data->>'name'`
  3. Parte do email antes do `@`
  4. `'Nadador'` (fallback)

## RPCs Relacionadas ao Perfil

- `get_my_profile()` - perfil próprio (authenticated)
- `get_public_profile(p_handle, p_user_id)` - perfil público (anon, authenticated)
- `update_my_profile(p_patch)` - editar perfil (authenticated)

## Headers Padrão

Todas as chamadas para Supabase exigem:

```http
apikey: {SUPABASE_ANON_KEY}
Authorization: Bearer {access_token|anon_key}
Content-Type: application/json
```

## Mobile Implementation

O app Flutter em `nadaaqui-mobile` implementa:

- **AuthApi**: Abstração para GoTrue e WireMock
- **SessionStore**: Persistência de session em SharedPreferences
- **DioClient**: Interceptor para headers de autenticação
- **LoginScreen**: UI para login/signup/recover

## Configuração de Email Confirmation

No dashboard Supabase:
- Authentication → Providers → Email
- **Confirm email**: ON/OFF
- **Secure email change**: ON/OFF

Se email confirmation estiver ON:
- Signup retorna session sem access_token
- Usuário precisa clicar no link de confirmação
- App deve mostrar mensagem para verificar email

## Error Handling

Erros comuns do GoTrue:

- `invalid_login_credentials`: Email ou senha incorretos
- `user_already_exists`: Email já cadastrado
- `weak_password`: Senha não atinge requisitos
- `email_not_confirmed`: Email não confirmado

O app traduz estas mensagens para PT-BR em `AuthApi._pt()`.
