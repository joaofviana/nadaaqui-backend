# F2 — smoke RLS (SQL editor, projeto live)

Rodar **depois** de aplicar `20260918030000_harden_rls.sql`.

## Como anon (`select * from check_ins`)

No SQL editor, role `anon` (ou `set role anon` se o editor permitir):

```sql
select * from public.check_ins;
```

**Esperado:** vazio ou erro de policy — **nunca** linhas de outros users.

`who_is_here` continua ok para guest:

```sql
select public.who_is_here('952f671d-fb18-46eb-a45a-e0897e925650');
```

## Como user A, insert de user B

Autenticado como A:

```sql
insert into public.check_ins (
  user_id, place_id, lat, lng, distance_meters, expires_at, status
) values (
  '<uuid-do-user-B>',
  '11111111-1111-1111-1111-111111111111',
  -23.5505, -46.6333, 10, now() + interval '3 hours', 'active'
);
```

**Esperado:** falha (`with check` / policy). `create_check_in` usa `auth.uid()` — não dá para forçar outro user.

## Escalada curator

```sql
update public.profiles set is_curator = true where id = auth.uid();
```

**Esperado:** `FORBIDDEN` (trigger) ou policy `with check`.

## Nearby / seed

`nearby_places` (SECURITY INVOKER + places publicados) não deve quebrar:

```sql
select * from public.nearby_places(-23.5802452, -46.6058969, 5000, null, 'sao-paulo', null, null, 10, 0);
```

Pelo menos 1 row Ipiranga.
