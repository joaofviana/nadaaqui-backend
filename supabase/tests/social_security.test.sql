-- pgTAP: segurança da parte social (follows, comments, comment_likes, notifications,
-- contadores do perfil e RPCs sociais). Roda com `supabase test db`.
-- Usuários: A (aaaa...) é quem testa; B e C são outros usuários.

begin;

select plan(67);

-- ---------------------------------------------------------------------------
-- Dados de teste (como postgres)
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'a@teste.local', '{"display_name":"Ana"}'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'b@teste.local', '{"display_name":"Bia"}'),
  ('cccccccc-0000-4000-8000-00000000000c', 'c@teste.local', '{"display_name":"Caio"}');

-- post do B (o trigger soma posts_count do B)
insert into public.posts (id, user_id, body, city_slug)
values ('dddddddd-0000-4000-8000-0000000000d1', 'bbbbbbbb-0000-4000-8000-00000000000b', 'post do B', 'sao-paulo');

-- C já segue B (contadores ajustados como se tivesse vindo da RPC)
insert into public.follows (follower_id, following_id)
values ('cccccccc-0000-4000-8000-00000000000c', 'bbbbbbbb-0000-4000-8000-00000000000b');
update public.profiles set followers_count = 1 where id = 'bbbbbbbb-0000-4000-8000-00000000000b';
update public.profiles set following_count = 1 where id = 'cccccccc-0000-4000-8000-00000000000c';

-- comentário do C no post do B
insert into public.comments (id, post_id, user_id, text)
values ('eeeeeeee-0000-4000-8000-0000000000e1', 'dddddddd-0000-4000-8000-0000000000d1',
        'cccccccc-0000-4000-8000-00000000000c', 'comentário do C');

-- like do C no próprio comentário (linha de outro usuário em comment_likes)
insert into public.comment_likes (comment_id, user_id)
values ('eeeeeeee-0000-4000-8000-0000000000e1', 'cccccccc-0000-4000-8000-00000000000c');

-- uma notificação para A e uma para B
insert into public.notifications (id, user_id, type, title) values
  ('ffffffff-0000-4000-8000-0000000000fa', 'aaaaaaaa-0000-4000-8000-00000000000a', 'follow', 'notif do A'),
  ('ffffffff-0000-4000-8000-0000000000fb', 'bbbbbbbb-0000-4000-8000-00000000000b', 'follow', 'notif do B');

-- ---------------------------------------------------------------------------
-- Estrutura
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::int from pg_class
    where relnamespace = 'public'::regnamespace
      and relname in ('follows', 'comments', 'comment_likes', 'notifications')
      and relrowsecurity),
  4,
  'RLS ligado em follows, comments, comment_likes e notifications'
);

select ok(
  not has_function_privilege('anon', 'public.list_notifications(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.follow_user(uuid, uuid)', 'execute')
  and not has_function_privilege('anon', 'public.create_comment(uuid, text)', 'execute'),
  'anon não executa RPCs sociais'
);

select ok(
  not has_function_privilege('authenticated', 'public.increment_posts_count()', 'execute'),
  'authenticated não executa a função de trigger increment_posts_count'
);

-- ---------------------------------------------------------------------------
-- anon: não lê nem escreve nas 4 tabelas
-- ---------------------------------------------------------------------------
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select throws_ok('select * from public.follows', '42501', null, 'anon não lê follows');
select throws_ok('select * from public.comments', '42501', null, 'anon não lê comments');
select throws_ok('select * from public.comment_likes', '42501', null, 'anon não lê comment_likes');
select throws_ok('select * from public.notifications', '42501', null, 'anon não lê notifications');

select throws_ok(
  $$insert into public.follows (follower_id, following_id)
    values ('bbbbbbbb-0000-4000-8000-00000000000b', 'cccccccc-0000-4000-8000-00000000000c')$$,
  '42501', null, 'anon não insere em follows');
select throws_ok(
  $$insert into public.comments (post_id, user_id, text)
    values ('dddddddd-0000-4000-8000-0000000000d1', 'bbbbbbbb-0000-4000-8000-00000000000b', 'x')$$,
  '42501', null, 'anon não insere em comments');
