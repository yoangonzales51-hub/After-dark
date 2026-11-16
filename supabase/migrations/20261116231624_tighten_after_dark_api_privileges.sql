-- Remove direct API access to tables that are only accessed through guarded RPCs.
revoke all on table public.couple_invites from anon, authenticated;
revoke all on table public.custom_cards from anon, authenticated;
revoke insert, update, delete on table public.remote_rounds from anon, authenticated;
grant select on table public.remote_rounds to authenticated;

-- Remove duplicate permissive policies while retaining the authenticated member checks.
drop policy if exists "members can read couple members" on public.couple_members;
drop policy if exists "members can read their couple" on public.couples;
drop policy if exists "remote_answers_own_select" on public.remote_answers;

-- Harden the active couple/invitation authorization functions against search_path changes.
alter function public.is_couple_member(uuid) set search_path = '';
alter function public.create_couple(text) set search_path = '';
alter function public.create_invite() set search_path = '';
alter function public.join_couple(text) set search_path = '';
