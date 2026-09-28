-- Perfil público + follow seguro (auth.uid) + posts do usuário + feed seguindo

-- ─── get_public_profile ─────────────────────────────────
create or replace function public.get_public_profile(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_row public.profiles%rowtype;
  v_followers int;
  v_following int;
  v_posts int;
  v_sessions int;
  v_minutes int;
  v_meters int;
  v_following_me boolean := false;
  v_activity jsonb;
begin
  select * into v_row from public.profiles where id = p_user_id;
  if not found then
    raise exception 'NOT_FOUND' using errcode = 'P0001';
  end if;

  select count(*) into v_followers from public.follows where following_id = p_user_id;
  select count(*) into v_following from public.follows where follower_id = p_user_id;

  begin
    select count(*) into v_posts from public.posts where user_id = p_user_id;
  exception when undefined_column then
    begin
      select count(*) into v_posts from public.posts where author_id = p_user_id;
    exception when others then
      v_posts := 0;
    end;
  when others then
    v_posts := 0;
  end;

  -- Sessões (prefer swim_sessions; fallback check_ins)
  begin
    select count(*),
           coalesce(sum(greatest(0, duration_seconds) / 60), 0)::int,
           coalesce(sum(coalesce(meters, 0)), 0)::int
    into v_sessions, v_minutes, v_meters
    from public.swim_sessions
    where user_id = p_user_id;
  exception when others then
    begin
      select count(*),
             coalesce(sum(extract(epoch from (ended_at - started_at)) / 60), 0)::int,
             0
      into v_sessions, v_minutes, v_meters
      from public.check_ins
      where user_id = p_user_id and status = 'ended';
    exception when others then
      v_sessions := 0; v_minutes := 0; v_meters := 0;
    end;
  end;

  if v_me is not null and v_me <> p_user_id then
    select exists(
      select 1 from public.follows
      where follower_id = v_me and following_id = p_user_id
    ) into v_following_me;
  end if;

  -- Atividade últimos 90 dias (calendário)
  begin
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'date', d::text,
        'minutes', mins,
        'meters', mtrs
      ) order by d
    ), '[]'::jsonb)
    into v_activity
    from (
      select date(started_at) as d,
             sum(greatest(0, coalesce(duration_seconds, 0)) / 60)::int as mins,
             sum(coalesce(meters, 0))::int as mtrs
      from public.swim_sessions
      where user_id = p_user_id
        and started_at >= current_date - interval '90 days'
      group by date(started_at)
    ) q;
  exception when others then
    v_activity := '[]'::jsonb;
  end;

  return jsonb_build_object(
    'id', v_row.id,
    'displayName', coalesce(v_row.display_name, 'Nadador'),
    'avatarUrl', v_row.avatar_url,
    'bio', nullif(trim(coalesce(v_row.bio, '')), ''),
    'followers', v_followers,
    'following', v_following,
    'isFollowing', v_following_me,
    'isSelf', (v_me is not null and v_me = p_user_id),
    'stats', jsonb_build_object(
      'sessions', coalesce(v_sessions, 0),
      'minutes', coalesce(v_minutes, 0),
      'meters', coalesce(v_meters, 0),
      'streakDays', 0,
      'posts', coalesce(v_posts, 0)
    ),
    'activity', coalesce(v_activity, '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_public_profile(uuid) from public;
grant execute on function public.get_public_profile(uuid) to authenticated, anon;

-- ─── toggle_follow (usa auth.uid) ───────────────────────
create or replace function public.toggle_follow(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_exists boolean;
  v_followers int;
begin
  if v_me is null then
    raise exception 'UNAUTHORIZED' using errcode = 'P0001';
  end if;
  if p_user_id is null or p_user_id = v_me then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'NOT_FOUND' using errcode = 'P0001';
  end if;

  select exists(
    select 1 from public.follows
    where follower_id = v_me and following_id = p_user_id
  ) into v_exists;

  if v_exists then
    delete from public.follows
    where follower_id = v_me and following_id = p_user_id;
  else
    insert into public.follows (follower_id, following_id)
    values (v_me, p_user_id)
    on conflict do nothing;
  end if;

  select count(*) into v_followers
  from public.follows where following_id = p_user_id;

  return jsonb_build_object(
    'isFollowing', not v_exists,
    'followers', v_followers
  );
end;
$$;

revoke all on function public.toggle_follow(uuid) from public;
grant execute on function public.toggle_follow(uuid) to authenticated;

-- ─── list_user_posts ────────────────────────────────────
create or replace function public.list_user_posts(
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
declare
  v_items jsonb;
  v_limit int := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_offset int := greatest(coalesce(p_offset, 0), 0);
begin
  -- Tenta author_id ou user_id conforme schema
  begin
    select coalesce(jsonb_agg(row_to_json(q)::jsonb), '[]'::jsonb)
    into v_items
    from (
      select
        p.id,
        p.kind,
        p.body,
        p.stars,
        p.created_at as "createdAt",
        p.place_id as "placeId",
        pl.name as "placeName",
        coalesce(p.likes, 0) as likes
      from public.posts p
      left join public.places pl on pl.id = p.place_id
      where p.user_id = p_user_id
      order by p.created_at desc
      limit v_limit offset v_offset
    ) q;
  exception when undefined_column then
    select coalesce(jsonb_agg(row_to_json(q)::jsonb), '[]'::jsonb)
    into v_items
    from (
      select
        p.id,
        p.kind,
        p.body,
        p.stars,
        p.created_at as "createdAt",
        p.place_id as "placeId",
        pl.name as "placeName",
        coalesce(p.likes, 0) as likes
      from public.posts p
      left join public.places pl on pl.id = p.place_id
      where p.author_id = p_user_id
      order by p.created_at desc
      limit v_limit offset v_offset
    ) q;
  end;

  return jsonb_build_object('items', coalesce(v_items, '[]'::jsonb));
end;
$$;

revoke all on function public.list_user_posts(uuid, int, int) from public;
grant execute on function public.list_user_posts(uuid, int, int) to authenticated, anon;

-- ─── list_following_feed ────────────────────────────────
create or replace function public.list_following_feed(
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
  v_me uuid := auth.uid();
  v_items jsonb;
  v_limit int := least(greatest(coalesce(p_limit, 30), 1), 50);
  v_offset int := greatest(coalesce(p_offset, 0), 0);
begin
  if v_me is null then
    raise exception 'UNAUTHORIZED' using errcode = 'P0001';
  end if;

  -- Reutiliza forma do list_feed se possível; monta lista mínima
  begin
    select coalesce(jsonb_agg(item order by created_at desc), '[]'::jsonb)
    into v_items
    from (
      select jsonb_build_object(
        'id', p.id,
        'kind', p.kind,
        'body', p.body,
        'stars', p.stars,
        'createdAt', p.created_at,
        'placeId', p.place_id,
        'placeName', pl.name,
        'likes', coalesce(p.likes, 0),
        'liked', false,
        'author', jsonb_build_object(
          'id', pr.id,
          'displayName', pr.display_name,
          'avatarUrl', pr.avatar_url
        )
      ) as item,
      p.created_at
      from public.posts p
      join public.follows f on f.following_id = p.user_id and f.follower_id = v_me
      join public.profiles pr on pr.id = p.user_id
      left join public.places pl on pl.id = p.place_id
      order by p.created_at desc
      limit v_limit offset v_offset
    ) q;
  exception when undefined_column then
    select coalesce(jsonb_agg(item order by created_at desc), '[]'::jsonb)
    into v_items
    from (
      select jsonb_build_object(
        'id', p.id,
        'kind', p.kind,
        'body', p.body,
        'stars', p.stars,
        'createdAt', p.created_at,
        'placeId', p.place_id,
        'placeName', pl.name,
        'likes', coalesce(p.likes, 0),
        'liked', false,
        'author', jsonb_build_object(
          'id', pr.id,
          'displayName', pr.display_name,
          'avatarUrl', pr.avatar_url
        )
      ) as item,
      p.created_at
      from public.posts p
      join public.follows f on f.following_id = p.author_id and f.follower_id = v_me
      join public.profiles pr on pr.id = p.author_id
      left join public.places pl on pl.id = p.place_id
      order by p.created_at desc
      limit v_limit offset v_offset
    ) q;
  end;

  return jsonb_build_object('items', coalesce(v_items, '[]'::jsonb));
end;
$$;

revoke all on function public.list_following_feed(int, int) from public;
grant execute on function public.list_following_feed(int, int) to authenticated;
