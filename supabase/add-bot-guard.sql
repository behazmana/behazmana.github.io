-- =====================================================================
-- Flood guard for reviews. A review shows on the site at once, with no approval, so a bot could fill the pages.
-- At most 5 reviews per maker per hour, and 30 per hour overall. Above that the insert fails with
-- 'busy, try again later' (code P0001), the same as the other flood guards, and the site says it is busy.
-- Safe to run more than once. Everything is inside one transaction: if any line fails, nothing changes.
-- To undo: drop trigger reviews_throttle on public.reviews;
-- =====================================================================
begin;

create or replace function public.throttle_reviews()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare n int;
begin
  perform pg_advisory_xact_lock(hashtext('behazmana.reviews_throttle'));   -- one at a time, so a burst cannot slip through
  select count(*) into n from public.reviews where maker_id = new.maker_id and created_at > now() - interval '1 hour';
  if n >= 5 then raise exception 'busy, try again later' using errcode = 'P0001'; end if;
  select count(*) into n from public.reviews where created_at > now() - interval '1 hour';
  if n >= 30 then raise exception 'busy, try again later' using errcode = 'P0001'; end if;
  return new;
end
$$;

revoke all on function public.throttle_reviews() from public, anon, authenticated;

drop trigger if exists reviews_throttle on public.reviews;
create trigger reviews_throttle before insert on public.reviews
  for each row execute function public.throttle_reviews();

commit;
