-- F2: anon não lê check_ins crus; curator flag não é self-service; expire só service_role.

drop policy if exists check_ins_select on public.check_ins;

create policy check_ins_select_own on public.check_ins
  for select to authenticated
  using (user_id = auth.uid());

create or replace function public.protect_curator_flag()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.is_curator is distinct from old.is_curator
     and coalesce(auth.role(), '') <> 'service_role' then
    new.is_curator := old.is_curator;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_protect_curator on public.profiles;
create trigger profiles_protect_curator
  before update on public.profiles
  for each row execute function public.protect_curator_flag();

revoke execute on function public.expire_check_ins() from public;
revoke execute on function public.expire_check_ins() from anon, authenticated;
grant execute on function public.expire_check_ins() to service_role;
