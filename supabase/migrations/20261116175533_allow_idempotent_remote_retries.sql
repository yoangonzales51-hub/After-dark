-- Preserve idempotent retries after the round is marked completed.
create or replace function public.submit_remote_answer_async(
  p_round_id uuid, p_card_id text, p_answer text
) returns jsonb
language plpgsql security definer set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_couple uuid; v_ids jsonb; v_partner uuid; v_existing text;
  v_card_completed boolean := false; v_round_completed boolean := false;
  v_total integer; v_completed integer;
  v_answer text := case when p_answer = 'skip' then 'pass' else p_answer end;
begin
  if v_uid is null then raise exception 'Authentification requise'; end if;
  if v_answer is null or v_answer not in ('yes','no','maybe','pass') then raise exception 'Réponse invalide'; end if;
  select r.couple_id,r.card_ids into v_couple,v_ids from public.remote_rounds r where r.id=p_round_id for update;
  if not found or not exists(select 1 from public.couple_members cm where cm.couple_id=v_couple and cm.user_id=v_uid)
    then raise exception 'Partie introuvable ou accès refusé'; end if;
  if not exists(select 1 from jsonb_array_elements_text(v_ids) x(card_id) where x.card_id=p_card_id)
    then raise exception 'Cette carte ne fait pas partie de cette partie'; end if;
  select cm.user_id into v_partner from public.couple_members cm where cm.couple_id=v_couple and cm.user_id<>v_uid limit 1;
  if v_partner is null then raise exception 'Deux partenaires sont nécessaires'; end if;
  select a.answer into v_existing from public.remote_answers a where a.round_id=p_round_id and a.user_id=v_uid and a.card_id=p_card_id;
  if found then
    if v_existing not in (v_answer,case when v_answer='pass' then 'skip' else v_answer end)
      then raise exception 'Une réponse a déjà été enregistrée pour cette carte'; end if;
    select exists(select 1 from public.remote_answers a where a.round_id=p_round_id and a.user_id=v_partner and a.card_id=p_card_id) into v_card_completed;
    return jsonb_build_object('saved',true,'duplicate',true,'card_id',p_card_id,'card_completed',v_card_completed,'waiting_for_partner',not v_card_completed);
  end if;
  if (select r.status from public.remote_rounds r where r.id=p_round_id)<>'playing'
    then raise exception 'Cette partie est terminée'; end if;
  insert into public.remote_answers(round_id,user_id,card_id,answer) values(p_round_id,v_uid,p_card_id,v_answer);
  select count(*) into v_total from jsonb_array_elements_text(v_ids) x(card_id);
  select count(*) into v_completed from (
    select x.card_id from jsonb_array_elements_text(v_ids) x(card_id)
    join public.remote_answers a on a.round_id=p_round_id and a.card_id=x.card_id and a.user_id in(v_uid,v_partner)
    group by x.card_id having count(distinct a.user_id)=2
  ) done_cards;
  select exists(select 1 from public.remote_answers a where a.round_id=p_round_id and a.card_id=p_card_id and a.user_id=v_partner) into v_card_completed;
  v_round_completed:=v_completed=v_total;
  update public.remote_rounds set updated_at=now(),status=case when v_round_completed then 'completed' else status end,
    completed_at=case when v_round_completed then coalesce(completed_at,now()) else completed_at end where id=p_round_id;
  return jsonb_build_object('saved',true,'duplicate',false,'card_id',p_card_id,'card_completed',v_card_completed,
    'waiting_for_partner',not v_card_completed,'completed_cards',v_completed,'total_cards',v_total,'round_completed',v_round_completed);
end;
$function$;
revoke all on function public.submit_remote_answer_async(uuid,text,text) from public,anon;
grant execute on function public.submit_remote_answer_async(uuid,text,text) to authenticated;