select throws_ok(
  $$insert into public.comment_likes (comment_id, user_id)
    values ('eeeeeeee-0000-4000-8000-0000000000e1', 'bbbbbbbb-0000-4000-8000-00000000000b')$$,
  '42501', null, 'anon não insere em comment_likes');
select throws_ok(
  $$insert into public.notifications (user_id, type, title)
    values ('bbbbbbbb-0000-4000-8000-00000000000b', 'x', 'x')$$,
  '42501', null, 'anon não insere em notifications');
select throws_ok('delete from public.follows', '42501', null, 'anon não apaga follows');
select throws_ok('delete from public.comments', '42501', null, 'anon não apaga comments');
select throws_ok('delete from public.comment_likes', '42501', null, 'anon não apaga comment_likes');
select throws_ok('delete from public.notifications', '42501', null, 'anon não apaga notifications');
select throws_ok($$update public.follows set created_at = now()$$, '42501', null, 'anon não altera follows');
select throws_ok($$update public.comments set text = 'x'$$, '42501', null, 'anon não altera comments');
select throws_ok($$update public.comment_likes set created_at = now()$$, '42501', null, 'anon não altera comment_likes');
select throws_ok('update public.notifications set read = true', '42501', null, 'anon não altera notifications');

select throws_ok('select * from public.list_notifications()', '42501', null, 'anon não chama list_notifications');
select throws_ok(
  $$select public.follow_user('bbbbbbbb-0000-4000-8000-00000000000b', 'cccccccc-0000-4000-8000-00000000000c')$$,
  '42501', null, 'anon não chama follow_user');

reset role;

-- ---------------------------------------------------------------------------
-- usuário A logado
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-00000000000a","role":"authenticated"}';

-- leitura
select is((select count(*)::int from public.follows), 1, 'A lê follows');
select is((select count(*)::int from public.comments), 1, 'A lê comments');
select is((select count(*)::int from public.comment_likes), 1, 'A lê comment_likes');
select is(
  (select count(*)::int from public.notifications where user_id = 'bbbbbbbb-0000-4000-8000-00000000000b'),
  0, 'A não vê notificações do B na tabela');
select is((select count(*)::int from public.notifications), 1, 'A vê só a própria notificação na tabela');

-- notificações: update
select results_eq(
  $$with u as (update public.notifications set read = true
               where id = 'ffffffff-0000-4000-8000-0000000000fb' returning 1)
    select count(*)::int from u$$,
  $$values (0)$$,
  'A não marca como lida notificação do B (update direto)');
select results_eq(
  $$with u as (update public.notifications set read = true
               where id = 'ffffffff-0000-4000-8000-0000000000fa' returning 1)
    select count(*)::int from u$$,
  $$values (1)$$,
  'A marca a própria notificação como lida (update direto)');
select throws_ok(
  $$update public.notifications set title = 'hack' where id = 'ffffffff-0000-4000-8000-0000000000fa'$$,
  '42501', null, 'A não altera título da própria notificação (só a coluna read)');

-- list_notifications
select results_eq(
  'select id from public.list_notifications()',
  $$values ('ffffffff-0000-4000-8000-0000000000fa'::uuid)$$,
  'list_notifications() devolve só as notificações do A');
select results_eq(
  $$select id from public.list_notifications('aaaaaaaa-0000-4000-8000-00000000000a')$$,
  $$values ('ffffffff-0000-4000-8000-0000000000fa'::uuid)$$,
  'list_notifications(A) continua funcionando para o próprio A');
select throws_ok(
  $$select * from public.list_notifications('bbbbbbbb-0000-4000-8000-00000000000b')$$,
  'P0001', 'FORBIDDEN', 'list_notifications(B) é recusado para A');

select lives_ok(
  $$select public.mark_notification_read('ffffffff-0000-4000-8000-0000000000fb')$$,
  'mark_notification_read na notificação do B roda sem erro (mas não altera, conferido no fim)');

