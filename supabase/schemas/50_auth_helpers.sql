create or replace function public.is_terminal(b public.status_behavior)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select b in ('completed'::public.status_behavior, 'cancelled'::public.status_behavior);
$$;

revoke execute on function public.is_terminal(public.status_behavior) from public, anon;
grant execute on function public.is_terminal(public.status_behavior) to authenticated;

create or replace function private.list_role_of(list_id uuid)
returns public.list_role
language sql
stable
security definer
set search_path = ''
as $$
  select m.role
  from public.list_members m
  where m.list_id = $1
    and m.user_id = (select auth.uid());
$$;

create or replace function private.has_list_role(list_id uuid, min_role public.list_role)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(private.list_role_of($1) >= $2, false);
$$;

create or replace function private.shares_list_with(other_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.list_members mine
    join public.list_members theirs on theirs.list_id = mine.list_id
    where mine.user_id = (select auth.uid())
      and theirs.user_id = $1
  );
$$;

revoke execute on function private.list_role_of(uuid) from public, anon;
revoke execute on function private.has_list_role(uuid, public.list_role) from public, anon;
revoke execute on function private.shares_list_with(uuid) from public, anon;
grant execute on function private.list_role_of(uuid) to authenticated;
grant execute on function private.has_list_role(uuid, public.list_role) to authenticated;
grant execute on function private.shares_list_with(uuid) to authenticated;

create or replace function private.can_read_status(status_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.task_statuses s
    where s.id = $1
      and (
        s.owner_id is null
        or s.owner_id = (select auth.uid())
        or private.shares_list_with(s.owner_id)
        or exists (
          select 1
          from public.tasks t
          where t.status_id = s.id
            and private.has_list_role(t.list_id, 'viewer')
        )
      )
  );
$$;

revoke execute on function private.can_read_status(uuid) from public, anon;
grant execute on function private.can_read_status(uuid) to authenticated;

create or replace function private.status_usable_in_list(status_id uuid, list_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.task_statuses s
    where s.id = $1
      and (
        s.owner_id is null
        or exists (
          select 1
          from public.list_members m
          where m.list_id = $2
            and m.user_id = s.owner_id
            and m.role >= 'editor'
        )
      )
  );
$$;

revoke execute on function private.status_usable_in_list(uuid, uuid) from public, anon;
grant execute on function private.status_usable_in_list(uuid, uuid) to authenticated;
