-- These legacy RPCs are not called by the current AFTER DARK client.
-- Keep the active v2 remote-play endpoints and couple lifecycle functions available.
revoke execute on function public.answer_category_reopen_request(uuid,text) from public, anon, authenticated;
revoke execute on function public.create_category_reopen_request(text) from public, anon, authenticated;
revoke execute on function public.create_game_session() from public, anon, authenticated;
revoke execute on function public.create_remote_round(jsonb) from public, anon, authenticated;
revoke execute on function public.get_remote_reveal(uuid) from public, anon, authenticated;
revoke execute on function public.get_revealed_answers(uuid,text) from public, anon, authenticated;
revoke execute on function public.get_round_answers(text) from public, anon, authenticated;
revoke execute on function public.join_couple(text,text) from public, anon, authenticated;
revoke execute on function public.remote_round_state(uuid) from public, anon, authenticated;
revoke execute on function public.save_game_state(jsonb) from public, anon, authenticated;
revoke execute on function public.submit_answer(text,text,text) from public, anon, authenticated;
revoke execute on function public.submit_remote_answer_async(uuid,text,text) from public, anon, authenticated;
