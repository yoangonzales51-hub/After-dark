drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own on public.profiles
for insert to public
with check ((select auth.uid()) = id);

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
for update to public
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

drop policy if exists profiles_select_own_or_couple on public.profiles;
create policy profiles_select_own_or_couple on public.profiles
for select to authenticated
using (
  (select auth.uid()) = id
  or exists (
    select 1
    from public.couple_members mine
    join public.couple_members theirs on theirs.couple_id = mine.couple_id
    where mine.user_id = (select auth.uid())
      and theirs.user_id = profiles.id
  )
);
