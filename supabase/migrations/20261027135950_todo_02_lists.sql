SET local check_function_bodies = off;

DROP POLICY "profiles_select" ON "public"."profiles";

CREATE TABLE "public"."list_members" (
  "list_id"    uuid                     NOT NULL,
  "user_id"    uuid                     NOT NULL,
  "role"       public.list_role         NOT NULL DEFAULT 'editor'::public.list_role,
  "invited_by" uuid,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "list_members_pkey" PRIMARY KEY (list_id, user_id)
);

ALTER TABLE "public"."list_members"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."list_members" FROM "anon";

CREATE TABLE "public"."lists" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "name"        text                     NOT NULL,
  "description" text,
  "archived_at" timestamp with time zone,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "lists_name_check" CHECK (((char_length(btrim(name)) >= 1) AND (char_length(btrim(name)) <= 200))),
  CONSTRAINT "lists_pkey" PRIMARY KEY (id),
  "owner_id"    uuid                     NOT NULL DEFAULT auth.uid()
);

ALTER TABLE "public"."lists"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."lists" FROM "anon";

CREATE OR REPLACE FUNCTION private.add_owner_membership()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  insert into public.list_members (list_id, user_id, role)
  values (new.id, new.owner_id, 'owner');
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.check_owner_role()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if new.role = 'owner' and new.user_id is distinct from
     (select l.owner_id from public.lists l where l.id = new.list_id) then
    raise exception 'only the list owner can have the owner role';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.guard_owner_membership()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION private.has_list_role (
  list_id  uuid,
  min_role public.list_role
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(private.list_role_of($1) >= $2, false);
$function$;

CREATE OR REPLACE FUNCTION private.list_role_of (
  list_id uuid
)
  RETURNS public.list_role
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select m.role
  from public.list_members m
  where m.list_id = $1
    and m.user_id = (select auth.uid());
$function$;

CREATE OR REPLACE FUNCTION private.shares_list_with (
  other_user uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select exists (
    select 1
    from public.list_members mine
    join public.list_members theirs on theirs.list_id = mine.list_id
    where mine.user_id = (select auth.uid())
      and theirs.user_id = $1
  );
$function$;

ALTER TABLE "public"."list_members"
  ADD CONSTRAINT "list_members_invited_by_fkey" FOREIGN KEY (invited_by) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "public"."list_members"
  ADD CONSTRAINT "list_members_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "public"."list_members"
  ADD CONSTRAINT "list_members_list_id_fkey" FOREIGN KEY (list_id) REFERENCES public.lists(id) ON DELETE CASCADE;

CREATE INDEX list_members_invited_by_idx ON public.list_members USING btree (invited_by);

CREATE UNIQUE INDEX list_members_one_owner_idx ON public.list_members USING btree (list_id)
  WHERE (ROLE = 'owner'::public.list_role);

CREATE INDEX list_members_user_id_list_id_idx ON public.list_members USING btree (user_id, list_id);

CREATE TRIGGER list_members_guard_owner
  BEFORE DELETE OR UPDATE ON public.list_members
  FOR EACH ROW
  EXECUTE FUNCTION private.guard_owner_membership();

CREATE TRIGGER list_members_owner_role_check
  BEFORE INSERT OR UPDATE OF ROLE ON public.list_members
  FOR EACH ROW
  EXECUTE FUNCTION private.check_owner_role();

CREATE TRIGGER lists_add_owner_membership
  AFTER INSERT ON public.lists
  FOR EACH ROW
  EXECUTE FUNCTION private.add_owner_membership();

CREATE TRIGGER lists_touch_updated_at
  BEFORE UPDATE ON public.lists
  FOR EACH ROW
  EXECUTE FUNCTION private.touch_updated_at();

CREATE POLICY "list_members_delete" ON "public"."list_members"
  FOR DELETE
  TO "authenticated"
  USING
    ((( SELECT private.has_list_role(list_members.list_id, 'owner'::public.list_role) AS has_list_role) OR ((user_id = ( SELECT auth.uid() AS uid)) AND (ROLE <>
    'owner'::public.list_role))));

CREATE POLICY "list_members_insert" ON "public"."list_members"
  FOR INSERT
  TO "authenticated"
  WITH CHECK (( SELECT private.has_list_role(list_members.list_id, 'owner'::public.list_role) AS has_list_role));

CREATE POLICY "list_members_select" ON "public"."list_members"
  FOR SELECT
  TO "authenticated"
  USING (( SELECT private.has_list_role(list_members.list_id, 'viewer'::public.list_role) AS has_list_role));

CREATE POLICY "list_members_update" ON "public"."list_members"
  FOR UPDATE
  TO "authenticated"
  USING (( SELECT private.has_list_role(list_members.list_id, 'owner'::public.list_role) AS has_list_role))
  WITH CHECK (( SELECT private.has_list_role(list_members.list_id, 'owner'::public.list_role) AS has_list_role));

CREATE POLICY "lists_delete" ON "public"."lists"
  FOR DELETE
  TO "authenticated"
  USING (( SELECT private.has_list_role(lists.id, 'owner'::public.list_role) AS has_list_role));

CREATE POLICY "lists_select" ON "public"."lists"
  FOR SELECT
  TO "authenticated"
  USING (( SELECT private.has_list_role(lists.id, 'viewer'::public.list_role) AS has_list_role));

CREATE POLICY "lists_update" ON "public"."lists"
  FOR UPDATE
  TO "authenticated"
  USING (( SELECT private.has_list_role(lists.id, 'owner'::public.list_role) AS has_list_role))
  WITH CHECK (( SELECT private.has_list_role(lists.id, 'owner'::public.list_role) AS has_list_role));

CREATE POLICY "profiles_select" ON "public"."profiles"
  FOR SELECT
  TO "authenticated"
  USING (((id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.shares_list_with(profiles.id) AS shares_list_with)));

REVOKE ALL ON FUNCTION "private"."has_list_role"(uuid, public.list_role) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."has_list_role"(uuid, public.list_role) TO "authenticated";

REVOKE ALL ON FUNCTION "private"."list_role_of"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."list_role_of"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "private"."shares_list_with"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."shares_list_with"(uuid) TO "authenticated";

REVOKE ALL ON TABLE "public"."list_members" FROM "authenticated";

REVOKE ALL ("invited_by") ON TABLE "public"."list_members" FROM "authenticated";

GRANT INSERT ("invited_by") ON TABLE "public"."list_members" TO "authenticated";

REVOKE ALL ("list_id") ON TABLE "public"."list_members" FROM "authenticated";

GRANT INSERT ("list_id") ON TABLE "public"."list_members" TO "authenticated";

REVOKE ALL ("role") ON TABLE "public"."list_members" FROM "authenticated";

GRANT INSERT ("role"), UPDATE ("role") ON TABLE "public"."list_members" TO "authenticated";

REVOKE ALL ("user_id") ON TABLE "public"."list_members" FROM "authenticated";

GRANT INSERT ("user_id") ON TABLE "public"."list_members" TO "authenticated";

GRANT DELETE, SELECT ON TABLE "public"."list_members" TO "authenticated";

REVOKE ALL ON TABLE "public"."list_members" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."list_members" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."list_members" TO "service_role";

REVOKE ALL ON TABLE "public"."lists" FROM "authenticated";

REVOKE ALL ("archived_at") ON TABLE "public"."lists" FROM "authenticated";

GRANT UPDATE ("archived_at") ON TABLE "public"."lists" TO "authenticated";

REVOKE ALL ("description") ON TABLE "public"."lists" FROM "authenticated";

GRANT INSERT ("description"), UPDATE ("description") ON TABLE "public"."lists" TO "authenticated";

REVOKE ALL ("id") ON TABLE "public"."lists" FROM "authenticated";

GRANT INSERT ("id") ON TABLE "public"."lists" TO "authenticated";

REVOKE ALL ("name") ON TABLE "public"."lists" FROM "authenticated";

GRANT INSERT ("name"), UPDATE ("name") ON TABLE "public"."lists" TO "authenticated";

GRANT DELETE, SELECT ON TABLE "public"."lists" TO "authenticated";

REVOKE ALL ON TABLE "public"."lists" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."lists" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."lists" TO "service_role";

ALTER TABLE "public"."lists"
  ADD CONSTRAINT "lists_owner_id_fkey" FOREIGN KEY (owner_id) REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE INDEX lists_owner_id_idx ON public.lists USING btree (owner_id);

CREATE POLICY "lists_insert" ON "public"."lists"
  FOR INSERT
  TO "authenticated"
  WITH CHECK ((owner_id = ( SELECT auth.uid() AS uid)));

REVOKE ALL ("owner_id") ON TABLE "public"."lists" FROM "authenticated";

GRANT INSERT ("owner_id") ON TABLE "public"."lists" TO "authenticated";
