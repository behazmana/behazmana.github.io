-- =====================================================================
-- Posts: a short name for a photo in the feed, and counts of what each photo led to.
--   * photo_posts: the short name. A maker writes only their own; everyone sees the names of approved makers' photos.
--   * photo_stats: one number per photo, kind and day. No person, address or device is stored.
--     kinds: 'open' (the photo was enlarged), 'profile' (the maker's page was opened from it), 'contact' (a contact button was tapped after it).
--     Each number stops at 2000 a day, so a bot cannot grow it without end.
-- Safe to run more than once. Everything is inside one transaction: if any line fails, nothing changes.
-- =====================================================================
begin;

create or replace function public.is_maker_photo(p_maker uuid, p_photo text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.makers m where m.id = p_maker and m.status = 'approved' and p_photo = any(m.photos))
$$;
revoke all on function public.is_maker_photo(uuid, text) from public, anon;
grant execute on function public.is_maker_photo(uuid, text) to authenticated;

create table if not exists public.photo_posts (
  maker_id   uuid not null references public.makers(id) on delete cascade,
  photo      text not null check (char_length(photo) between 3 and 200),
  caption    text not null check (char_length(btrim(caption)) between 1 and 60),
  updated_at timestamptz not null default now(),
  primary key (maker_id, photo)
);
alter table public.photo_posts enable row level security;
revoke all on public.photo_posts from public, anon, authenticated;
grant select, insert, update, delete on public.photo_posts to authenticated;

drop policy if exists photo_posts_maker_read on public.photo_posts;
create policy photo_posts_maker_read on public.photo_posts for select to authenticated using (maker_id = public.my_maker_id() or public.is_owner());
drop policy if exists photo_posts_maker_add on public.photo_posts;
create policy photo_posts_maker_add on public.photo_posts for insert to authenticated with check (maker_id = public.my_maker_id() and public.is_maker_photo(maker_id, photo));
drop policy if exists photo_posts_maker_edit on public.photo_posts;
create policy photo_posts_maker_edit on public.photo_posts for update to authenticated using (maker_id = public.my_maker_id()) with check (maker_id = public.my_maker_id() and public.is_maker_photo(maker_id, photo));
drop policy if exists photo_posts_remove on public.photo_posts;
create policy photo_posts_remove on public.photo_posts for delete to authenticated using (maker_id = public.my_maker_id() or public.is_owner());

create or replace view public.public_photo_posts with (security_invoker = false) as
  select p.maker_id, p.photo, p.caption
  from public.photo_posts p join public.makers m on m.id = p.maker_id
  where m.status = 'approved' and public.can_see_maker(m.id, m.is_test) and p.photo = any(m.photos);
revoke all on public.public_photo_posts from public, anon, authenticated;
grant select on public.public_photo_posts to anon, authenticated;

create table if not exists public.photo_stats (
  maker_id uuid not null references public.makers(id) on delete cascade,
  photo    text not null,
  kind     text not null check (kind in ('open', 'profile', 'contact')),
  day      date not null default current_date,
  n        integer not null default 1,
  primary key (maker_id, photo, kind, day)
);
alter table public.photo_stats enable row level security;   -- no policies and no grants: only the two functions below touch it
revoke all on public.photo_stats from public, anon, authenticated;

create or replace function public.track_photo(p_maker uuid, p_photo text, p_kind text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if p_kind not in ('open', 'profile', 'contact') or not public.is_maker_photo(p_maker, p_photo) then return; end if;
  insert into public.photo_stats as s (maker_id, photo, kind) values (p_maker, p_photo, p_kind)
  on conflict (maker_id, photo, kind, day) do update set n = least(s.n + 1, 2000);
end
$$;
revoke all on function public.track_photo(uuid, text, text) from public;
grant execute on function public.track_photo(uuid, text, text) to anon, authenticated;

create or replace function public.my_photo_stats() returns table (photo text, kind text, n bigint)
language sql stable security definer set search_path = '' as $$
  select s.photo, s.kind, sum(s.n)::bigint from public.photo_stats s where s.maker_id = public.my_maker_id() group by s.photo, s.kind
$$;
revoke all on function public.my_photo_stats() from public, anon;
grant execute on function public.my_photo_stats() to authenticated;

commit;
