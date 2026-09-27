-- Dias da semana em que o treino é feito (ISO: 1=seg … 7=dom)

alter table public.workout_plans
  add column if not exists week_days int[] not null default '{}';

comment on column public.workout_plans.week_days is
  'ISO weekdays 1=Mon … 7=Sun';

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
    'weekDays', coalesce(to_jsonb(v_plan.week_days), '[]'::jsonb),
    'totalMeters', v_plan.total_meters,
    'estimatedMinutes', v_plan.estimated_minutes,
    'createdAt', v_plan.created_at,
    'updatedAt', v_plan.updated_at,
    'blocks', v_blocks
  );
end;
$$;

drop function if exists public.save_workout_plan(
  text, public.pool_length, public.workout_focus, jsonb, uuid
);

create or replace function public.save_workout_plan(
  p_name text,
  p_pool_length public.pool_length default 'm25',
  p_focus public.workout_focus default 'misto',
  p_blocks jsonb default '[]'::jsonb,
  p_plan_id uuid default null,
  p_week_days int[] default '{}'
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
  v_days int[];
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

  -- normaliza dias 1–7 únicos
  select coalesce(array_agg(distinct d order by d), '{}')
  into v_days
  from unnest(coalesce(p_week_days, '{}')) as d
  where d between 1 and 7;

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
        week_days = v_days,
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
      user_id, name, pool_length, focus, week_days, total_meters, estimated_minutes
    ) values (
      v_uid,
      left(trim(p_name), 120),
      coalesce(p_pool_length, 'm25'),
      coalesce(p_focus, 'misto'),
      v_days,
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
  text, public.pool_length, public.workout_focus, jsonb, uuid, int[]
) to authenticated;
