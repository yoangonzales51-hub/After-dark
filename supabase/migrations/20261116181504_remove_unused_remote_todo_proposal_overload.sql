-- Remove an obsolete incomplete RPC overload; only the guarded three-argument proposal RPC is used.
drop function if exists public.append_remote_todo_proposal(uuid,text);
