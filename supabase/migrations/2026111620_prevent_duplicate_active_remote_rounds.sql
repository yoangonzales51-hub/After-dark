-- Prevent both partners from creating separate active rounds at the same time.
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
 perform pg_advisory_xact_lock(hashtext(v_couple::text));
 select r.id into v_round from public.remote_rounds r where r.couple_id=v_couple and r.status='playing' order by r.created_at desc limit 1;
 if v_round is not null then return v_round; end if;
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
