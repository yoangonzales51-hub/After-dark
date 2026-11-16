
create or replace function public.confirm_remote_todo_done(p_card_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_couple uuid;
  v_partner uuid;
  v_confirmations integer;
  v_partner_confirmed boolean := false;
  v_done boolean := false;
begin
  if v_uid is null then raise exception 'Authentification requise'; end if;
  if nullif(trim(p_card_id),'') is null then raise exception 'Réalisation invalide'; end if;

  select cm.couple_id into v_couple
  from public.couple_members cm where cm.user_id=v_uid;
  if v_couple is null then raise exception 'Couple introuvable'; end if;

  select cm.user_id into v_partner
  from public.couple_members cm
  where cm.couple_id=v_couple and cm.user_id<>v_uid
  limit 1;
  if v_partner is null or (select count(*) from public.couple_members cm where cm.couple_id=v_couple)<>2 then
    raise exception 'Deux partenaires sont nécessaires';
  end if;

  perform 1
  from public.remote_todo_states t
  where t.couple_id=v_couple and t.card_id=p_card_id and t.status='accepted'
  for update;
  if not found then
    raise exception 'Cette réalisation doit d’abord être acceptée à deux';
  end if;

  insert into public.remote_todo_completion_votes(couple_id,card_id,user_id,confirmed,updated_at)
  values(v_couple,p_card_id,v_uid,true,now())
  on conflict(couple_id,card_id,user_id)
  do update set confirmed=true,updated_at=now();

  select count(*) into v_confirmations
  from public.remote_todo_completion_votes v
  join public.couple_members cm
    on cm.couple_id=v.couple_id and cm.user_id=v.user_id
  where v.couple_id=v_couple and v.card_id=p_card_id and v.confirmed=true;

  select coalesce(v.confirmed,false) into v_partner_confirmed
  from public.remote_todo_completion_votes v
  where v.couple_id=v_couple and v.card_id=p_card_id and v.user_id=v_partner;
  v_partner_confirmed:=coalesce(v_partner_confirmed,false);
  v_done:=v_confirmations=2;

  update public.remote_todo_states
  set done=v_done,
      completed_at=case when v_done then coalesce(completed_at,now()) else null end,
      updated_by=v_uid,
      updated_at=now()
  where couple_id=v_couple and card_id=p_card_id;

  return jsonb_build_object(
    'card_id',p_card_id,
    'done',v_done,
    'my_confirmed',true,
    'partner_confirmed',v_partner_confirmed,
    'confirmations',v_confirmations
  );
end;
$function$;
