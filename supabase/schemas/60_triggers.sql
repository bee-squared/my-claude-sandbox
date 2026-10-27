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
