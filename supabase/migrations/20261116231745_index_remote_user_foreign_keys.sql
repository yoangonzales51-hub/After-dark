
create index if not exists remote_answers_user_id_idx on public.remote_answers(user_id);
create index if not exists remote_todo_completion_votes_user_id_idx on public.remote_todo_completion_votes(user_id);
