-- NadaAqui — planos de treino (workout builder)
-- Tabelas: workout_plans, workout_blocks
-- RPCs: save_workout_plan, list_my_workouts, get_workout_plan,
--        delete_workout_plan, start_workout

create type public.pool_length as enum ('m25', 'm50');
create type public.workout_focus as enum ('tecnica', 'velocidade', 'resistencia', 'misto');
create type public.workout_phase as enum (
  'aquecimento', 'serie', 'educativo', 'desaquecimento'
);

create table if not exists public.workout_plans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 120),
  pool_length public.pool_length not null default 'm25',
  focus public.workout_focus not null default 'misto',
  total_meters int not null default 0 check (total_meters >= 0),
  estimated_minutes int not null default 0 check (estimated_minutes >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists workout_plans_user_created_idx
  on public.workout_plans (user_id, created_at desc);

create table if not exists public.workout_blocks (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.workout_plans (id) on delete cascade,
  phase public.workout_phase not null default 'serie',
  title text not null check (char_length(trim(title)) between 1 and 80),
  detail text not null default '' check (char_length(detail) <= 300),
  meters int not null default 0 check (meters >= 0),
  sets int not null default 1 check (sets between 1 and 100),
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists workout_blocks_plan_order_idx
  on public.workout_blocks (plan_id, sort_order);

alter table public.workout_plans enable row level security;
alter table public.workout_blocks enable row level security;

drop policy if exists workout_plans_own on public.workout_plans;
create policy workout_plans_own on public.workout_plans
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists workout_blocks_own on public.workout_blocks;
create policy workout_blocks_own on public.workout_blocks
  for all to authenticated
  using (
    exists (
      select 1 from public.workout_plans p
      where p.id = plan_id and p.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.workout_plans p
      where p.id = plan_id and p.user_id = auth.uid()
    )
  );

create trigger workout_plans_updated_at
  before update on public.workout_plans
  for each row execute function public.set_updated_at();

-- ─── Helpers ───────────────────────────────────────────────

create or replace function public._workout_plan_json(p_plan_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_plan public.workout_plans%rowtype;
  v_blocks jsonb;
begin
  select * into v_plan from public.workout_plans where id = p_plan_id;
  if not found then
    return null;
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', b.id,
      'phase', b.phase,
      'title', b.title,
      'detail', b.detail,
      'meters', b.meters,
      'sets', b.sets,
      'sortOrder', b.sort_order
    ) order by b.sort_order, b.created_at
  ), '[]'::jsonb)
  into v_blocks
  from public.workout_blocks b
  where b.plan_id = p_plan_id;

  return jsonb_build_object(
    'id', v_plan.id,
    'name', v_plan.name,
    'poolLength', v_plan.pool_length,
    'focus', v_plan.focus,
    'totalMeters', v_plan.total_meters,
    'estimatedMinutes', v_plan.estimated_minutes,
    'createdAt', v_plan.created_at,
    'updatedAt', v_plan.updated_at,
    'blocks', v_blocks
  );
end;
$$;

-- ─── save_workout_plan ───────────────────────────────────
-- p_blocks: jsonb array [{phase, title, detail, meters, sets}]

