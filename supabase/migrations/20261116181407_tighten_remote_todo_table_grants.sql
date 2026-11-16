-- Expose read access only to authenticated couple members; all writes go through guarded RPCs.
revoke all on public.remote_todo_states from public,anon,authenticated;
grant select on public.remote_todo_states to authenticated;
