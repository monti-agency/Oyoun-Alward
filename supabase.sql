-- ============================================================
--  عيون الورد للهدايا | Oyoun Al-Ward Gifts — admin panel backend
--  Run ONCE in Supabase → SQL Editor → New query → Run.
--  Safe to run again (idempotent).
--
--  BEFORE RUNNING: replace PUT-YOUR-EMAIL-HERE (line marked ★) with the
--  owner's login email — the same email you will add under
--  Authentication → Users → Add user (with a password, "Auto Confirm" on).
--  Only emails listed in site_admins can publish or upload images.
--  Also turn OFF "Allow new users to sign up" (Authentication → Sign In / Providers).
-- ============================================================

-- 1) Who is allowed to edit the site ------------------------------------
create table if not exists public.site_admins (
  email text primary key
);
alter table public.site_admins enable row level security;   -- no policies = invisible to the browser

insert into public.site_admins (email)
values (lower('PUT-YOUR-EMAIL-HERE'))                        -- ★ owner email
on conflict (email) do nothing;

create or replace function public.is_site_admin()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.site_admins
    where email = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;
revoke all on function public.is_site_admin() from public;
grant execute on function public.is_site_admin() to authenticated;

-- 2) Site content: products + settings (one JSON row each) --------------
--    keys used by admin.html / index.html:
--      oyoun_products  → the product list
--      oyoun_settings  → announcement bar text, WhatsApp number, Instagram handle
create table if not exists public.site_data (
  key        text primary key,
  value      jsonb not null,
  updated_at timestamptz not null default now()
);
alter table public.site_data enable row level security;

drop policy if exists "site_data read"         on public.site_data;
drop policy if exists "site_data admin insert" on public.site_data;
drop policy if exists "site_data admin update" on public.site_data;
drop policy if exists "site_data admin delete" on public.site_data;

-- everyone (the public website) can read
create policy "site_data read" on public.site_data
  for select to anon, authenticated using (true);

-- only the owner can write
create policy "site_data admin insert" on public.site_data
  for insert to authenticated with check (public.is_site_admin());
create policy "site_data admin update" on public.site_data
  for update to authenticated using (public.is_site_admin()) with check (public.is_site_admin());
create policy "site_data admin delete" on public.site_data
  for delete to authenticated using (public.is_site_admin());

grant select on public.site_data to anon, authenticated;
grant insert, update, delete on public.site_data to authenticated;

-- 3) Product photos bucket (public images, 5 MB max, JPG/PNG/WebP) ------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('oyoun-images', 'oyoun-images', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = true,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "oyoun-images read"         on storage.objects;
drop policy if exists "oyoun-images admin insert" on storage.objects;
drop policy if exists "oyoun-images admin update" on storage.objects;
drop policy if exists "oyoun-images admin delete" on storage.objects;

create policy "oyoun-images read" on storage.objects
  for select to anon, authenticated using (bucket_id = 'oyoun-images');

create policy "oyoun-images admin insert" on storage.objects
  for insert to authenticated with check (bucket_id = 'oyoun-images' and public.is_site_admin());
create policy "oyoun-images admin update" on storage.objects
  for update to authenticated using (bucket_id = 'oyoun-images' and public.is_site_admin())
  with check (bucket_id = 'oyoun-images' and public.is_site_admin());
create policy "oyoun-images admin delete" on storage.objects
  for delete to authenticated using (bucket_id = 'oyoun-images' and public.is_site_admin());
