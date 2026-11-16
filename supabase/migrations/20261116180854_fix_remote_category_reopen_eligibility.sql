-- Harden category-reopen payloads and keep alternate discoveries locked until their predecessor is answered.
create or replace function public.append_remote_category_reopen(p_round_id uuid,p_category text,p_cards jsonb)
returns text language plpgsql security definer set search_path=''
as $function$
declare v_uid uuid:=auth.uid(); v_couple uuid; v_verify_id text; v_position integer; v_count integer; v_valid integer;
begin
 if v_uid is null then raise exception 'Authentification requise'; end if;
 if nullif(trim(p_category),'') is null then raise exception 'Catégorie invalide'; end if;
 if p_cards is null or jsonb_typeof(p_cards) is distinct from 'array' then raise exception 'Cartes de la catégorie invalides'; end if;
 if jsonb_array_length(p_cards)<1 or jsonb_array_length(p_cards)>300 then raise exception 'Cartes de la catégorie invalides'; end if;
 select r.couple_id into v_couple from public.remote_rounds r where r.id=p_round_id for update;
 if not found or not exists(select 1 from public.couple_members cm where cm.couple_id=v_couple and cm.user_id=v_uid) then raise exception 'Partie introuvable ou accès refusé'; end if;
 if (select r.status from public.remote_rounds r where r.id=p_round_id)<>'playing' then raise exception 'La partie est terminée'; end if;
 v_verify_id:='__REOPEN__:'||md5(p_category);
 if exists(select 1 from public.remote_round_cards c where c.round_id=p_round_id and c.card_id=v_verify_id) then
  update public.remote_round_cards set eligible=true where round_id=p_round_id and card_id=v_verify_id and completed_at is null;
  return v_verify_id;
 end if;
 select count(*),count(distinct x.card_id) into v_count,v_valid from jsonb_to_recordset(p_cards) as x(card_id text,card_type text,theme_id text,alternative_index integer,linked_realization_id text,category_id text);
 if v_count<>v_valid or exists(select 1 from jsonb_to_recordset(p_cards) as x(card_id text,card_type text,theme_id text,alternative_index integer,linked_realization_id text,category_id text)
  where nullif(trim(card_id),'') is null or card_type is null or card_type not in ('independent','discovery') or x.category_id is distinct from p_category or (card_type='discovery' and nullif(theme_id,'') is null))
 then raise exception 'Métadonnées de cartes invalides'; end if;
 if exists(select 1 from jsonb_to_recordset(p_cards) x(card_id text,card_type text,theme_id text,alternative_index integer,linked_realization_id text,category_id text)
   join public.remote_round_cards c on c.round_id=p_round_id and c.card_id=x.card_id) then raise exception 'Cette catégorie est déjà présente dans la partie'; end if;
 select coalesce(max(c.position),-1)+1 into v_position from public.remote_round_cards c where c.round_id=p_round_id;
 insert into public.remote_round_cards(round_id,card_id,position,card_type,theme_id,alternative_index,linked_realization_id,category_id,eligible)
 values(p_round_id,v_verify_id,v_position,'category_verification',p_category,0,null,p_category,true);
 insert into public.remote_round_cards(round_id,card_id,position,card_type,theme_id,alternative_index,linked_realization_id,category_id,eligible)
 select p_round_id,x.card_id,v_position+row_number() over(order by coalesce(x.theme_id,''),coalesce(x.alternative_index,0),x.card_id),x.card_type,x.theme_id,coalesce(x.alternative_index,0),x.linked_realization_id,x.category_id,false
 from jsonb_to_recordset(p_cards) as x(card_id text,card_type text,theme_id text,alternative_index integer,linked_realization_id text,category_id text);
 update public.remote_rounds set card_ids=card_ids||coalesce((select jsonb_agg(x.card_id) from jsonb_to_recordset(p_cards) x(card_id text,card_type text,theme_id text,alternative_index integer,linked_realization_id text,category_id text)),'[]'::jsonb),updated_at=now() where id=p_round_id;
 return v_verify_id;
end;
$function$;
revoke all on function public.append_remote_category_reopen(uuid,text,jsonb) from public,anon;
grant execute on function public.append_remote_category_reopen(uuid,text,jsonb) to authenticated;

