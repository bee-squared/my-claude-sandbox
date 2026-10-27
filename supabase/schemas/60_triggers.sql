create or replace function private.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data ->> 'display_name',
      new.raw_user_meta_data ->> 'full_name',
      new.raw_user_meta_data ->> 'name'
    )
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

create trigger lists_touch_updated_at
  before update on public.lists
  for each row execute function private.touch_updated_at();

create or replace function private.add_owner_membership()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.list_members (list_id, user_id, role)
  values (new.id, new.owner_id, 'owner');
  return new;
end;
$$;

create trigger lists_add_owner_membership
  after insert on public.lists
  for each row execute function private.add_owner_membership();

create or replace function private.guard_owner_membership()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_owner uuid;
begin
  select l.owner_id into current_owner from public.lists l where l.id = old.list_id;

  if found and old.user_id = current_owner then
    if tg_op = 'DELETE' then
      if exists (select 1 from auth.users u where u.id = old.user_id) then
        raise exception 'list owner cannot be removed';
      end if;
    elsif new.role <> 'owner' then
      raise exception 'list owner cannot be downgraded';
    end if;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger list_members_guard_owner
  before update or delete on public.list_members
  for each row execute function private.guard_owner_membership();

create or replace function private.check_owner_role()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.role = 'owner' and new.user_id is distinct from
     (select l.owner_id from public.lists l where l.id = new.list_id) then
    raise exception 'only the list owner can have the owner role';
  end if;
  return new;
end;
$$;

create trigger list_members_owner_role_check
  before insert or update of role on public.list_members
  for each row execute function private.check_owner_role();

create or replace function private.normalize_custom_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  builtin_sort smallint;
begin
  if new.owner_id is null then
    return new;
  end if;

  new.label := btrim(new.label);

  if exists (
    select 1 from public.task_statuses s
    where s.owner_id is null and lower(s.label) = lower(new.label)
  ) then
    raise exception 'status label matches a built-in status';
  end if;

  if tg_op = 'INSERT' and new.sort_order is null then
    select s.sort_order + 1 into builtin_sort
    from public.task_statuses s
    where s.owner_id is null and s.behavior = new.behavior;
    new.sort_order := builtin_sort;
  end if;

  return new;
end;
$$;

create trigger task_statuses_normalize
  before insert or update of label, behavior, sort_order on public.task_statuses
  for each row execute function private.normalize_custom_status();

create or replace function private.default_task_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status_id is null then
    select s.id into new.status_id
    from public.task_statuses s
    where s.owner_id is null and s.behavior = 'todo';
  end if;
  return new;
end;
$$;

create trigger tasks_10_default_status
  before insert on public.tasks
  for each row execute function private.default_task_status();

create or replace function private.check_task_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Signed-in non-editors are rejected by RLS; skipping here avoids leaking membership.
  if (select auth.uid()) is not null
     and not private.has_list_role(new.list_id, 'editor') then
    return new;
  end if;

  if tg_op = 'INSERT'
     or new.status_id is distinct from old.status_id
     or new.list_id is distinct from old.list_id then
    if not private.status_usable_in_list(new.status_id, new.list_id) then
      raise exception 'status cannot be used in this list';
    end if;
  end if;

  if tg_op = 'INSERT' or new.status_id is distinct from old.status_id then
    if exists (
      select 1 from public.task_statuses s
      where s.id = new.status_id and s.archived_at is not null
    ) then
      raise exception 'archived status cannot be chosen';
    end if;
  end if;

  return new;
end;
$$;

create trigger tasks_20_check_status
  before insert or update of status_id, list_id on public.tasks
  for each row execute function private.check_task_status();

create or replace function private.check_task_assignee()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Signed-in non-editors are rejected by RLS; skipping here avoids leaking membership.
  if (select auth.uid()) is not null
     and not private.has_list_role(new.list_id, 'editor') then
    return new;
  end if;

  if new.assignee_id is not null and not exists (
    select 1 from public.list_members m
    where m.list_id = new.list_id and m.user_id = new.assignee_id
  ) then
    raise exception 'assignee must be a member of the list';
  end if;
  return new;
end;
$$;

create trigger tasks_30_check_assignee
  before insert or update of assignee_id, list_id on public.tasks
  for each row execute function private.check_task_assignee();

create trigger tasks_90_touch_updated_at
  before update on public.tasks
  for each row execute function private.touch_updated_at();

create or replace function private.clear_removed_member_assignments()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.tasks t
  set assignee_id = null
  where t.list_id = old.list_id and t.assignee_id = old.user_id;
  return old;
end;
$$;

create trigger list_members_clear_assignments
  after delete on public.list_members
  for each row execute function private.clear_removed_member_assignments();
