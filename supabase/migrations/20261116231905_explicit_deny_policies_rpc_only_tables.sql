-- Explicit restrictive deny rules make RPC-only tables stay private even if
-- a permissive policy is accidentally added later.
create policy couple_invites_deny_direct_api
on public.couple_invites as restrictive
for all to anon, authenticated
using (false) with check (false);

create policy custom_cards_deny_direct_api
on public.custom_cards as restrictive
for all to anon, authenticated
using (false) with check (false);

create policy remote_round_cards_deny_direct_api
on public.remote_round_cards as restrictive
for all to anon, authenticated
using (false) with check (false);

create policy remote_todo_completion_votes_deny_direct_api
on public.remote_todo_completion_votes as restrictive
for all to anon, authenticated
using (false) with check (false);
