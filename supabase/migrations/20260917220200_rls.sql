-- NadaAqui Sprint 1 — RLS

alter table public.app_config enable row level security;
alter table public.profiles enable row level security;
alter table public.places enable row level security;
alter table public.check_ins enable row level security;
alter table public.posts enable row level security;
alter table public.favorites enable row level security;
alter table public.place_suggestions enable row level security;

-- app_config: leitura pública
create policy app_config_select on public.app_config
  for select to anon, authenticated
  using (true);

-- profiles
create policy profiles_select_authenticated on public.profiles
  for select to authenticated
  using (true);

create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- places: guest + auth leem publicados
create policy places_select_published on public.places
  for select to anon, authenticated
  using (is_published = true);

create policy places_curator_all on public.places
  for all to authenticated
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_curator))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_curator));

-- check_ins
-- próprio sempre; presença visível de outros se active e não expirado
create policy check_ins_select on public.check_ins
  for select to anon, authenticated
  using (
    user_id = auth.uid()
    or (
      status = 'active'
      and expires_at > now()
      and visible_in_presence = true
    )
  );

create policy check_ins_insert_own on public.check_ins
  for insert to authenticated
  with check (user_id = auth.uid());

create policy check_ins_update_own on public.check_ins
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- favorites / suggestions / posts (P2 mínimo)
create policy favorites_own on public.favorites
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy posts_select on public.posts
  for select to anon, authenticated
  using (true);

create policy posts_insert_own on public.posts
  for insert to authenticated
  with check (user_id = auth.uid());

create policy suggestions_select_own on public.place_suggestions
  for select to authenticated
  using (
    user_id = auth.uid()
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_curator)
  );

create policy suggestions_insert_own on public.place_suggestions
  for insert to authenticated
  with check (user_id = auth.uid());
