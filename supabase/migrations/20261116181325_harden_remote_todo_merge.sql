-- Preserve the strongest shared wish state and make simultaneous realization proposals idempotent.
create or replace function public.sync_remote_todo(p_card_id text,p_status text,p_done boolean default false,p_source text default null)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare v_uid uuid:=auth.uid();v_couple uuid;v_row public.remote_todo_states%rowtype;
begin
 if v_uid is null then raise exception 'Authentification requise'; end if;
 if nullif(trim(p_card_id),'') is null or p_status is null or p_status not in ('accepted','curious','unlocked') then raise exception 'Envie invalide'; end if;
 select cm.couple_id into v_couple from public.couple_members cm where cm.user_id=v_uid;
 if v_couple is null then raise exception 'Couple introuvable'; end if;
 insert into public.remote_todo_states(couple_id,card_id,status,source,done,completed_at,updated_by,updated_at)
 values(v_couple,p_card_id,p_status,p_source,coalesce(p_done,false),case when p_done then now() else null end,v_uid,now())
 on conflict(couple_id,card_id) do update set
 status=case when excluded.status='accepted' or public.remote_todo_states.status='accepted' then 'accepted'
 when excluded.status='unlocked' or public.remote_todo_states.status='unlocked' then 'unlocked' else 'curious' end,
 source=coalesce(excluded.source,public.remote_todo_states.source),done=public.remote_todo_states.done or excluded.done,
 completed_at=case when public.remote_todo_states.done or excluded.done then coalesce(public.remote_todo_states.completed_at,excluded.completed_at,now()) else null end,
 updated_by=v_uid,updated_at=now() returning * into v_row;
 return jsonb_build_object('card_id',v_row.card_id,'status',v_row.status,'source',v_row.source,'done',v_row.done,'completed_at',v_row.completed_at);
end;
$function$;
revoke all on function public.sync_remote_todo(text,text,boolean,text) from public,anon;
grant execute on function public.sync_remote_todo(text,text,boolean,text) to authenticated;
create or replace function public.append_remote_todo_proposal(p_round_id uuid,p_card_id text,p_category text)
returns text language plpgsql security definer set search_path=''
as $function$
declare v_uid uuid:=auth.uid();v_couple uuid;v_status text;v_position integer;
begin
 if v_uid is null then raise exception 'Authentification requise'; end if;
 if nullif(trim(p_category),'') is null then raise exception 'Catégorie invalide'; end if;
 select r.couple_id into v_couple from public.remote_rounds r where r.id=p_round_id for update;
 if not found or not exists(select 1 from public.couple_members cm where cm.couple_id=v_couple and cm.user_id=v_uid) then raise exception 'Partie introuvable ou accès refusé'; end if;
 if (select r.status from public.remote_rounds r where r.id=p_round_id)<>'playing' then raise exception 'La partie est terminée'; end if;
 select t.status into v_status from public.remote_todo_states t where t.couple_id=v_couple and t.card_id=p_card_id and not t.done;
 if v_status is null or v_status not in ('unlocked','curious') then raise exception 'Cette réalisation ne peut pas être proposée pour le moment'; end if;
 if exists(select 1 from public.remote_round_cards c where c.round_id=p_round_id and c.card_id=p_card_id and c.card_type='todo_proposal') then return p_card_id; end if;
 if exists(select 1 from public.remote_round_cards c where c.round_id=p_round_id and c.card_id=p_card_id) then raise exception 'Cette carte a déjà été utilisée dans cette partie'; end if;
 select coalesce(max(c.position),-1)+1 into v_position from public.remote_round_cards c where c.round_id=p_round_id;
 insert into public.remote_round_cards(round_id,card_id,position,card_type,theme_id,alternative_index,linked_realization_id,category_id,eligible)
 values(p_round_id,p_card_id,v_position,'todo_proposal',null,0,null,p_category,true);
 update public.remote_rounds set card_ids=card_ids||jsonb_build_array(p_card_id),updated_at=now() where id=p_round_id;
 return p_card_id;
end;
$function$;
revoke all on function public.append_remote_todo_proposal(uuid,text,text) from public,anon;
grant execute on function public.append_remote_todo_proposal(uuid,text,text) to authenticated;
