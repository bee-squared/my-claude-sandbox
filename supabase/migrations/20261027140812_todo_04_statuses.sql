SET local check_function_bodies = off;

CREATE TABLE "public"."task_statuses" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "owner_id"    uuid,
  "label"       text                     NOT NULL,
  "behavior"    public.status_behavior   NOT NULL,
  "sort_order"  smallint                 NOT NULL,
  "archived_at" timestamp with time zone,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "task_statuses_builtin_not_archived" CHECK (((owner_id IS NOT NULL) OR (archived_at IS NULL))),
  CONSTRAINT "task_statuses_label_length" CHECK (((char_length(btrim(label)) >= 1) AND (char_length(btrim(label)) <= 50))),
  CONSTRAINT "task_statuses_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."task_statuses"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."task_statuses" FROM "anon";

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
      )
  );
$function$;

CREATE OR REPLACE FUNCTION private.normalize_custom_status()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

ALTER TABLE "public"."task_statuses"
  ADD CONSTRAINT "task_statuses_owner_id_fkey" FOREIGN KEY (owner_id) REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE UNIQUE INDEX task_statuses_one_builtin_per_behavior_idx ON public.task_statuses USING btree (behavior)
  WHERE (owner_id IS NULL);

CREATE INDEX task_statuses_owner_id_idx ON public.task_statuses USING btree (owner_id);

CREATE UNIQUE INDEX task_statuses_owner_label_idx ON public.task_statuses USING btree (owner_id, lower(label)) NULLS NOT DISTINCT;

CREATE TRIGGER task_statuses_normalize
  BEFORE INSERT OR UPDATE OF label, behavior, sort_order ON public.task_statuses
  FOR EACH ROW
  EXECUTE FUNCTION private.normalize_custom_status();

CREATE POLICY "task_statuses_delete" ON "public"."task_statuses"
  FOR DELETE
  TO "authenticated"
  USING ((owner_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "task_statuses_insert" ON "public"."task_statuses"
  FOR INSERT
  TO "authenticated"
  WITH CHECK ((owner_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "task_statuses_select" ON "public"."task_statuses"
  FOR SELECT
  TO "authenticated"
  USING (((owner_id IS NULL) OR (owner_id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.can_read_status(task_statuses.id) AS can_read_status)));

CREATE POLICY "task_statuses_update" ON "public"."task_statuses"
  FOR UPDATE
  TO "authenticated"
  USING ((owner_id = ( SELECT auth.uid() AS uid)))
  WITH CHECK ((owner_id = ( SELECT auth.uid() AS uid)));

REVOKE ALL ON FUNCTION "private"."can_read_status"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."can_read_status"(uuid) TO "authenticated";

REVOKE ALL ON TABLE "public"."task_statuses" FROM "authenticated";

REVOKE ALL ("archived_at") ON TABLE "public"."task_statuses" FROM "authenticated";

GRANT UPDATE ("archived_at") ON TABLE "public"."task_statuses" TO "authenticated";

REVOKE ALL ("behavior") ON TABLE "public"."task_statuses" FROM "authenticated";

GRANT INSERT ("behavior"), UPDATE ("behavior") ON TABLE "public"."task_statuses" TO "authenticated";

REVOKE ALL ("id") ON TABLE "public"."task_statuses" FROM "authenticated";

GRANT INSERT ("id") ON TABLE "public"."task_statuses" TO "authenticated";

REVOKE ALL ("label") ON TABLE "public"."task_statuses" FROM "authenticated";

GRANT INSERT ("label"), UPDATE ("label") ON TABLE "public"."task_statuses" TO "authenticated";

REVOKE ALL ("owner_id") ON TABLE "public"."task_statuses" FROM "authenticated";

GRANT INSERT ("owner_id") ON TABLE "public"."task_statuses" TO "authenticated";

REVOKE ALL ("sort_order") ON TABLE "public"."task_statuses" FROM "authenticated";

GRANT INSERT ("sort_order"), UPDATE ("sort_order") ON TABLE "public"."task_statuses" TO "authenticated";

GRANT DELETE, SELECT ON TABLE "public"."task_statuses" TO "authenticated";

REVOKE ALL ON TABLE "public"."task_statuses" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."task_statuses" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."task_statuses" TO "service_role";
