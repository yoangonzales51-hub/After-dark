-- Remote round metadata is readable only by authenticated couple members.
revoke select on public.remote_rounds from anon;
