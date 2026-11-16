-- The card queue migration includes the final cancellation field and paired-answer progression.
alter table public.remote_round_cards add column if not exists cancelled boolean not null default false;
