create or replace function public.transfer_list_ownership(list_id uuid, new_owner uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_owner uuid;
  promoted integer;
begin
  select l.owner_id into current_owner
  from public.lists l
  where l.id = transfer_list_ownership.list_id
  for update;

  if current_owner is distinct from (select auth.uid()) then
    raise exception 'only the list owner can transfer ownership';
  end if;

  if transfer_list_ownership.new_owner = current_owner then
    return;
  end if;

  -- Lock the target's membership row so a concurrent leave blocks until we commit.
  perform 1
  from public.list_members m
  where m.list_id = transfer_list_ownership.list_id
    and m.user_id = transfer_list_ownership.new_owner
  for update;

  if not found then
    raise exception 'new owner must already be a member of the list';
  end if;

  update public.lists l
  set owner_id = transfer_list_ownership.new_owner
  where l.id = transfer_list_ownership.list_id;

  update public.list_members m
  set role = 'editor'
  where m.list_id = transfer_list_ownership.list_id
    and m.user_id = current_owner;

  update public.list_members m
  set role = 'owner'
  where m.list_id = transfer_list_ownership.list_id
    and m.user_id = transfer_list_ownership.new_owner;

  get diagnostics promoted = row_count;
  if promoted <> 1 then
    raise exception 'new owner must already be a member of the list';
  end if;
end;
$$;
