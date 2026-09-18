-- F2: endurecer RLS + SECURITY DEFINER
-- Não edita 20260917220200_rls.sql (já aplicado no projeto live).

-- 1) check_ins: dono vê as próprias linhas; anon NÃO lê check-ins crus.
--    Presença pública continua só via who_is_here (SECURITY DEFINER).
drop policy if exists check_ins_select on public.check_ins;

create policy check_ins_select_own on public.check_ins
  for select to authenticated
  using (user_id = auth.uid());

-- 2) expire_check_ins: confirmar service_role only (revoga public/anon/auth).
revoke all on function public.expire_check_ins() from public;
revoke execute on function public.expire_check_ins() from anon, authenticated;
grant execute on function public.expire_check_ins() to service_role;

-- 3) Bloquear escalada de is_curator no UPDATE direto (profiles_update_own).
drop policy if exists profiles_update_own on public.profiles;

create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (
    id = auth.uid()
    and is_curator is not distinct from (
      select p.is_curator from public.profiles p where p.id = auth.uid()
    )
  );

-- Cinto: trigger ignora/recusa mudança de is_curator fora de service_role.
create or replace function public.protect_is_curator()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.is_curator is distinct from old.is_curator
     and coalesce(auth.role(), '') not in ('service_role') then
    raise exception 'FORBIDDEN'
      using errcode = '42501',
            message = 'is_curator não pode ser alterado pelo próprio usuário';
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_protect_is_curator on public.profiles;
create trigger profiles_protect_is_curator
  before update of is_curator on public.profiles
  for each row execute function public.protect_is_curator();

-- 4) who_is_here: sem email (já era o caso). Recria com grants explícitos
--    e search_path travado. Mantém userId no MVP.
create or replace function public.who_is_here(p_place_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_visible int;
  v_hidden int;
  v_people jsonb;
begin
  if not exists (select 1 from public.places where id = p_place_id and is_published) then
    return null;
  end if;

  select
    count(*) filter (where visible_in_presence),
    count(*) filter (where not visible_in_presence)
  into v_visible, v_hidden
  from public.check_ins
  where place_id = p_place_id
    and status = 'active'
    and expires_at > now();

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'userId', c.user_id,
      'displayName', p.display_name,
      'avatarUrl', p.avatar_url,
      'checkedInAt', c.started_at
    )
    order by c.started_at desc
  ), '[]'::jsonb)
  into v_people
  from public.check_ins c
  join public.profiles p on p.id = c.user_id
  where c.place_id = p_place_id
    and c.status = 'active'
    and c.expires_at > now()
    and c.visible_in_presence = true;

  return jsonb_build_object(
    'placeId', p_place_id,
    'visibleCount', coalesce(v_visible, 0),
    'hiddenCount', coalesce(v_hidden, 0),
    'people', v_people
  );
end;
$$;

revoke all on function public.who_is_here(uuid) from public;
grant execute on function public.who_is_here(uuid) to anon, authenticated;

-- create_check_in já recusa auth.uid() is null; reforça search_path (já tinha).
-- grants: authenticated only (já era). Reafirma:
revoke all on function public.create_check_in(
  uuid, double precision, double precision, double precision, timestamptz, boolean
) from public;
grant execute on function public.create_check_in(
  uuid, double precision, double precision, double precision, timestamptz, boolean
) to authenticated;
