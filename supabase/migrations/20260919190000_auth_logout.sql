-- Auth: logout via Supabase GoTrue (não RPC)
-- Documentação: o app chama diretamente POST /auth/v1/logout
-- Esta migration documenta o comportamento esperado

comment on function public.handle_new_user() is
  'Cria public.profiles no signup GoTrue. display_name vem de user_metadata.';

-- Nota: Logout não precisa de RPC. O app chama Supabase GoTrue diretamente:
-- POST {SUPABASE_URL}/auth/v1/logout
-- Headers: apikey, Authorization: Bearer {access_token}
-- GoTrue revoga o access_token e refresh_token no servidor
