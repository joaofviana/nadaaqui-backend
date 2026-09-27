-- Exclusão de conta (exigência Google Play)
-- Apaga dados públicos do usuário e o registro em auth.users.

create or replace function public.delete_my_account()
returns json
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  -- Dados de app (FKs com on delete cascade cobrem a maior parte)
  delete from public.club_event_rsvps where user_id = uid;
  delete from public.club_members where user_id = uid;
  -- Clubes onde era owner: remove se não houver outro owner (simplificado: delete club)
  delete from public.clubs where owner_id = uid;
  delete from public.comment_likes where user_id = uid;
  delete from public.comments where user_id = uid;
  delete from public.notifications where user_id = uid or actor_id = uid;
  delete from public.follows where follower_id = uid or following_id = uid;

  -- Perfil (cascade para posts/sessions se FK permitir; senão limpa o que der)
  begin
    delete from public.posts where author_id = uid;
  exception when undefined_column then
    begin
      delete from public.posts where user_id = uid;
    exception when others then null;
    end;
  when others then null;
  end;

  begin
    delete from public.swim_sessions where user_id = uid;
  exception when others then null;
  end;

  begin
    delete from public.check_ins where user_id = uid;
  exception when others then null;
  end;

  begin
    delete from public.workout_plans where user_id = uid;
  exception when others then null;
  end;

  delete from public.profiles where id = uid;

  -- Conta Auth (GoTrue)
  delete from auth.users where id = uid;

  return json_build_object('ok', true, 'deletedUserId', uid);
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;
