SET local check_function_bodies = off;

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

  if new.assignee_id is not null and not exists (
    select 1 from public.list_members m
    where m.list_id = new.list_id and m.user_id = new.assignee_id
  ) then
    raise exception 'assignee must be a member of the list';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.check_task_status()
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
$function$;
