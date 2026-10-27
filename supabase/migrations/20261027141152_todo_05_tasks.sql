SET local check_function_bodies = off;

CREATE TABLE "public"."tasks" (
  "id"                uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "list_id"           uuid                     NOT NULL,
  "title"             text                     NOT NULL,
  "description"       text,
  "status_id"         uuid                     NOT NULL,
  "position"          double precision         NOT NULL DEFAULT 0,
  "priority"          smallint,
  "assignee_id"       uuid,
  "blocked_reason"    text,
  "due_at"            timestamp with time zone,
  "status_changed_at" timestamp with time zone NOT NULL DEFAULT now(),
  "completed_at"      timestamp with time zone,
  "created_at"        timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"        timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "tasks_pkey" PRIMARY KEY (id),
  CONSTRAINT "tasks_priority_range" CHECK (((priority >= 1) AND (priority <= 3))),
  CONSTRAINT "tasks_title_length" CHECK (((char_length(btrim(title)) >= 1) AND (char_length(btrim(title)) <= 500))),
  "created_by"        uuid                     DEFAULT auth.uid()
);

ALTER TABLE "public"."tasks"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."tasks" FROM "anon";

CREATE OR REPLACE FUNCTION private.check_task_assignee()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
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

CREATE OR REPLACE FUNCTION private.clear_removed_member_assignments()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  update public.tasks t
  set assignee_id = null
  where t.list_id = old.list_id and t.assignee_id = old.user_id;
  return old;
end;
$function$;

CREATE OR REPLACE FUNCTION private.default_task_status()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if new.status_id is null then
    select s.id into new.status_id
    from public.task_statuses s
    where s.owner_id is null and s.behavior = 'todo';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.status_usable_in_list (
  status_id uuid,
  list_id   uuid
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
        or exists (
          select 1
          from public.list_members m
          where m.list_id = $2
            and m.user_id = s.owner_id
            and m.role >= 'editor'
        )
      )
  );
$function$;

ALTER TABLE "public"."tasks"
  ADD CONSTRAINT "tasks_assignee_id_fkey" FOREIGN KEY (assignee_id) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "public"."tasks"
  ADD CONSTRAINT "tasks_list_id_fkey" FOREIGN KEY (list_id) REFERENCES public.lists(id) ON DELETE CASCADE;

ALTER TABLE "public"."tasks"
  ADD CONSTRAINT "tasks_status_id_fkey" FOREIGN KEY (status_id) REFERENCES public.task_statuses(id);

CREATE INDEX tasks_assignee_id_idx ON public.tasks USING btree (assignee_id);

CREATE INDEX tasks_list_status_position_idx ON public.tasks USING btree (list_id, status_id, "position");

CREATE INDEX tasks_status_id_idx ON public.tasks USING btree (status_id);

CREATE TRIGGER list_members_clear_assignments
  AFTER DELETE ON public.list_members
  FOR EACH ROW
  EXECUTE FUNCTION private.clear_removed_member_assignments();

CREATE TRIGGER tasks_10_default_status
  BEFORE INSERT ON public.tasks
  FOR EACH ROW
  EXECUTE FUNCTION private.default_task_status();

CREATE TRIGGER tasks_20_check_status
  BEFORE INSERT OR UPDATE OF status_id, list_id ON public.tasks
  FOR EACH ROW
  EXECUTE FUNCTION private.check_task_status();

CREATE TRIGGER tasks_30_check_assignee
  BEFORE INSERT OR UPDATE OF assignee_id, list_id ON public.tasks
  FOR EACH ROW
  EXECUTE FUNCTION private.check_task_assignee();

CREATE TRIGGER tasks_90_touch_updated_at
  BEFORE UPDATE ON public.tasks
  FOR EACH ROW
  EXECUTE FUNCTION private.touch_updated_at();

CREATE POLICY "tasks_delete" ON "public"."tasks"
  FOR DELETE
  TO "authenticated"
  USING (( SELECT private.has_list_role(tasks.list_id, 'editor'::public.list_role) AS has_list_role));

CREATE POLICY "tasks_insert" ON "public"."tasks"
  FOR INSERT
  TO "authenticated"
  WITH CHECK (( SELECT private.has_list_role(tasks.list_id, 'editor'::public.list_role) AS has_list_role));

CREATE POLICY "tasks_select" ON "public"."tasks"
  FOR SELECT
  TO "authenticated"
  USING (( SELECT private.has_list_role(tasks.list_id, 'viewer'::public.list_role) AS has_list_role));

CREATE POLICY "tasks_update" ON "public"."tasks"
  FOR UPDATE
  TO "authenticated"
  USING (( SELECT private.has_list_role(tasks.list_id, 'editor'::public.list_role) AS has_list_role))
  WITH CHECK (( SELECT private.has_list_role(tasks.list_id, 'editor'::public.list_role) AS has_list_role));

REVOKE ALL ON FUNCTION "private"."status_usable_in_list"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."status_usable_in_list"(uuid, uuid) TO "authenticated";

REVOKE ALL ON TABLE "public"."tasks" FROM "authenticated";

REVOKE ALL ("assignee_id") ON TABLE "public"."tasks" FROM "authenticated";

GRANT INSERT ("assignee_id"), UPDATE ("assignee_id") ON TABLE "public"."tasks" TO "authenticated";

REVOKE ALL ("blocked_reason") ON TABLE "public"."tasks" FROM "authenticated";

GRANT INSERT ("blocked_reason"), UPDATE ("blocked_reason") ON TABLE "public"."tasks" TO "authenticated";

REVOKE ALL ("description") ON TABLE "public"."tasks" FROM "authenticated";

GRANT INSERT ("description"), UPDATE ("description") ON TABLE "public"."tasks" TO "authenticated";

REVOKE ALL ("due_at") ON TABLE "public"."tasks" FROM "authenticated";

GRANT INSERT ("due_at"), UPDATE ("due_at") ON TABLE "public"."tasks" TO "authenticated";

REVOKE ALL ("id") ON TABLE "public"."tasks" FROM "authenticated";

GRANT INSERT ("id") ON TABLE "public"."tasks" TO "authenticated";

REVOKE ALL ("list_id") ON TABLE "public"."tasks" FROM "authenticated";

GRANT INSERT ("list_id"), UPDATE ("list_id") ON TABLE "public"."tasks" TO "authenticated";

REVOKE ALL ("position") ON TABLE "public"."tasks" FROM "authenticated";

GRANT INSERT ("position"), UPDATE ("position") ON TABLE "public"."tasks" TO "authenticated";

REVOKE ALL ("priority") ON TABLE "public"."tasks" FROM "authenticated";

GRANT INSERT ("priority"), UPDATE ("priority") ON TABLE "public"."tasks" TO "authenticated";

REVOKE ALL ("status_id") ON TABLE "public"."tasks" FROM "authenticated";

GRANT INSERT ("status_id"), UPDATE ("status_id") ON TABLE "public"."tasks" TO "authenticated";

REVOKE ALL ("title") ON TABLE "public"."tasks" FROM "authenticated";

GRANT INSERT ("title"), UPDATE ("title") ON TABLE "public"."tasks" TO "authenticated";

GRANT DELETE, SELECT ON TABLE "public"."tasks" TO "authenticated";

REVOKE ALL ON TABLE "public"."tasks" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."tasks" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."tasks" TO "service_role";

ALTER TABLE "public"."tasks"
  ADD CONSTRAINT "tasks_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE INDEX tasks_created_by_idx ON public.tasks USING btree (created_by);
