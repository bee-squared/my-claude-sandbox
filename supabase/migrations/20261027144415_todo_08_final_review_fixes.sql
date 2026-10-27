SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION private.can_read_status (
  status_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION private.check_task_assignee()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  -- Signed-in non-editors are rejected by RLS; skipping here avoids leaking membership.
  if (select auth.uid()) is not null
     and not private.has_list_role(new.list_id, 'editor') then
    return new;
  end if;

  if new.assignee_id is not null then
    -- for key share blocks a concurrent leave (delete) of the assignee's membership row.
    perform 1
    from public.list_members m
    where m.list_id = new.list_id and m.user_id = new.assignee_id
    for key share;

    if not found then
      raise exception 'assignee must be a member of the list';
    end if;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.transfer_list_ownership (
  list_id   uuid,
  new_owner uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;
