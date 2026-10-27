create table public.task_statuses (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references auth.users (id) on delete cascade,
  label text not null,
  behavior public.status_behavior not null,
  sort_order smallint not null,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  constraint task_statuses_label_length check (char_length(btrim(label)) between 1 and 50),
  constraint task_statuses_builtin_not_archived check (owner_id is not null or archived_at is null)
);

create unique index task_statuses_one_builtin_per_behavior_idx on public.task_statuses (behavior) where owner_id is null;
create unique index task_statuses_owner_label_idx on public.task_statuses (owner_id, lower(label)) nulls not distinct;
create index task_statuses_owner_id_idx on public.task_statuses (owner_id);
