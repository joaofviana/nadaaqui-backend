-- NadaAqui pós-S1 — Perfil nadador (HU-14/15/16)

create type public.swimming_level as enum ('beginner', 'intermediate', 'advanced');
create type public.swimming_style as enum ('crawl', 'backstroke', 'breaststroke', 'butterfly');

alter table public.profiles
  add column if not exists handle text,
  add column if not exists bio text,
  add column if not exists age int check (age is null or (age between 1 and 120)),
  add column if not exists meters_declared int check (meters_declared is null or meters_declared >= 0),
  add column if not exists swimming_since text,
  add column if not exists level public.swimming_level,
  add column if not exists styles public.swimming_style[] not null default '{}',
  add column if not exists privacy_show_age boolean not null default true,
  add column if not exists privacy_show_meters boolean not null default true,
  add column if not exists privacy_show_level_styles boolean not null default true,
  add column if not exists privacy_show_swimming_since boolean not null default true;

-- handle único (case-insensitive); null permitido até onboarding
create unique index if not exists profiles_handle_unique_ci
  on public.profiles (lower(handle))
  where handle is not null;

comment on column public.profiles.meters_declared is 'Metros declarados pelo usuário (não medidos). NULL = não informado (≠ 0).';
comment on column public.profiles.swimming_since is 'Texto declarado: "desde 2019" ou "há 5 anos".';

-- Contagens derivadas
create or replace function public.profile_stats(p_user_id uuid)
returns table (check_ins_count bigint, places_count bigint)
language sql
stable
security invoker
set search_path = public
as $$
  select
    count(*)::bigint as check_ins_count,
    count(distinct place_id)::bigint as places_count
  from public.check_ins
  where user_id = p_user_id;
$$;

grant execute on function public.profile_stats(uuid) to anon, authenticated;

-- Perfil completo (dono)
create or replace function public.get_my_profile()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  r public.profiles%rowtype;
  s record;
begin
  if v_uid is null then
    raise exception 'UNAUTHORIZED' using errcode = 'P0001';
  end if;
  select * into r from public.profiles where id = v_uid;
  if not found then return null; end if;
  select * into s from public.profile_stats(v_uid);
  return jsonb_build_object(
    'id', r.id,
    'displayName', r.display_name,
    'handle', r.handle,
    'avatarUrl', r.avatar_url,
    'bio', r.bio,
    'age', r.age,
    'metersDeclared', r.meters_declared,
    'swimmingSince', r.swimming_since,
    'level', r.level,
    'styles', to_jsonb(r.styles),
    'showInPresence', r.show_in_presence,
    'privacy', jsonb_build_object(
      'showAge', r.privacy_show_age,
      'showMeters', r.privacy_show_meters,
      'showLevelStyles', r.privacy_show_level_styles,
      'showSwimmingSince', r.privacy_show_swimming_since
    ),
    'stats', jsonb_build_object(
      'checkInsCount', coalesce(s.check_ins_count, 0),
      'placesCount', coalesce(s.places_count, 0)
    ),
    'isSelf', true
  );
end;
$$;

grant execute on function public.get_my_profile() to authenticated;

