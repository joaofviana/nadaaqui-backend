-- F3: expirar check-in de verdade
-- Job no banco é a fonte da verdade. Se pg_cron não existir (Free),
-- o README documenta o SQL para colar no editor + fallback.

-- Encerra ativos cujo TTL já passou (o user autenticado só os próprios).
create or replace function public.expire_stale_for_user(p_uid uuid)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  n int;
begin
  if p_uid is null then
    return 0;
  end if;
  with u as (
    update public.check_ins
    set status = 'ended', ended_at = coalesce(ended_at, now())
    where user_id = p_uid
      and status = 'active'
      and expires_at < now()
    returning 1
  )
  select count(*) into n from u;
  return n;
end;
$$;

revoke all on function public.expire_stale_for_user(uuid) from public;
grant execute on function public.expire_stale_for_user(uuid) to authenticated;

-- create_check_in: limpa stale do próprio user ANTES do unique index / ALREADY_CHECKED_IN
create or replace function public.create_check_in(
  p_place_id uuid,
  p_lat double precision,
  p_lng double precision,
  p_accuracy_meters double precision,
  p_captured_at timestamptz,
  p_end_previous boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_cfg public.app_config%rowtype;
  v_place public.places%rowtype;
  v_origin geography;
  v_distance int;
  v_age_seconds int;
  v_profile public.profiles%rowtype;
  v_active public.check_ins%rowtype;
  v_ended_id uuid;
  v_new public.check_ins%rowtype;
begin
  if v_uid is null then
    raise exception 'UNAUTHORIZED' using errcode = 'P0001';
  end if;

  perform public.expire_stale_for_user(v_uid);

  select * into v_cfg from public.app_config where id = 1;
  select * into v_profile from public.profiles where id = v_uid;
  select * into v_place from public.places where id = p_place_id and is_published = true;
  if not found then
    raise exception 'NOT_FOUND' using errcode = 'P0001';
  end if;

  v_age_seconds := extract(epoch from (now() - p_captured_at))::int;
  if v_age_seconds > v_cfg.location_max_age_seconds or v_age_seconds < -30 then
    return jsonb_build_object(
      'error', jsonb_build_object(
        'code', 'LOCATION_STALE',
        'message', 'Sua localização está desatualizada. Atualize o GPS e tente de novo.',
        'details', jsonb_build_object('maxAgeSeconds', v_cfg.location_max_age_seconds)
      )
    );
  end if;

  v_origin := ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography;
  v_distance := ST_Distance(v_place.location, v_origin)::int;

  if v_distance > v_cfg.check_in_radius_meters then
    return jsonb_build_object(
      'error', jsonb_build_object(
        'code', 'OUT_OF_RANGE',
        'message', 'Você precisa estar mais perto do local para fazer check-in.',
        'details', jsonb_build_object(
          'distanceMeters', v_distance,
          'radiusMeters', v_cfg.check_in_radius_meters,
          'placeId', p_place_id
        )
      )
    );
  end if;

  select * into v_active
  from public.check_ins
  where user_id = v_uid and status = 'active'
  limit 1;

  if found then
    if v_active.place_id = p_place_id then
      return jsonb_build_object(
        'checkIn', jsonb_build_object(
          'id', v_active.id,
          'placeId', v_active.place_id,
          'userId', v_active.user_id,
          'status', v_active.status,
          'startedAt', v_active.started_at,
          'expiresAt', v_active.expires_at,
          'endedAt', v_active.ended_at,
          'distanceMeters', v_active.distance_meters,
          'visibleInPresence', v_active.visible_in_presence
        ),
        'endedPreviousCheckInId', null
      );
    end if;

    if not coalesce(p_end_previous, true) then
      return jsonb_build_object(
        'error', jsonb_build_object(
          'code', 'ALREADY_CHECKED_IN',
          'message', 'Você já tem um check-in ativo em outro local.',
          'details', jsonb_build_object(
            'activePlaceId', v_active.place_id,
            'activeCheckInId', v_active.id
          )
        )
      );
    end if;

    update public.check_ins
    set status = 'ended', ended_at = now()
    where id = v_active.id;
    v_ended_id := v_active.id;
  end if;

  insert into public.check_ins (
    user_id, place_id, lat, lng, accuracy_meters, distance_meters,
    expires_at, visible_in_presence, status
  ) values (
    v_uid, p_place_id, p_lat, p_lng, p_accuracy_meters, v_distance,
    now() + make_interval(secs => v_cfg.check_in_ttl_seconds),
    coalesce(v_profile.show_in_presence, true),
    'active'
  )
  returning * into v_new;

  return jsonb_build_object(
    'checkIn', jsonb_build_object(
      'id', v_new.id,
      'placeId', v_new.place_id,
      'userId', v_new.user_id,
      'status', v_new.status,
      'startedAt', v_new.started_at,
      'expiresAt', v_new.expires_at,
      'endedAt', v_new.ended_at,
      'distanceMeters', v_new.distance_meters,
      'visibleInPresence', v_new.visible_in_presence
    ),
    'endedPreviousCheckInId', v_ended_id
  );
end;
$$;

revoke all on function public.create_check_in(
  uuid, double precision, double precision, double precision, timestamptz, boolean
) from public;
grant execute on function public.create_check_in(
  uuid, double precision, double precision, double precision, timestamptz, boolean
) to authenticated;

-- Agendar pg_cron se a extensão existir. No Free isso costuma falhar — ok.
do $$
begin
  if exists (
    select 1 from pg_extension where extname = 'pg_cron'
  ) or exists (
    select 1 from pg_namespace where nspname = 'cron'
  ) then
    if exists (select 1 from cron.job where jobname = 'expire-check-ins') then
      perform cron.unschedule('expire-check-ins');
    end if;
    perform cron.schedule(
      'expire-check-ins',
      '*/10 * * * *',
      $job$select public.expire_check_ins()$job$
    );
    raise notice 'pg_cron: job expire-check-ins a cada 10 min';
  else
    raise notice 'pg_cron indisponível — cole o SQL de supabase/README.md no editor';
  end if;
exception
  when others then
    raise notice 'pg_cron não agendado (%). Fallback: supabase/README.md', sqlerrm;
end;
$$;
