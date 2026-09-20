-- Social schema: follows, comments, notifications
-- Tabelas para funcionalidades sociais

begin;

-- Tabela de follows
create table public.follows (
  id uuid primary key default gen_random_uuid(),
  follower_id uuid not null references public.profiles (id) on delete cascade,
  following_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (follower_id, following_id)
);

create index follows_follower_idx on public.follows (follower_id);
create index follows_following_idx on public.follows (following_id);

-- Tabela de comentários
create table public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  text text not null check (char_length(text) between 1 and 500),
  likes int not null default 0,
  created_at timestamptz not null default now()
);

create index comments_post_idx on public.comments (post_id);
create index comments_user_idx on public.comments (user_id);

-- Tabela de likes em comentários
create table public.comment_likes (
  comment_id uuid not null references public.comments (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (comment_id, user_id)
);

-- Tabela de notificações
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  type text not null, -- 'like', 'comment', 'follow', 'mention', 'check_in'
  title text not null,
  body text,
  actor_id uuid references public.profiles (id) on delete set null,
  post_id uuid references public.posts (id) on delete set null,
  place_id uuid references public.places (id) on delete set null,
  read boolean not null default false,
  created_at timestamptz not null default now()
);

create index notifications_user_idx on public.notifications (user_id, read, created_at desc);
create index notifications_actor_idx on public.notifications (actor_id);

-- Adicionar campos de contadores ao profiles (se não existirem)
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_name = 'profiles' and column_name = 'followers_count'
  ) then
    alter table public.profiles add column followers_count int not null default 0;
  end if;
  
  if not exists (
    select 1 from information_schema.columns
    where table_name = 'profiles' and column_name = 'following_count'
  ) then
    alter table public.profiles add column following_count int not null default 0;
  end if;
  
  if not exists (
    select 1 from information_schema.columns
    where table_name = 'profiles' and column_name = 'posts_count'
  ) then
    alter table public.profiles add column posts_count int not null default 0;
  end if;
  
  if not exists (
    select 1 from information_schema.columns
    where table_name = 'profiles' and column_name = 'bio'
  ) then
    alter table public.profiles add column bio text;
  end if;
end $$;

commit;
