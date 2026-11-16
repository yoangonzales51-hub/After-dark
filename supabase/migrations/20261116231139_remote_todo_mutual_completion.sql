
create table if not exists public.remote_todo_completion_votes (
  couple_id uuid not null references public.couples(id) on delete cascade,
  card_id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  confirmed boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (couple_id, card_id, user_id)
);

alter table public.remote_todo_completion_votes enable row level security;
revoke all on table public.remote_todo_completion_votes from anon, authenticated;

create or replace function public.sync_remote_todo(
  p_card_id text,
  p_status text,
  p_done boolean default false,
  p_source text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_couple uuid;
  v_row public.remote_todo_states%rowtype;
begin
  if v_uid is null then raise exception 'Authentification requise'; end if;
  if nullif(trim(p_card_id),'') is null or p_status is null or p_status not in ('accepted','curious','unlocked') then
    raise exception 'Envie invalide';
  end if;
  select cm.couple_id into v_couple
  from public.couple_members cm where cm.user_id=v_uid;
  if v_couple is null then raise exception 'Couple introuvable'; end if;

  insert into public.remote_todo_states(couple_id,card_id,status,source,done,completed_at,updated_by,updated_at)
  values(v_couple,p_card_id,p_status,p_source,false,null,v_uid,now())
  on conflict(couple_id,card_id) do update set
    status=case
      when excluded.status='accepted' or public.remote_todo_states.status='accepted' then 'accepted'
      when excluded.status='unlocked' or public.remote_todo_states.status='unlocked' then 'unlocked'
      else 'curious' end,
    source=coalesce(excluded.source,public.remote_todo_states.source),
    done=public.remote_todo_states.done,
    completed_at=public.remote_todo_states.completed_at,
    updated_by=v_uid,
    updated_at=now()
  returning * into v_row;

  return jsonb_build_object(
    'card_id',v_row.card_id,'status',v_row.status,'source',v_row.source,
    'done',v_row.done,'completed_at',v_row.completed_at
  );
end;
$function$;

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

  if not exists (
    select 1 from public.remote_todo_states t
    where t.couple_id=v_couple and t.card_id=p_card_id and t.status='accepted'
  ) then
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

create or replace function public.get_remote_todos()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_couple uuid;
  v_result jsonb;
begin
  if v_uid is null then raise exception 'Authentification requise'; end if;
  select cm.couple_id into v_couple
  from public.couple_members cm where cm.user_id=v_uid;
  if v_couple is null then raise exception 'Couple introuvable'; end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'card_id',t.card_id,
        'status',t.status,
        'source',t.source,
        'done',t.done,
        'completed_at',t.completed_at,
        'my_done_vote',coalesce(mine.confirmed,false),
        'partner_done_vote',coalesce(partner.confirmed,false)
      ) order by t.updated_at
    ),
    '[]'::jsonb
  )
  into v_result
  from public.remote_todo_states t
  left join public.remote_todo_completion_votes mine
    on mine.couple_id=t.couple_id and mine.card_id=t.card_id and mine.user_id=v_uid
  left join public.couple_members partner_member
    on partner_member.couple_id=t.couple_id and partner_member.user_id<>v_uid
  left join public.remote_todo_completion_votes partner
    on partner.couple_id=t.couple_id and partner.card_id=t.card_id and partner.user_id=partner_member.user_id
  where t.couple_id=v_couple;

  return v_result;
end;
$function$;

revoke all on function public.confirm_remote_todo_done(text) from public, anon;
grant execute on function public.confirm_remote_todo_done(text) to authenticated;