create or replace function public.submit_remote_card_answer(p_round_id uuid,p_card_id text,p_answer text)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare v_uid uuid:=auth.uid(); v_couple uuid; v_partner uuid; v_answer text; v_existing text; v_card public.remote_round_cards%rowtype; v_a text; v_b text; v_completed boolean:=false; v_next text; v_total integer; v_done integer;
begin
 if v_uid is null then raise exception 'Authentification requise'; end if;
 v_answer:=case when p_answer='skip' then 'pass' else p_answer end;
 if v_answer is null or v_answer not in ('yes','no','maybe','pass') then raise exception 'Réponse invalide'; end if;
 select r.couple_id into v_couple from public.remote_rounds r where r.id=p_round_id for update;
 if not found or not exists(select 1 from public.couple_members cm where cm.couple_id=v_couple and cm.user_id=v_uid) then raise exception 'Partie introuvable ou accès refusé'; end if;
 select cm.user_id into v_partner from public.couple_members cm where cm.couple_id=v_couple and cm.user_id<>v_uid limit 1;
 if v_partner is null then raise exception 'Deux partenaires sont nécessaires'; end if;
 select * into v_card from public.remote_round_cards c where c.round_id=p_round_id and c.card_id=p_card_id for update;
 if not found or v_card.cancelled then raise exception 'Carte inconnue ou indisponible'; end if;
 select a.answer into v_existing from public.remote_answers a where a.round_id=p_round_id and a.user_id=v_uid and a.card_id=p_card_id;
 if found then
  if v_existing not in (v_answer,case when v_answer='pass' then 'skip' else v_answer end) then raise exception 'Une réponse a déjà été enregistrée pour cette carte'; end if;
  select exists(select 1 from public.remote_answers a where a.round_id=p_round_id and a.user_id=v_partner and a.card_id=p_card_id) into v_completed;
  return jsonb_build_object('saved',true,'duplicate',true,'card_completed',v_completed,'waiting_for_partner',not v_completed);
 end if;
 if not v_card.eligible then raise exception 'Cette carte n’est pas encore disponible'; end if;
 if (select r.status from public.remote_rounds r where r.id=p_round_id)<>'playing' then raise exception 'Cette partie est terminée'; end if;
 insert into public.remote_answers(round_id,user_id,card_id,answer) values(p_round_id,v_uid,p_card_id,v_answer);
 select a.answer into v_a from public.remote_answers a where a.round_id=p_round_id and a.user_id=v_uid and a.card_id=p_card_id;
 select a.answer into v_b from public.remote_answers a where a.round_id=p_round_id and a.user_id=v_partner and a.card_id=p_card_id;
 v_completed:=v_b is not null;
 if v_completed then
  update public.remote_round_cards set completed_at=coalesce(completed_at,now()) where round_id=p_round_id and card_id=p_card_id;
  if v_card.card_type='category_verification' then
   if v_a='yes' and v_b='yes' then
    update public.remote_round_cards set eligible=(card_type='independent' or (card_type='discovery' and alternative_index=0)) where round_id=p_round_id and category_id=v_card.category_id and card_type<>'category_verification';
   else
    update public.remote_round_cards set cancelled=true where round_id=p_round_id and category_id=v_card.category_id and card_type<>'category_verification';
   end if;
  elsif v_card.card_type='discovery' then
   if (v_a='yes' and v_b in ('yes','maybe')) or (v_b='yes' and v_a in ('yes','maybe')) then
    update public.remote_round_cards set cancelled=true where round_id=p_round_id and card_type='discovery' and theme_id=v_card.theme_id and alternative_index>v_card.alternative_index and completed_at is null;
   else
    select c.card_id into v_next from public.remote_round_cards c where c.round_id=p_round_id and c.card_type='discovery' and c.theme_id=v_card.theme_id and c.alternative_index>v_card.alternative_index and c.completed_at is null and not c.cancelled order by c.alternative_index limit 1;
    if v_next is not null then update public.remote_round_cards set eligible=true where round_id=p_round_id and card_id=v_next; end if;
   end if;
  end if;
 end if;
 select count(*) into v_total from public.remote_round_cards c where c.round_id=p_round_id;
 select count(*) into v_done from public.remote_round_cards c where c.round_id=p_round_id and (c.completed_at is not null or c.cancelled);
 update public.remote_rounds set updated_at=now(),status=case when v_done=v_total then 'completed' else status end,completed_at=case when v_done=v_total then coalesce(completed_at,now()) else completed_at end where id=p_round_id;
 return jsonb_build_object('saved',true,'duplicate',false,'card_completed',v_completed,'waiting_for_partner',not v_completed,'completed_cards',v_done,'total_cards',v_total,'round_completed',v_done=v_total);
end;
$function$;
revoke all on function public.submit_remote_card_answer(uuid,text,text) from public,anon;
grant execute on function public.submit_remote_card_answer(uuid,text,text) to authenticated;
