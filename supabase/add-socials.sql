-- =====================================================================
-- 25. A maker's social pages (Instagram, TikTok, Facebook, a website): up to four https links.
--     Safe to run more than once. Everything is inside one transaction: if any line fails, nothing changes.
-- =====================================================================
begin;

alter table public.makers add column if not exists socials text[] not null default '{}';
alter table public.makers drop constraint if exists makers_socials_ck;
alter table public.makers add constraint makers_socials_ck check (
  cardinality(socials) <= 4
  and array_position(socials, null) is null
  and char_length(array_to_string(socials, ' ')) <= 1200
  and (cardinality(socials) = 0 or array_to_string(socials, ' ') ~ '^https://[^[:space:]]+( https://[^[:space:]]+)*$')
);
grant insert (socials) on public.makers to anon, authenticated;

create or replace view public.public_makers
  with (security_invoker = false)
as
  select id, name, city, craft, story, photos, portrait,
         case when phone_public then phone end as contact_phone,
         craft_other,
         case when email_public then email end as contact_email,
         crafts,
         reviews_url,
         theme,
         socials
  from public.makers
  where status = 'approved' and public.can_see_maker(id, is_test);

create or replace view public.my_maker
  with (security_invoker = false)
as
  select id, name, city, craft, craft_other, story, photos, portrait, phone_public, email_public, status, created_at, crafts, phone, reviews_url, theme, socials
  from public.makers
  where email is not null
    and lower(btrim(email)) = lower(btrim(coalesce(auth.jwt() ->> 'email', '')));

commit;
