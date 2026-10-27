alter table public.profiles enable row level security;

revoke all on table public.profiles from anon, authenticated;
grant select on table public.profiles to authenticated;
grant update (display_name, avatar_url) on table public.profiles to authenticated;

create policy profiles_select on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or (select private.shares_list_with(id)));

create policy profiles_update on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

alter table public.lists enable row level security;

revoke all on table public.lists from anon, authenticated;
grant select, delete on table public.lists to authenticated;
grant insert (id, name, description, owner_id) on table public.lists to authenticated;
grant update (name, description, archived_at) on table public.lists to authenticated;

create policy lists_select on public.lists
  for select to authenticated
  using ((select private.has_list_role(id, 'viewer')) or owner_id = (select auth.uid()));

create policy lists_insert on public.lists
  for insert to authenticated
  with check (owner_id = (select auth.uid()));

create policy lists_update on public.lists
  for update to authenticated
  using ((select private.has_list_role(id, 'owner')))
  with check ((select private.has_list_role(id, 'owner')));

create policy lists_delete on public.lists
  for delete to authenticated
  using ((select private.has_list_role(id, 'owner')));

alter table public.list_members enable row level security;

revoke all on table public.list_members from anon, authenticated;
grant select, delete on table public.list_members to authenticated;
grant insert (list_id, user_id, role, invited_by) on table public.list_members to authenticated;
grant update (role) on table public.list_members to authenticated;

create policy list_members_select on public.list_members
  for select to authenticated
  using ((select private.has_list_role(list_id, 'viewer')));

create policy list_members_insert on public.list_members
  for insert to authenticated
  with check ((select private.has_list_role(list_id, 'owner')));

create policy list_members_update on public.list_members
  for update to authenticated
  using ((select private.has_list_role(list_id, 'owner')))
  with check ((select private.has_list_role(list_id, 'owner')));

create policy list_members_delete on public.list_members
  for delete to authenticated
  using (
    (select private.has_list_role(list_id, 'owner'))
    or (user_id = (select auth.uid()) and role <> 'owner')
  );
