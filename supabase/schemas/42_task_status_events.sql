create table public.task_status_events (
  id bigint generated always as identity primary key,
  task_id uuid not null references public.tasks (id) on delete cascade,
  from_status_id uuid references public.task_statuses (id) on delete no action,
  to_status_id uuid not null references public.task_statuses (id) on delete no action,
  from_behavior public.status_behavior,
  to_behavior public.status_behavior not null,
  changed_by uuid default auth.uid() references auth.users (id) on delete set null,
  changed_at timestamptz not null default now()
);

create index task_status_events_task_changed_idx on public.task_status_events (task_id, changed_at);
create index task_status_events_from_status_id_idx on public.task_status_events (from_status_id);
create index task_status_events_to_status_id_idx on public.task_status_events (to_status_id);
create index task_status_events_changed_by_idx on public.task_status_events (changed_by);