create or replace function public.save_workout_plan(
  p_name text,
  p_pool_length public.pool_length default 'm25',
  p_focus public.workout_focus default 'misto',
  p_blocks jsonb default '[]'::jsonb,
  p_plan_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_plan_id uuid;
  v_total int := 0;
  v_mins int := 0;
  v_block jsonb;
  v_idx int := 0;
  v_meters int;
  v_sets int;
  v_phase text;
  v_title text;
  v_detail text;
begin
  if v_uid is null then
    raise exception 'UNAUTHORIZED' using errcode = 'P0001';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001';
  end if;

  if p_blocks is null or jsonb_typeof(p_blocks) <> 'array' then
    p_blocks := '[]'::jsonb;
  end if;

  -- soma metros
  for v_block in select * from jsonb_array_elements(p_blocks)
  loop
    v_meters := coalesce((v_block->>'meters')::int, 0);
    v_sets := greatest(1, coalesce((v_block->>'sets')::int, 1));
    v_total := v_total + (v_meters * v_sets);
  end loop;

  v_mins := greatest(15, least(120, round((v_total::numeric / 100.0) * 2)::int));
  if v_total = 0 then v_mins := 0; end if;

  if p_plan_id is not null then
    update public.workout_plans
    set name = left(trim(p_name), 120),
        pool_length = coalesce(p_pool_length, 'm25'),
        focus = coalesce(p_focus, 'misto'),
        total_meters = v_total,
        estimated_minutes = v_mins,
        updated_at = now()
    where id = p_plan_id and user_id = v_uid
    returning id into v_plan_id;

    if v_plan_id is null then
      raise exception 'NOT_FOUND' using errcode = 'P0001';
    end if;

    delete from public.workout_blocks where plan_id = v_plan_id;
  else
    insert into public.workout_plans (
      user_id, name, pool_length, focus, total_meters, estimated_minutes
    ) values (
      v_uid,
      left(trim(p_name), 120),
      coalesce(p_pool_length, 'm25'),
      coalesce(p_focus, 'misto'),
      v_total,
      v_mins
    )
    returning id into v_plan_id;
  end if;

  for v_block in select * from jsonb_array_elements(p_blocks)
  loop
    v_phase := coalesce(v_block->>'phase', 'serie');
    if v_phase not in ('aquecimento', 'serie', 'educativo', 'desaquecimento') then
      v_phase := 'serie';
    end if;
    v_title := left(coalesce(nullif(trim(v_block->>'title'), ''), 'Bloco'), 80);
    v_detail := left(coalesce(v_block->>'detail', ''), 300);
    v_meters := greatest(0, coalesce((v_block->>'meters')::int, 0));
    v_sets := greatest(1, least(100, coalesce((v_block->>'sets')::int, 1)));

    insert into public.workout_blocks (
      plan_id, phase, title, detail, meters, sets, sort_order
    ) values (
      v_plan_id,
      v_phase::public.workout_phase,
      v_title,
      v_detail,
      v_meters,
      v_sets,
      v_idx
    );
    v_idx := v_idx + 1;
  end loop;

  return public._workout_plan_json(v_plan_id);
end;
$$;

grant execute on function public.save_workout_plan(
  text, public.pool_length, public.workout_focus, jsonb, uuid
) to authenticated;

-- ─── list_my_workouts ────────────────────────────────────

create or replace function public.list_my_workouts(
  p_limit int default 30,
  p_offset int default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_items jsonb;
  v_total int;
begin
  if v_uid is null then
    raise exception 'UNAUTHORIZED' using errcode = 'P0001';
  end if;

  if p_limit is null or p_limit < 1 then p_limit := 30; end if;
  if p_limit > 50 then p_limit := 50; end if;
  if p_offset is null or p_offset < 0 then p_offset := 0; end if;

  select count(*) into v_total
  from public.workout_plans
  where user_id = v_uid;

  select coalesce(jsonb_agg(item order by created_at desc), '[]'::jsonb)
  into v_items
  from (
    select public._workout_plan_json(p.id) as item, p.created_at
    from public.workout_plans p
    where p.user_id = v_uid
    order by p.created_at desc
    limit p_limit offset p_offset
  ) q;

  return jsonb_build_object(
    'items', v_items,
    'total', v_total
  );
end;
$$;

grant execute on function public.list_my_workouts(int, int) to authenticated;

-- ─── get_workout_plan ────────────────────────────────────

create or replace function public.get_workout_plan(p_plan_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_owner uuid;
begin
  if v_uid is null then
    raise exception 'UNAUTHORIZED' using errcode = 'P0001';
  end if;

  select user_id into v_owner
  from public.workout_plans
  where id = p_plan_id;

  if v_owner is null then
    raise exception 'NOT_FOUND' using errcode = 'P0001';
  end if;
  if v_owner <> v_uid then
    raise exception 'FORBIDDEN' using errcode = 'P0001';
  end if;

  return public._workout_plan_json(p_plan_id);
end;
$$;

grant execute on function public.get_workout_plan(uuid) to authenticated;

-- ─── delete_workout_plan ─────────────────────────────────

create or replace function public.delete_workout_plan(p_plan_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_deleted uuid;
begin
  if v_uid is null then
    raise exception 'UNAUTHORIZED' using errcode = 'P0001';
  end if;

  delete from public.workout_plans
  where id = p_plan_id and user_id = v_uid
  returning id into v_deleted;

  if v_deleted is null then
    raise exception 'NOT_FOUND' using errcode = 'P0001';
  end if;

  return jsonb_build_object('deleted', true, 'id', v_deleted);
end;
$$;

grant execute on function public.delete_workout_plan(uuid) to authenticated;

-- ─── start_workout ───────────────────────────────────────
-- Registra sessão a partir do plano (sem check-in obrigatório).
-- place_id opcional; se omitido, usa um place genérico da cidade ou null-safe.

create or replace function public.start_workout(
  p_plan_id uuid,
  p_place_id uuid default null,
  p_meters int default null,
  p_duration_seconds int default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_plan public.workout_plans%rowtype;
  v_place_id uuid;
  v_place_name text;
  v_meters int;
  v_dur int;
  v_session public.swim_sessions%rowtype;
  v_started timestamptz := now();
  v_ended timestamptz;
begin
  if v_uid is null then
    raise exception 'UNAUTHORIZED' using errcode = 'P0001';
  end if;

  select * into v_plan
  from public.workout_plans
  where id = p_plan_id and user_id = v_uid;

  if not found then
    raise exception 'NOT_FOUND' using errcode = 'P0001';
  end if;

  v_meters := coalesce(p_meters, v_plan.total_meters);
  v_dur := coalesce(
    p_duration_seconds,
    greatest(60, v_plan.estimated_minutes * 60)
  );
  v_ended := v_started + make_interval(secs => v_dur);

  v_place_id := p_place_id;
  if v_place_id is null then
    select id, name into v_place_id, v_place_name
    from public.places
    where is_published
    order by created_at
    limit 1;
  else
    select name into v_place_name
    from public.places
    where id = v_place_id;
  end if;

  if v_place_id is null then
    raise exception 'NO_PLACE' using errcode = 'P0001';
  end if;

  insert into public.swim_sessions (
    user_id, place_id, started_at, ended_at, duration_seconds, meters
  ) values (
    v_uid, v_place_id, v_started, v_ended, v_dur, v_meters
  )
  returning * into v_session;

  return jsonb_build_object(
    'session', jsonb_build_object(
      'id', v_session.id,
      'placeId', v_session.place_id,
      'placeName', coalesce(v_place_name, ''),
      'startedAt', v_session.started_at,
      'endedAt', v_session.ended_at,
      'durationSeconds', v_session.duration_seconds,
      'meters', v_session.meters
    ),
    'plan', public._workout_plan_json(p_plan_id)
  );
end;
$$;

grant execute on function public.start_workout(uuid, uuid, int, int) to authenticated;
