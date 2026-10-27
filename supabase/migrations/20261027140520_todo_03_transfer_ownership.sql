SET local check_function_bodies = off;

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

  if not exists (
    select 1 from public.list_members m
    where m.list_id = transfer_list_ownership.list_id
      and m.user_id = transfer_list_ownership.new_owner
  ) then
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
end;
$function$;

REVOKE ALL ON FUNCTION "public"."transfer_list_ownership"(uuid, uuid) FROM PUBLIC, "anon";

GRANT EXECUTE ON FUNCTION "public"."transfer_list_ownership"(uuid, uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."transfer_list_ownership"(uuid, uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."transfer_list_ownership"(uuid, uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."transfer_list_ownership"(uuid, uuid) TO "service_role";
