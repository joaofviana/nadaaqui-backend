-- Signup: perfil a partir de display_name no metadata; idempotente.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
begin
  v_name := coalesce(
    nullif(trim(new.raw_user_meta_data->>'display_name'), ''),
    nullif(trim(new.raw_user_meta_data->>'name'), ''),
    split_part(coalesce(new.email, ''), '@', 1),
    'Nadador'
  );

  insert into public.profiles (id, display_name)
  values (new.id, v_name)
  on conflict (id) do update
    set display_name = excluded.display_name,
        updated_at = now()
    where public.profiles.display_name is distinct from excluded.display_name;

  return new;
end;
$$;

comment on function public.handle_new_user() is
  'Cria public.profiles no signup GoTrue. display_name vem de user_metadata.';