-- escrita direta proibida
select throws_ok(
  $$insert into public.follows (follower_id, following_id)
    values ('bbbbbbbb-0000-4000-8000-00000000000b', 'cccccccc-0000-4000-8000-00000000000c')$$,
  '42501', null, 'A não insere follow em nome do B');
select throws_ok(
  $$insert into public.follows (follower_id, following_id)
    values ('aaaaaaaa-0000-4000-8000-00000000000a', 'cccccccc-0000-4000-8000-00000000000c')$$,
  '42501', null, 'A não insere follow direto nem em nome próprio (só via RPC)');
select throws_ok(
  $$insert into public.comments (post_id, user_id, text)
    values ('dddddddd-0000-4000-8000-0000000000d1', 'bbbbbbbb-0000-4000-8000-00000000000b', 'fake')$$,
  '42501', null, 'A não insere comentário em nome do B');
select throws_ok('delete from public.follows', '42501', null, 'A não apaga follows direto');
select throws_ok(
  $$update public.follows set following_id = 'aaaaaaaa-0000-4000-8000-00000000000a'
    where follower_id = 'cccccccc-0000-4000-8000-00000000000c'$$,
  '42501', null, 'A não altera follow do C');
select throws_ok(
  $$delete from public.comments where id = 'eeeeeeee-0000-4000-8000-0000000000e1'$$,
  '42501', null, 'A não apaga comentário do C');
select throws_ok(
  $$update public.comment_likes set user_id = 'aaaaaaaa-0000-4000-8000-00000000000a'
    where user_id = 'cccccccc-0000-4000-8000-00000000000c'$$,
  '42501', null, 'A não altera like do C');
select throws_ok(
  $$delete from public.comment_likes where user_id = 'cccccccc-0000-4000-8000-00000000000c'$$,
  '42501', null, 'A não apaga like do C');
select throws_ok(
  $$delete from public.notifications where id = 'ffffffff-0000-4000-8000-0000000000fb'$$,
  '42501', null, 'A não apaga notificação do B');
select throws_ok(
  $$update public.comments set likes = 999$$,
  '42501', null, 'A não altera likes de comentário direto');
select throws_ok(
  $$insert into public.notifications (user_id, type, title)
    values ('bbbbbbbb-0000-4000-8000-00000000000b', 'x', 'spam')$$,
  '42501', null, 'A não cria notificação');

-- RPCs em nome de outro usuário
select throws_ok(
  $$select public.follow_user('bbbbbbbb-0000-4000-8000-00000000000b', 'cccccccc-0000-4000-8000-00000000000c')$$,
  'P0001', 'FORBIDDEN', 'follow_user em nome do B é recusado');
select throws_ok(
  $$select public.unfollow_user('cccccccc-0000-4000-8000-00000000000c', 'bbbbbbbb-0000-4000-8000-00000000000b')$$,
  'P0001', 'FORBIDDEN', 'unfollow_user em nome do C é recusado');

-- alvo inválido no follow_user
select throws_ok(
  $$select public.follow_user(null, null)$$,
  'P0001', 'VALIDATION_ERROR', 'follow_user com alvo null dá VALIDATION_ERROR');
select throws_ok(
  $$select public.follow_user(null, '99999999-0000-4000-8000-000000000099')$$,
  'P0001', 'VALIDATION_ERROR', 'follow_user com alvo inexistente dá VALIDATION_ERROR');

-- contadores do próprio perfil
update public.profiles
set followers_count = 999, following_count = 999, posts_count = 999, display_name = 'Ana Nova'
where id = 'aaaaaaaa-0000-4000-8000-00000000000a';

select results_eq(
  $$select followers_count, following_count, posts_count, display_name
    from public.profiles where id = 'aaaaaaaa-0000-4000-8000-00000000000a'$$,
  $$values (0, 0, 0, 'Ana Nova'::text)$$,
  'A não altera os próprios contadores direto, mas altera o nome');

-- RPCs continuam funcionando e atualizam contadores
select is(
  public.follow_user('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b')->>'success',
  'true', 'follow_user(A, B) funciona');
select results_eq(
  $$select (select following_count from public.profiles where id = 'aaaaaaaa-0000-4000-8000-00000000000a'),
           (select followers_count from public.profiles where id = 'bbbbbbbb-0000-4000-8000-00000000000b')$$,
  $$values (1, 2)$$,
  'follow_user atualiza following_count do A e followers_count do B');

