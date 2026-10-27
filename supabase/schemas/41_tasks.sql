create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  list_id uuid not null references public.lists (id) on delete cascade,
  title text not null,
  description text,
  status_id uuid not null references public.task_statuses (id) on delete no action,
  position double precision not null default 0,
  priority smallint,
  assignee_id uuid references auth.users (id) on delete set null,
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  blocked_reason text,
  due_at timestamptz,
  status_changed_at timestamptz not null default now(),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tasks_title_length check (char_length(btrim(title)) between 1 and 500),
  constraint tasks_priority_range check (priority between 1 and 3)
);

create index tasks_list_status_position_idx on public.tasks (list_id, status_id, position);
create index tasks_status_id_idx on public.tasks (status_id);
create index tasks_assignee_id_idx on public.tasks (assignee_id);
create index tasks_created_by_idx on public.tasks (created_by);
