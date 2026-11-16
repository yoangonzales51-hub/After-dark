-- Remote card-by-card queue with per-card eligibility and paired-answer gating.
create table if not exists public.remote_round_cards (
  round_id uuid not null references public.remote_rounds(id) on delete cascade,
  card_id text not null,
  position integer not null,
  card_type text not null check (card_type in ('independent','discovery')),
  theme_id text,
  alternative_index integer not null default 0,
  linked_realization_id text,
  eligible boolean not null default false,
  completed_at timestamptz,
  cancelled boolean not null default false,
  primary key (round_id,card_id),
  unique (round_id,position)
);
create index if not exists remote_round_cards_available_idx on public.remote_round_cards(round_id,eligible,position);
alter table public.remote_round_cards enable row level security;
revoke all on public.remote_round_cards from public,anon,authenticated;

create or replace function public.create_remote_round_v2(p_cards jsonb)
returns uuid language plpgsql security definer set search_path=''
as $function$
declare v_uid uuid:=auth.uid(); v_couple uuid; v_round uuid; v_count integer; v_valid integer;
begin
 if v_uid is null then raise exception 'Authentification requise'; end if;
 if jsonb_typeof(p_cards)<>'array' or jsonb_array_length(p_cards)<1 or jsonb_array_length(p_cards)>500 then raise exception 'Sélection de cartes invalide'; end if;
 select cm.couple_id into v_couple from public.couple_members cm where cm.user_id=v_uid;
 if v_couple is null then raise exception 'Vous devez associer un couple'; end if;
 if (select count(*) from public.couple_members cm where cm.couple_id=v_couple)<>2 then raise exception 'Deux partenaires sont nécessaires'; end if;
 select count(*),count(distinct x.card_id) into v_count,v_valid from jsonb_to_recordset(p_cards) as x(card_id text,position integer,card_type text,theme_id text,alternative_index integer,linked_realization_id text);
 if v_count<>v_valid or exists(select 1 from jsonb_to_recordset(p_cards) as x(card_id text,position integer,card_type text,theme_id text,alternative_index integer,linked_realization_id text)
   where nullif(trim(card_id),'') is null or position is null or position<0 or card_type not in ('independent','discovery') or (card_type='discovery' and nullif(theme_id,'') is null))
 then raise exception 'Métadonnées de cartes invalides ou dupliquées'; end if;
 insert into public.remote_rounds(couple_id,card_ids,current_index,status)
 select v_couple,coalesce(jsonb_agg(x.card_id order by x.position),'[]'::jsonb),0,'playing'
 from jsonb_to_recordset(p_cards) as x(card_id text,position integer,card_type text,theme_id text,alternative_index integer,linked_realization_id text)
 returning id into v_round;
 insert into public.remote_round_cards(round_id,card_id,position,card_type,theme_id,alternative_index,linked_realization_id,eligible)
 select v_round,x.card_id,x.position,x.card_type,x.theme_id,coalesce(x.alternative_index,0),x.linked_realization_id,
   (x.card_type='independent' or (x.card_type='discovery' and coalesce(x.alternative_index,0)=0))
 from jsonb_to_recordset(p_cards) as x(card_id text,position integer,card_type text,theme_id text,alternative_index integer,linked_realization_id text);
 return v_round;
end;
$function$;
revoke all on function public.create_remote_round_v2(jsonb) from public,anon;
grant execute on function public.create_remote_round_v2(jsonb) to authenticated;

create or replace function public.submit_remote_card_answer(p_round_id uuid,p_card_id text,p_answer text)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare
 v_uid uuid:=auth.uid(); v_couple uuid; v_partner uuid; v_answer text; v_existing text;
 v_card public.remote_round_cards%rowtype; v_a text; v_b text; v_completed boolean:=false;
 v_next text; v_total integer; v_done integer;
begin
 if v_uid is null then raise exception 'Authentification requise'; end if;
 v_answer:=case when p_answer='skip' then 'pass' else p_answer end;
 if v_answer not in ('yes','no','maybe','pass') then raise exception 'Réponse invalide'; end if;
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
  if v_card.card_type='discovery' then
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

create or replace function public.remote_round_state_v2(p_round_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare v_uid uuid:=auth.uid(); v_couple uuid; v_partner uuid; v_status text; v_cards jsonb; v_total integer; v_done integer;
begin
 if v_uid is null then raise exception 'Authentification requise'; end if;
 select r.couple_id,r.status into v_couple,v_status from public.remote_rounds r where r.id=p_round_id;
 if not found or not exists(select 1 from public.couple_members cm where cm.couple_id=v_couple and cm.user_id=v_uid) then raise exception 'Partie distante introuvable ou accès refusé'; end if;
 select cm.user_id into v_partner from public.couple_members cm where cm.couple_id=v_couple and cm.user_id<>v_uid limit 1;
 if v_partner is null then raise exception 'Deux partenaires sont nécessaires'; end if;
 select count(*) into v_total from public.remote_round_cards c where c.round_id=p_round_id;
 select count(*) into v_done from public.remote_round_cards c where c.round_id=p_round_id and (c.completed_at is not null or c.cancelled);
 select coalesce(jsonb_agg(jsonb_build_object(
  'card_id',c.card_id,'position',c.position,'card_type',c.card_type,'theme_id',c.theme_id,'alternative_index',c.alternative_index,
  'linked_realization_id',c.linked_realization_id,'eligible',c.eligible,'completed',c.completed_at is not null,'cancelled',c.cancelled,
  'my_answer',(select a.answer from public.remote_answers a where a.round_id=p_round_id and a.user_id=v_uid and a.card_id=c.card_id),
  'partner_answered',exists(select 1 from public.remote_answers a where a.round_id=p_round_id and a.user_id=v_partner and a.card_id=c.card_id),
  'partner_answer',(select a.answer from public.remote_answers a where a.round_id=p_round_id and a.user_id=v_partner and a.card_id=c.card_id and exists(select 1 from public.remote_answers own where own.round_id=p_round_id and own.user_id=v_uid and own.card_id=c.card_id))
 ) order by c.position),'[]'::jsonb) into v_cards from public.remote_round_cards c where c.round_id=p_round_id;
 return jsonb_build_object('status',v_status,'total',v_total,'completed_count',v_done,'cards',v_cards);
end;
$function$;
revoke all on function public.remote_round_state_v2(uuid) from public,anon;
grant execute on function public.remote_round_state_v2(uuid) to authenticated;
