SET local check_function_bodies = off;

CREATE TABLE "public"."task_status_events" (
  "id"             bigint                   GENERATED ALWAYS AS IDENTITY NOT NULL,
  "task_id"        uuid                     NOT NULL,
  "from_status_id" uuid,
  "to_status_id"   uuid                     NOT NULL,
  "from_behavior"  public.status_behavior,
  "to_behavior"    public.status_behavior   NOT NULL,
  "changed_at"     timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "task_status_events_pkey" PRIMARY KEY (id),
  "changed_by"     uuid                     DEFAULT auth.uid()
);

ALTER TABLE "public"."task_status_events"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."task_status_events" FROM "anon";

CREATE OR REPLACE FUNCTION private.apply_status_effects()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  old_behavior public.status_behavior;
  new_behavior public.status_behavior;
  old_terminal boolean := false;
  new_terminal boolean;
begin
  -- A WHEN clause cannot reference OLD in an insert-or-update trigger, so no-op writes are skipped here.
  if tg_op = 'UPDATE' and old.status_id is not distinct from new.status_id then
    return new;
  end if;

  select s.behavior into new_behavior from public.task_statuses s where s.id = new.status_id;
  new_terminal := coalesce(public.is_terminal(new_behavior), false);

  if tg_op = 'UPDATE' then
    select s.behavior into old_behavior from public.task_statuses s where s.id = old.status_id;
    old_terminal := coalesce(public.is_terminal(old_behavior), false);
  end if;

  new.status_changed_at := now();

  if not new_terminal then
    new.completed_at := null;
  elsif not old_terminal then
    new.completed_at := now();
  end if;

  if old_behavior = 'blocked' and new_behavior is distinct from 'blocked' then
    new.blocked_reason := null;
  end if;

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.delete_task_status_events()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  delete from public.task_status_events e where e.task_id = old.id;
  return old;
end;
$function$;

CREATE OR REPLACE FUNCTION private.guard_status_behavior()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if old.behavior is distinct from new.behavior
     and exists (select 1 from public.tasks t where t.status_id = old.id) then
    raise exception 'status behavior cannot change while tasks use it';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.record_status_event()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  old_behavior public.status_behavior;
  new_behavior public.status_behavior;
begin
  if tg_op = 'UPDATE' then
    if old.status_id is not distinct from new.status_id then
      return null;
    end if;
    select s.behavior into old_behavior from public.task_statuses s where s.id = old.status_id;
  end if;

  select s.behavior into new_behavior from public.task_statuses s where s.id = new.status_id;

  insert into public.task_status_events (task_id, from_status_id, to_status_id, from_behavior, to_behavior)
  values (
    new.id,
    case when tg_op = 'UPDATE' then old.status_id end,
    new.status_id,
    old_behavior,
    new_behavior
  );
  return null;
end;
$function$;

ALTER TABLE "public"."task_status_events"
  ADD CONSTRAINT "task_status_events_from_status_id_fkey" FOREIGN KEY (from_status_id) REFERENCES public.task_statuses(id);

ALTER TABLE "public"."task_status_events"
  ADD CONSTRAINT "task_status_events_task_id_fkey" FOREIGN KEY (task_id) REFERENCES public.tasks(id) ON DELETE CASCADE;

ALTER TABLE "public"."task_status_events"
  ADD CONSTRAINT "task_status_events_to_status_id_fkey" FOREIGN KEY (to_status_id) REFERENCES public.task_statuses(id);

CREATE INDEX task_status_events_from_status_id_idx ON public.task_status_events USING btree (from_status_id);

CREATE INDEX task_status_events_task_changed_idx ON public.task_status_events USING btree (task_id, changed_at);

CREATE INDEX task_status_events_to_status_id_idx ON public.task_status_events USING btree (to_status_id);

CREATE TRIGGER task_statuses_guard_behavior
  BEFORE UPDATE OF behavior ON public.task_statuses
  FOR EACH ROW
  EXECUTE FUNCTION private.guard_status_behavior();

CREATE TRIGGER tasks_before_delete_events
  BEFORE DELETE ON public.tasks
  FOR EACH ROW
  EXECUTE FUNCTION private.delete_task_status_events();

CREATE TRIGGER tasks_40_status_effects
  BEFORE INSERT OR UPDATE OF status_id ON public.tasks
  FOR EACH ROW
  EXECUTE FUNCTION private.apply_status_effects();

CREATE TRIGGER tasks_after_status_event
  AFTER INSERT OR UPDATE OF status_id ON public.tasks
  FOR EACH ROW
  EXECUTE FUNCTION private.record_status_event();

CREATE POLICY "task_status_events_select" ON "public"."task_status_events"
  FOR SELECT
  TO "authenticated"
  USING ((EXISTS ( SELECT 1
   FROM public.tasks t
  WHERE (t.id = task_status_events.task_id))));

REVOKE ALL ON SEQUENCE "public"."task_status_events_id_seq" FROM "postgres";

GRANT SELECT, UPDATE, USAGE ON SEQUENCE "public"."task_status_events_id_seq" TO "postgres";

REVOKE ALL ON SEQUENCE "public"."task_status_events_id_seq" FROM "service_role";

GRANT SELECT, UPDATE, USAGE ON SEQUENCE "public"."task_status_events_id_seq" TO "service_role";

REVOKE ALL ON TABLE "public"."task_status_events" FROM "authenticated";

GRANT SELECT ON TABLE "public"."task_status_events" TO "authenticated";

REVOKE ALL ON TABLE "public"."task_status_events" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."task_status_events" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."task_status_events" TO "service_role";

ALTER TABLE "public"."task_status_events"
  ADD CONSTRAINT "task_status_events_changed_by_fkey" FOREIGN KEY (changed_by) REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE INDEX task_status_events_changed_by_idx ON public.task_status_events USING btree (changed_by);
