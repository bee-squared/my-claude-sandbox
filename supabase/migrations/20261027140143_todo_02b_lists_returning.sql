DROP POLICY "lists_select" ON "public"."lists";

CREATE POLICY "lists_select" ON "public"."lists"
  FOR SELECT
  TO "authenticated"
  USING ((( SELECT private.has_list_role(lists.id, 'viewer'::public.list_role) AS has_list_role) OR (owner_id = ( SELECT auth.uid() AS uid))));
