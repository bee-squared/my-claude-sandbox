create table public.list_members (
  list_id uuid not null references public.lists (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role public.list_role not null default 'editor',
  invited_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (list_id, user_id)
);

create unique index list_members_one_owner_idx on public.list_members (list_id) where role = 'owner';
create index list_members_user_id_list_id_idx on public.list_members (user_id, list_id);
create index list_members_invited_by_idx on public.list_members (invited_by);