-- Perfil público (outro) — omite campos com privacy off / vazios
create or replace function public.get_public_profile(p_handle text default null, p_user_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  r public.profiles%rowtype;
  s record;
  v_self boolean;
  out jsonb;
begin
  if p_user_id is not null then
    select * into r from public.profiles where id = p_user_id;
  elsif p_handle is not null then
    select * into r from public.profiles where lower(handle) = lower(p_handle);
  else
    return null;
  end if;
  if not found then return null; end if;

  v_self := (auth.uid() is not null and auth.uid() = r.id);
  if v_self then
    return public.get_my_profile();
  end if;

  select * into s from public.profile_stats(r.id);

  out := jsonb_build_object(
    'id', r.id,
    'displayName', r.display_name,
    'handle', r.handle,
    'avatarUrl', r.avatar_url,
    'bio', r.bio,
    'showInPresence', r.show_in_presence,
    'stats', jsonb_build_object(
      'checkInsCount', coalesce(s.check_ins_count, 0),
      'placesCount', coalesce(s.places_count, 0)
    ),
    'isSelf', false
  );

  if r.privacy_show_age and r.age is not null then
    out := out || jsonb_build_object('age', r.age);
  end if;
  if r.privacy_show_meters and r.meters_declared is not null then
    out := out || jsonb_build_object('metersDeclared', r.meters_declared);
  end if;
  if r.privacy_show_swimming_since and r.swimming_since is not null then
    out := out || jsonb_build_object('swimmingSince', r.swimming_since);
  end if;
  if r.privacy_show_level_styles then
    if r.level is not null then
      out := out || jsonb_build_object('level', r.level);
    end if;
    if cardinality(r.styles) > 0 then
      out := out || jsonb_build_object('styles', to_jsonb(r.styles));
    end if;
  end if;

  -- never expose privacy toggles or private fields to others
  return out;
end;
$$;

grant execute on function public.get_public_profile(text, uuid) to anon, authenticated;

-- Update profile (dono)
create or replace function public.update_my_profile(p_patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_handle text;
begin
  if v_uid is null then
    raise exception 'UNAUTHORIZED' using errcode = 'P0001';
  end if;

  if p_patch ? 'handle' then
    v_handle := nullif(trim(p_patch->>'handle'), '');
    if v_handle is not null then
      if exists (
        select 1 from public.profiles
        where lower(handle) = lower(v_handle) and id <> v_uid
      ) then
        return jsonb_build_object(
          'error', jsonb_build_object(
            'code', 'CONFLICT',
            'message', 'Esse @handle já está em uso.',
            'details', jsonb_build_object('field', 'handle')
          )
        );
      end if;
    end if;
  end if;

  update public.profiles set
    display_name = case when p_patch ? 'displayName' then coalesce(nullif(trim(p_patch->>'displayName'), ''), display_name) else display_name end,
    handle = case when p_patch ? 'handle' then nullif(trim(p_patch->>'handle'), '') else handle end,
    avatar_url = case when p_patch ? 'avatarUrl' then nullif(p_patch->>'avatarUrl', '') else avatar_url end,
    bio = case when p_patch ? 'bio' then nullif(p_patch->>'bio', '') else bio end,
    age = case when p_patch ? 'age' then (p_patch->>'age')::int else age end,
    meters_declared = case
      when p_patch ? 'metersDeclared' and (p_patch->'metersDeclared') = 'null'::jsonb then null
      when p_patch ? 'metersDeclared' then (p_patch->>'metersDeclared')::int
      else meters_declared
    end,
    swimming_since = case when p_patch ? 'swimmingSince' then nullif(p_patch->>'swimmingSince', '') else swimming_since end,
    level = case
      when p_patch ? 'level' and (p_patch->'level') = 'null'::jsonb then null
      when p_patch ? 'level' then (p_patch->>'level')::public.swimming_level
      else level
    end,
    styles = case
      when p_patch ? 'styles' then coalesce(
        (select array_agg(x::public.swimming_style) from jsonb_array_elements_text(p_patch->'styles') t(x)),
        '{}'
      )
      else styles
    end,
    show_in_presence = case when p_patch ? 'showInPresence' then (p_patch->>'showInPresence')::boolean else show_in_presence end,
    privacy_show_age = case when p_patch #>> '{privacy,showAge}' is not null then (p_patch#>>'{privacy,showAge}')::boolean else privacy_show_age end,
    privacy_show_meters = case when p_patch #>> '{privacy,showMeters}' is not null then (p_patch#>>'{privacy,showMeters}')::boolean else privacy_show_meters end,
    privacy_show_level_styles = case when p_patch #>> '{privacy,showLevelStyles}' is not null then (p_patch#>>'{privacy,showLevelStyles}')::boolean else privacy_show_level_styles end,
    privacy_show_swimming_since = case when p_patch #>> '{privacy,showSwimmingSince}' is not null then (p_patch#>>'{privacy,showSwimmingSince}')::boolean else privacy_show_swimming_since end,
    updated_at = now()
  where id = v_uid;

  return public.get_my_profile();
end;
$$;

grant execute on function public.update_my_profile(jsonb) to authenticated;

-- Check-ins públicos de um perfil (lista no perfil, não feed)
create or replace function public.list_profile_public_check_ins(
  p_user_id uuid,
  p_limit int default 20,
  p_offset int default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_limit is null or p_limit < 1 then p_limit := 20; end if;
  if p_limit > 50 then p_limit := 50; end if;
  if p_offset is null or p_offset < 0 then p_offset := 0; end if;

  return coalesce((
    select jsonb_agg(row_to_json(t)::jsonb)
    from (
      select
        c.id,
        c.place_id as "placeId",
        pl.name as "placeName",
        c.started_at as "startedAt",
        c.status
      from public.check_ins c
      join public.places pl on pl.id = c.place_id
      where c.user_id = p_user_id
        and c.visible_in_presence = true
      order by c.started_at desc
      limit p_limit offset p_offset
    ) t
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.list_profile_public_check_ins(uuid, int, int) to anon, authenticated;