select lives_ok(
  $$select public.follow_user(null, 'bbbbbbbb-0000-4000-8000-00000000000b')$$,
  'follow_user com p_follower_id null (= eu) funciona');
select results_eq(
  $$select (select following_count from public.profiles where id = 'aaaaaaaa-0000-4000-8000-00000000000a'),
           (select followers_count from public.profiles where id = 'bbbbbbbb-0000-4000-8000-00000000000b')$$,
  $$values (1, 2)$$,
  'seguir de novo não infla contadores');

select is(
  public.follow_user('aaaaaaaa-0000-4000-8000-00000000000a', 'aaaaaaaa-0000-4000-8000-00000000000a')->>'error',
  'Cannot follow yourself', 'A não segue a si mesmo');

select ok(
  public.is_following('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b'),
  'is_following(A, B) = true');

select is(
  (public.get_user_profile('bbbbbbbb-0000-4000-8000-00000000000b')->>'followers_count')::int,
  2, 'get_user_profile funciona (sem UPDATE) e conta followers');

select is(
  public.create_comment('dddddddd-0000-4000-8000-0000000000d1', 'comentário do A')->>'success',
  'true', 'create_comment funciona');
select results_eq(
  $$select (select count(*)::int from public.comments
             where user_id = 'aaaaaaaa-0000-4000-8000-00000000000a'),
           (select posts_count from public.profiles where id = 'aaaaaaaa-0000-4000-8000-00000000000a')$$,
  $$values (1, 1)$$,
  'create_comment grava como A e atualiza posts_count do A');

select is(
  public.toggle_comment_like('eeeeeeee-0000-4000-8000-0000000000e1')->>'likes',
  '1', 'toggle_comment_like funciona no comentário do C');

select is(
  public.unfollow_user('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b')->>'success',
  'true', 'unfollow_user(A, B) funciona');
select lives_ok(
  $$select public.unfollow_user('aaaaaaaa-0000-4000-8000-00000000000a', 'bbbbbbbb-0000-4000-8000-00000000000b')$$,
  'unfollow_user repetido não dá erro');
select results_eq(
  $$select (select following_count from public.profiles where id = 'aaaaaaaa-0000-4000-8000-00000000000a'),
           (select followers_count from public.profiles where id = 'bbbbbbbb-0000-4000-8000-00000000000b')$$,
  $$values (0, 1)$$,
  'unfollow_user volta os contadores e repetir não desconta de novo');

-- post direto (policy posts_insert_own) ainda soma posts_count pelo trigger
insert into public.posts (user_id, body, city_slug)
values ('aaaaaaaa-0000-4000-8000-00000000000a', 'post do A', 'sao-paulo');
select is(
  (select posts_count from public.profiles where id = 'aaaaaaaa-0000-4000-8000-00000000000a'),
  2, 'trigger de posts ainda atualiza posts_count');

reset role;

-- ---------------------------------------------------------------------------
-- authenticated sem usuário no JWT (sub vazio): UNAUTHORIZED com P0001
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"role":"authenticated"}';
select throws_ok(
  'select * from public.list_notifications()',
  'P0001', 'UNAUTHORIZED', 'list_notifications sem usuário dá UNAUTHORIZED (P0001)');
reset role;

-- ---------------------------------------------------------------------------
-- Conferência final (como postgres)
-- ---------------------------------------------------------------------------
select is(
  (select read from public.notifications where id = 'ffffffff-0000-4000-8000-0000000000fb'),
  false, 'notificação do B continua não lida');
select is(
  (select title from public.notifications where id = 'ffffffff-0000-4000-8000-0000000000fa'),
  'notif do A', 'título da notificação do A não mudou');
select ok(
  exists (select 1 from public.follows
          where follower_id = 'cccccccc-0000-4000-8000-00000000000c'
            and following_id = 'bbbbbbbb-0000-4000-8000-00000000000b'),
  'follow C -> B continua existindo');

select * from finish();

rollback;
