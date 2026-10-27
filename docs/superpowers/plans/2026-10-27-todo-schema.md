# To-Do Core Schema Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the To-Do app's Postgres core (profiles, lists, membership, statuses, tasks, status history) with every rule enforced in the database and proven by pgTAP tests.

**Architecture:** Declarative schema files in `supabase/schemas/` are the source of truth. Each task edits them, generates a migration with `pg-delta` (`db schema declarative sync`), applies it locally and runs pgTAP. Policies call `SECURITY DEFINER` helpers in an unexposed `private` schema. Triggers handle defaults, validity checks, side effects and history.

**Tech Stack:** Supabase CLI 2.120.0 via `pnpm supabase`, Postgres 17, `pg-delta` diff engine (`[experimental.pgdelta] enabled = true` already in `supabase/config.toml`), pgTAP 1.3.3.

**Spec:** `docs/superpowers/specs/2026-10-27-todo-schema-design.md`

## Global Constraints

- Use pnpm for everything (`pnpm supabase …`). Never npm/npx.
- All tables in `public`; helper and trigger functions in `private`. Every timestamp is `timestamptz`. Every foreign key column has an index.
- RLS is on for every table. `anon` has no grants on any table or function. Everything is for `authenticated`.
- Helpers are `SECURITY DEFINER`, `STABLE`, `set search_path = ''`. Policies call them wrapped as `(select private.fn(...))` whenever the arguments don't depend on the row.
- Every `SECURITY DEFINER` function sets `search_path = ''` and fully qualifies names.
- No code tests a status by its name or id to decide behaviour, only by `behavior`. The only exception is the default-status lookup, `owner_id is null and behavior = 'todo'`.
- No column limits, no transition rules.
- Enum `status_behavior` values, in order: `backlog, todo, in_progress, blocked, in_review, completed, cancelled`.
- Enum `list_role` values, in order: `viewer, editor, owner`, so `>=` comparisons work.

### Deviations from the spec (decided here)

1. **Delivery commands.** This CLI uses `pg-delta`, so `schema_paths` is ignored (leave it `[]`) and `db diff` ignores `supabase/schemas/`. Use `pnpm supabase db schema declarative sync -f <name> --apply`. Files are ordered by dependency, so the spec's numeric prefixes are kept for readability only. Each task generates its own migration instead of one `todo_init`. Nothing is deployed yet, so this is cosmetic.
2. **`on delete no action` instead of `restrict`** on `tasks.status_id`, `task_status_events.from_status_id` and `task_status_events.to_status_id`. Verified locally: with `restrict`, deleting a user fails depending on FK creation order. Their custom status's cascade runs before their lists' cascade has removed the tasks. `no action` checks at end of statement, so a direct delete of a used status still fails (23503) while user deletion works.
3. **Rule 3 signalling needs no flag.**
   - `lists.owner_id` is not client-updatable: there is no column grant.
   - The guard trigger protects the member row whose `user_id` equals the list's current `owner_id`.
   - `transfer_list_ownership` updates `lists.owner_id` first, so the old owner's row is no longer protected when it is downgraded.
   - The guard allows the delete when the list or the user no longer exists, which covers both cascades.
4. **Column-level grants.** Clients may write only the columns listed under each task's grants. Trigger-maintained columns and `created_by` are not client-writable.
5. **Custom labels are stored trimmed** (`btrim`) by trigger before the uniqueness and built-in checks. This keeps `" To Do "` from slipping past.

### Error catalogue

Custom raises use the default SQLSTATE `P0001` with these exact messages. Tests match on them.

| Rule | Message |
| --- | --- |
| 3 delete owner row | `list owner cannot be removed` |
| 3 downgrade owner | `list owner cannot be downgraded` |
| 3 owner role for non-owner | `only the list owner can have the owner role` |
| 4 caller not owner | `only the list owner can transfer ownership` |
| 4 target not member | `new owner must already be a member of the list` |
| 6 status not usable | `status cannot be used in this list` |
| 6 archived newly chosen | `archived status cannot be chosen` |
| 6a assignee | `assignee must be a member of the list` |
| 10 behaviour change | `status behavior cannot change while tasks use it` |
| 10 built-in label | `status label matches a built-in status` |

Postgres raises the rest itself: RLS and grant denials `42501`, check constraints `23514`, unique `23505`, FK `23503`, not-null `23502`.

## Review Focus

1. **Deleting a user who owns lists with tasks in their custom status** must succeed and remove everything. Pinned in Task 6 (and the simpler case in Task 2).
2. **Whitespace or case-padded labels** (`" to do "`, `"Waiting for parts "`) must be rejected as duplicates, and labels are stored trimmed. Pinned in Task 4.
3. **An owner bypassing the transfer RPC** must be rejected, whether by updating `lists.owner_id` directly or by promoting a member to `owner`. Pinned in Task 2.
4. **A no-op status write** (`set status_id = status_id`) must write no event and leave `status_changed_at` and `completed_at` alone. Pinned in Task 6.
5. **An archived list stays fully editable** by its editors. This is a user decision, but no acceptance criterion covers it. Pinned in Task 5.

---

## Test conventions (all tasks)

- Files live in `supabase/tests/database/`, named `NN_name.test.sql`, and run alphabetically.
- `00_helpers.test.sql` (Task 1) persists the `tests` schema and its helpers. It is not wrapped in a transaction. Every other file is `begin; select plan(N); … select * from finish(); rollback;`.
- Fixtures are created as `postgres`. Switch identity with `select tests.authenticate_as('<email>');` and switch back with `select tests.clear_authentication();`.
- To run one file: `pnpm supabase test db supabase/tests/database/00_helpers.test.sql supabase/tests/database/<file>`. To run all: `pnpm supabase test db`.
- Per-task migration loop: `pnpm supabase db schema declarative sync -f <name> --apply`. Then read the generated file in `supabase/migrations/` and check that it contains only this task's change. Drop stray default-privilege `GRANT` lines that contradict the declared grants.

---

### Task 1: Test harness, foundations, profiles

**Files:**
- Create: `supabase/schemas/00_schemas.sql`, `10_types.sql`, `20_profiles.sql`, `50_auth_helpers.sql`, `60_triggers.sql`, `70_policies.sql`
- Create: `supabase/tests/database/00_helpers.test.sql`, `supabase/tests/database/10_profiles.test.sql`

**Interfaces:**
- Produces:
  - schema `private`, with usage granted to `authenticated` only
  - enums `public.list_role`, `public.status_behavior`
  - `public.is_terminal(b public.status_behavior) returns boolean`, `immutable`
  - table `public.profiles`
  - trigger function `private.handle_new_user()`
  - generic `private.touch_updated_at()` trigger function (sets `new.updated_at = now()`), used by Tasks 2 and 5
- Test helpers, all in schema `tests`, `security definer`, `search_path = ''`, executable by `authenticated`:
  - `tests.create_user(email text, display_name text default null) returns uuid`: inserts into `auth.users` (`instance_id` all-zero uuid, `aud`/`role` `'authenticated'`, `raw_user_meta_data` `{"display_name": …}` or `{}`)
  - `tests.user_id(email text) returns uuid`
  - `tests.authenticate_as(email text) returns void`: `set_config('request.jwt.claims', {"sub","role":"authenticated"}, true)` and `set_config('role','authenticated',true)`. Not security definer.
  - `tests.clear_authentication() returns void`: claims `''`, role `'postgres'`. Not security definer.
  - `tests.list_id(list_name text) returns uuid`, `tests.status_id(status_label text) returns uuid`, `tests.task_id(task_title text) returns uuid`: lookups that ignore RLS. They raise if the name is not unique. Being plpgsql, they resolve tables at call time, so they can be defined now.

- [ ] **Step 1: Write `00_helpers.test.sql`.** It contains `create extension if not exists pgtap with schema extensions;`, `create schema if not exists tests;`, the grants, and `create or replace` for each helper above. It ends with `select plan(1); select ok(tests.user_id('nobody@test') is null, 'helpers loaded'); select * from finish();`.

- [ ] **Step 2: Write the failing test `10_profiles.test.sql`**

```sql
begin;
select plan(7);
select tests.create_user('ann@test', 'Ann');
select tests.create_user('bob@test');

select enum_has_labels('public', 'status_behavior',
  array['backlog','todo','in_progress','blocked','in_review','completed','cancelled']);
select enum_has_labels('public', 'list_role', array['viewer','editor','owner']);
select ok(public.is_terminal('completed') and public.is_terminal('cancelled')
  and not public.is_terminal('blocked') and not public.is_terminal('todo'),
  'is_terminal is true only for completed and cancelled');
select is((select display_name from public.profiles where id = tests.user_id('ann@test')),
  'Ann', 'signup creates a profile with display_name from metadata');

select tests.authenticate_as('ann@test');
select results_eq($$select display_name from public.profiles$$, $$values ('Ann'::text)$$,
  'a user sharing no list sees only their own profile');
update public.profiles set display_name = 'hacked' where id = tests.user_id('bob@test');
select tests.clear_authentication();
select is((select display_name from public.profiles where id = tests.user_id('bob@test')),
  null, 'cannot update another user''s profile');
select table_privs_are('public', 'profiles', 'anon', array[]::text[]);

select * from finish();
rollback;
```

- [ ] **Step 3: Run it to verify it fails**

Run: `pnpm supabase test db`
Expected: `10_profiles` FAILS (type `status_behavior` / relation `profiles` does not exist). `00_helpers` passes.

- [ ] **Step 4: Implement the foundations**
  - `00_schemas.sql`: `create schema private`, `revoke all on schema private from public`, `grant usage on schema private to authenticated`.
  - `10_types.sql`: both enums.
  - `50_auth_helpers.sql`: `public.is_terminal`, with `execute` revoked from `public`/`anon` and granted to `authenticated`.
  - `20_profiles.sql`: columns as in spec §profiles.
  - `60_triggers.sql`: `private.handle_new_user()`, security definer. It inserts `profiles(id, display_name)`, with `display_name` = `coalesce(raw_user_meta_data->>'display_name', raw_user_meta_data->>'full_name', raw_user_meta_data->>'name')`. Trigger `on_auth_user_created` runs `after insert on auth.users`. Also add `private.touch_updated_at()`.
  - `70_policies.sql`: enable RLS on profiles; revoke all from `anon`, `authenticated`; grant `select`, `update (display_name, avatar_url)` to `authenticated`.
    - select policy: `id = (select auth.uid())`. Task 2 widens it.
    - update policy: `using` and `with check` both `id = (select auth.uid())`.

- [ ] **Step 5: Generate and apply the migration**

Run: `pnpm supabase db schema declarative sync -f todo_01_foundations --apply`
Expected: a new `supabase/migrations/<ts>_todo_01_foundations.sql`, including the `auth.users` trigger. Review it.

- [ ] **Step 6: Run tests to verify they pass**

Run: `pnpm supabase test db`
Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add supabase/schemas supabase/migrations supabase/tests
git commit -m "feat(db): add foundations, profiles and pgTAP harness"
```

---

### Task 2: Lists, membership and access helpers

**Files:**
- Create: `supabase/schemas/30_lists.sql`, `supabase/schemas/31_list_members.sql`
- Modify: `supabase/schemas/50_auth_helpers.sql`, `60_triggers.sql`, `70_policies.sql`
- Test: `supabase/tests/database/20_lists_members.test.sql`

**Interfaces:**
- Consumes: Task 1 enums, `private.touch_updated_at()`, test helpers.
- Produces:
  - tables `public.lists`, `public.list_members` (columns and indexes per spec)
  - `private.list_role_of(list_id uuid) returns public.list_role`: the caller's role, or null
  - `private.has_list_role(list_id uuid, min_role public.list_role) returns boolean`
  - `private.shares_list_with(other_user uuid) returns boolean`: true if the caller and `other_user` are both members of some list
- Triggers:
  - `lists_add_owner_membership`: after insert on lists, inserts `(id, owner_id, 'owner')`
  - `lists_touch_updated_at`: before update
  - `list_members_guard_owner`: before update or delete, function `private.guard_owner_membership()`, security definer:
    - on delete of a row whose `user_id` = the list's `owner_id`, while both the list and the `auth.users` row still exist → `list owner cannot be removed`
    - on update of that row to a non-owner role → `list owner cannot be downgraded`
  - `list_members_owner_role_check`: before insert or update of role. If `new.role = 'owner'` and `new.user_id <> lists.owner_id` → `only the list owner can have the owner role`.
- Grants to `authenticated`:
  - lists: `select`, `insert (id, name, description, owner_id)`, `update (name, description, archived_at)`, `delete`
  - list_members: `select`, `insert (list_id, user_id, role, invited_by)`, `update (role)`, `delete`
- Policies, per the spec's Access control table:
  - lists insert: `with check owner_id = (select auth.uid())`
  - list_members read: `has_list_role(list_id,'viewer')`
  - list_members delete: owner, or `user_id = (select auth.uid()) and role <> 'owner'`
  - profiles select widens to `id = (select auth.uid()) or private.shares_list_with(id)`

- [ ] **Step 1: Write the failing test `20_lists_members.test.sql`.** Fixtures:
  - users `owner@test`, `ed@test`, `vi@test`, `stranger@test`
  - as owner: `insert into public.lists(name) values ('Home')`, then insert member rows for `ed` (editor) and `vi` (viewer)

Assertions (plan 16):

```sql
select is((select role from public.list_members where list_id = tests.list_id('Home')
  and user_id = tests.user_id('owner@test')), 'owner'::public.list_role, 'creator becomes owner member');
-- as stranger
select is_empty($$select 1 from public.lists$$, 'non-member cannot read the list');
select is_empty($$select 1 from public.list_members$$, 'non-member cannot read members');
-- as ed
select throws_ok($$insert into public.list_members(list_id,user_id,role)
  values (tests.list_id('Home'), tests.user_id('stranger@test'), 'viewer')$$, '42501', null, 'editor cannot add members');
update public.list_members set role = 'editor' where user_id = tests.user_id('vi@test');
delete from public.list_members where user_id = tests.user_id('vi@test');
update public.lists set name = 'Renamed by editor';
select is((select name from public.lists where id = tests.list_id('Home')), 'Home', 'only the owner updates the list');
-- back to postgres
select is((select role from public.list_members where user_id = tests.user_id('vi@test')),
  'viewer'::public.list_role, 'editor cannot change or remove members');
-- as vi
delete from public.list_members where user_id = tests.user_id('vi@test');
select is_empty($$select 1 from public.list_members where user_id = tests.user_id('vi@test')$$, 'a member can leave');
-- as owner
select throws_ok($$delete from public.list_members where user_id = tests.user_id('owner@test')$$,
  'P0001', 'list owner cannot be removed');
select throws_ok($$update public.list_members set role = 'editor' where user_id = tests.user_id('owner@test')$$,
  'P0001', 'list owner cannot be downgraded');
select throws_ok($$update public.list_members set role = 'owner' where user_id = tests.user_id('ed@test')$$,
  'P0001', 'only the list owner can have the owner role');
select throws_ok($$update public.lists set owner_id = tests.user_id('ed@test')$$, '42501', null,
  'owner_id cannot be changed directly');
select throws_ok($$insert into public.lists(name) values ('   ')$$, '23514', null, 'blank list name rejected');
select isnt_empty($$select 1 from public.profiles where id = tests.user_id('ed@test')$$, 'owner sees a co-member''s profile');
-- updated_at: as postgres set lists.updated_at = '2000-01-01', then as owner rename
select ok((select updated_at > '2000-01-02' from public.lists where id = tests.list_id('Home')), 'updated_at maintained');
select table_privs_are('public', 'lists', 'anon', array[]::text[]);
-- as postgres
select lives_ok($$delete from auth.users where id = tests.user_id('owner@test')$$, 'deleting an owning user succeeds');
```

- [ ] **Step 2: Run to verify it fails**

Run: `pnpm supabase test db`
Expected: `20_lists_members` FAILS (relation `public.lists` does not exist).

- [ ] **Step 3: Implement the tables, helpers, triggers, grants and policies listed in Interfaces.** Name check: `char_length(btrim(name)) between 1 and 200`.

- [ ] **Step 4: Generate, apply, test**

Run: `pnpm supabase db schema declarative sync -f todo_02_lists --apply && pnpm supabase test db`
Expected: all PASS. Review the generated migration.

- [ ] **Step 5: Commit**

```bash
git add supabase/schemas supabase/migrations supabase/tests
git commit -m "feat(db): add lists, membership, owner guards and RLS"
```

---

### Task 3: Ownership transfer RPC

**Files:**
- Create: `supabase/schemas/65_rpc.sql`
- Modify: `supabase/schemas/70_policies.sql` (function grants)
- Test: `supabase/tests/database/25_transfer_ownership.test.sql`

**Interfaces:**
- Consumes: Task 2 tables and guard semantics: the guard protects whoever `lists.owner_id` names.
- Produces: `public.transfer_list_ownership(list_id uuid, new_owner uuid) returns void`, `security definer`, `search_path = ''`. Parameter names are the RPC API, so qualify column references instead of renaming them. Execute is revoked from `public` and `anon`, and granted to `authenticated`.
  - If the caller is not the list's `owner_id` → `only the list owner can transfer ownership`.
  - If `new_owner` is the caller → return without change.
  - If `new_owner` is not in `list_members` → `new owner must already be a member of the list`.
  - Otherwise: update `lists.owner_id`, set the old owner's row to `editor`, then set the new owner's row to `owner`, in that order. The order matters for the guard and the unique index.

- [ ] **Step 1: Write the failing test.** Fixtures: owner `own@test` with list `Home`, editor `ed@test`, stranger `st@test`. Plan 8:

```sql
-- as ed
select throws_ok($$select public.transfer_list_ownership(tests.list_id('Home'), tests.user_id('ed@test'))$$,
  'P0001', 'only the list owner can transfer ownership');
-- as own
select throws_ok($$select public.transfer_list_ownership(tests.list_id('Home'), tests.user_id('st@test'))$$,
  'P0001', 'new owner must already be a member of the list');
select lives_ok($$select public.transfer_list_ownership(tests.list_id('Home'), tests.user_id('own@test'))$$, 'transfer to self is a no-op');
select lives_ok($$select public.transfer_list_ownership(tests.list_id('Home'), tests.user_id('ed@test'))$$, 'owner transfers to editor');
-- as postgres
select is((select count(*) from public.list_members where list_id = tests.list_id('Home') and role = 'owner'), 1::bigint, 'exactly one owner');
select is((select owner_id from public.lists where id = tests.list_id('Home')), tests.user_id('ed@test'), 'lists.owner_id updated');
select is((select role from public.list_members where user_id = tests.user_id('own@test')), 'editor'::public.list_role, 'old owner is editor');
select function_privs_are('public', 'transfer_list_ownership', array['uuid','uuid'], 'anon', array[]::text[]);
```

- [ ] **Step 2: Run to verify it fails**

Run: `pnpm supabase test db`
Expected: FAIL (function `transfer_list_ownership` does not exist).

- [ ] **Step 3: Implement `public.transfer_list_ownership` per Interfaces.**

- [ ] **Step 4: Generate, apply, test**

Run: `pnpm supabase db schema declarative sync -f todo_03_transfer_ownership --apply && pnpm supabase test db`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add supabase/schemas supabase/migrations supabase/tests
git commit -m "feat(db): add transfer_list_ownership RPC"
```

---

### Task 4: Statuses (built-in and custom)

**Files:**
- Create: `supabase/schemas/40_task_statuses.sql`, migration `supabase/migrations/<ts>_seed_builtin_statuses.sql` (via `pnpm supabase migration new`)
- Modify: `supabase/schemas/50_auth_helpers.sql`, `60_triggers.sql`, `70_policies.sql`
- Test: `supabase/tests/database/30_statuses.test.sql`

**Interfaces:**
- Consumes: `private.shares_list_with` (Task 2).
- Produces:
  - table `public.task_statuses` with the spec's columns, indexes and check
  - `private.can_read_status(status_id uuid) returns boolean`: built-in, or own, or owner shares a list with the caller
  - trigger `task_statuses_normalize`, before insert or update of label/behavior/sort_order, function `private.normalize_custom_status()`, skipped for built-ins (`owner_id is null`):
    - `new.label := btrim(new.label)`
    - if the lowercased label matches any built-in label → `status label matches a built-in status`
    - on insert with `sort_order` null, set it to the matching built-in's `sort_order + 1`
- Grants to `authenticated`: `select`, `insert (id, owner_id, label, behavior, sort_order)`, `update (label, behavior, sort_order, archived_at)`, `delete`.
- Policies:
  - select: `owner_id is null or owner_id = (select auth.uid()) or private.can_read_status(id)`
  - insert, update (`using` and `with check`) and delete: `owner_id = (select auth.uid())`

Built-ins are therefore unreachable for writes: `owner_id` is never null under these checks.

- [ ] **Step 1: Write the failing test.** Fixtures: `ann@test`, `bob@test`; ann owns list `Home`. Plan 13:

```sql
select results_eq($$select behavior::text, label, sort_order::int from public.task_statuses where owner_id is null order by sort_order$$,
  $$values ('backlog','Backlog',10),('todo','To Do',20),('in_progress','In Progress',30),('blocked','Blocked',40),
           ('in_review','In Review',50),('completed','Completed',60),('cancelled','Cancelled',70)$$, 'seven built-ins seeded');
-- as ann
insert into public.task_statuses(owner_id, label, behavior) values (tests.user_id('ann@test'), '  Waiting for parts ', 'blocked');
select is((select sort_order::int from public.task_statuses where label = 'Waiting for parts'), 41, 'custom sorts after its built-in, label trimmed');
select throws_ok($$insert into public.task_statuses(owner_id,label,behavior) values (tests.user_id('ann@test'),' to do ','todo')$$,
  'P0001', 'status label matches a built-in status');
select throws_ok($$insert into public.task_statuses(owner_id,label,behavior) values (tests.user_id('ann@test'),'WAITING FOR PARTS ','blocked')$$,
  '23505', null, 'duplicate custom label rejected case- and space-insensitively');
select throws_ok($$insert into public.task_statuses(owner_id,label,behavior) values (null,'Mine','todo')$$, '42501', null, 'cannot insert built-ins');
select throws_ok($$insert into public.task_statuses(owner_id,label,behavior) values (tests.user_id('bob@test'),'X','todo')$$, '42501', null, 'cannot create for others');
select throws_ok($$insert into public.task_statuses(owner_id,label,behavior) values (tests.user_id('ann@test'),repeat('x',51),'todo')$$, '23514', null, 'label max 50');
update public.task_statuses set label = 'Hacked' where owner_id is null;
delete from public.task_statuses where owner_id is null;
-- as postgres
select is((select count(*) from public.task_statuses where owner_id is null and label <> 'Hacked'), 7::bigint, 'clients cannot change or delete built-ins');
-- as bob
select lives_ok($$insert into public.task_statuses(owner_id,label,behavior) values (tests.user_id('bob@test'),'Waiting for parts','blocked')$$, 'labels unique per owner only');
select is((select count(*) from public.task_statuses where owner_id = tests.user_id('ann@test')), 0::bigint, 'strangers cannot see my statuses');
-- as postgres: add bob to Home as editor; as bob:
select is((select count(*) from public.task_statuses where owner_id = tests.user_id('ann@test')), 1::bigint, 'co-members can see my statuses');
select table_privs_are('public', 'task_statuses', 'anon', array[]::text[]);
select ok((select count(*) from public.task_statuses where owner_id is null) = 7, 'built-ins visible to everyone');
```

- [ ] **Step 2: Run to verify it fails**

Run: `pnpm supabase test db`
Expected: FAIL (relation `task_statuses` does not exist).

- [ ] **Step 3: Implement the table, helper, trigger, grants and policies listed in Interfaces.** Label check: `char_length(btrim(label)) between 1 and 50`. Built-in check: `owner_id is not null or archived_at is null`.

- [ ] **Step 4: Generate the schema migration, then the seed migration**

Run: `pnpm supabase db schema declarative sync -f todo_04_statuses --apply`, then `pnpm supabase migration new seed_builtin_statuses`, and write into the new file:

```sql
insert into public.task_statuses (owner_id, label, behavior, sort_order) values
  (null, 'Backlog', 'backlog', 10),
  (null, 'To Do', 'todo', 20),
  (null, 'In Progress', 'in_progress', 30),
  (null, 'Blocked', 'blocked', 40),
  (null, 'In Review', 'in_review', 50),
  (null, 'Completed', 'completed', 60),
  (null, 'Cancelled', 'cancelled', 70);
```

Then run `pnpm supabase migration up`.

- [ ] **Step 5: Run tests**

Run: `pnpm supabase test db`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add supabase/schemas supabase/migrations supabase/tests
git commit -m "feat(db): add built-in and custom task statuses"
```

---

### Task 5: Tasks, status validity, assignees

**Files:**
- Create: `supabase/schemas/41_tasks.sql`
- Modify: `supabase/schemas/50_auth_helpers.sql`, `60_triggers.sql`, `70_policies.sql`
- Test: `supabase/tests/database/40_tasks.test.sql`

**Interfaces:**
- Consumes: `private.has_list_role`, `private.touch_updated_at`, `public.task_statuses` and the built-in `todo` row.
- Produces:
  - table `public.tasks` with the spec's columns, indexes and checks. `status_id` FK is `on delete no action` (Deviation 2).
  - `private.status_usable_in_list(status_id uuid, list_id uuid) returns boolean`: true when the status is built-in, or its owner is a current member of the list with role ≥ editor. Ignores `archived_at`.
- BEFORE triggers on `tasks`, all functions `security definer`. Postgres fires them in name order:
  - `tasks_10_default_status` (insert): if `status_id` is null, set it to the built-in `todo` id.
  - `tasks_20_check_status` (insert or update of `status_id`, `list_id`):
    - on insert, or when `status_id` changed: if the status is not usable → `status cannot be used in this list`; else if it is archived → `archived status cannot be chosen`
    - when only `list_id` changed: the usability check only
  - `tasks_30_check_assignee` (insert or update of `assignee_id`, `list_id`): if `assignee_id` is not null and not a member of `list_id` → `assignee must be a member of the list`.
  - `tasks_90_touch_updated_at` (update).
- AFTER trigger `list_members_clear_assignments` (after delete on `list_members`), security definer: sets `assignee_id = null` on that list's tasks assigned to the removed user.
- Grants to `authenticated`:
  - `select`
  - `insert (id, list_id, title, description, status_id, position, priority, assignee_id, blocked_reason, due_at)`
  - `update (list_id, title, description, status_id, position, priority, assignee_id, blocked_reason, due_at)`
  - `delete`
- Policies:
  - select: `has_list_role(list_id,'viewer')`
  - insert and delete: `has_list_role(list_id,'editor')`
  - update: `using` and `with check` both `has_list_role(list_id,'editor')`, which covers both the old and the new list

- [ ] **Step 1: Write the failing test.** Fixtures:
  - ann owns `Home` and `Work`. In Home, bob is editor and cat is viewer. dan is a stranger.
  - ann's custom statuses are `Waiting for parts` (blocked) and `Old way` (todo). Dan's is `Dan status`, cat's is `Cat status`.
  - as ann: task `T-old` in Home with status `Old way`, then archive `Old way`.

Plan 22:

```sql
-- as ann
insert into public.tasks(list_id, title) values (tests.list_id('Home'), 'T1');
select is((select behavior from public.tasks t join public.task_statuses s on s.id = t.status_id where t.title = 'T1'),
  'todo'::public.status_behavior, 'task without status lands in To Do');
select lives_ok($$do $d$ declare a uuid; b uuid; begin
  for a in select id from public.task_statuses where owner_id is null loop
    for b in select id from public.task_statuses where owner_id is null loop
      update public.tasks set status_id = a where title = 'T1';
      update public.tasks set status_id = b where title = 'T1';
    end loop; end loop; end $d$$$, 'any status can move to any other');
select lives_ok($$insert into public.tasks(list_id,title,status_id) values
  (tests.list_id('Home'),'T2',tests.status_id('Waiting for parts')),(tests.list_id('Work'),'T3',tests.status_id('Waiting for parts'))$$,
  'own custom status works in any of my lists');
select throws_ok($$insert into public.tasks(list_id,title,status_id) values (tests.list_id('Home'),'X',tests.status_id('Dan status'))$$,
  'P0001', 'status cannot be used in this list');
select throws_ok($$insert into public.tasks(list_id,title,status_id) values (tests.list_id('Home'),'X',tests.status_id('Cat status'))$$,
  'P0001', 'status cannot be used in this list');  -- viewer's status
select throws_ok($$update public.tasks set status_id = tests.status_id('Old way') where title = 'T1'$$,
  'P0001', 'archived status cannot be chosen');
select lives_ok($$update public.tasks set list_id = tests.list_id('Work') where title = 'T-old'$$, 'archived status travels with its task');
select throws_ok($$update public.tasks set assignee_id = tests.user_id('dan@test') where title = 'T1'$$,
  'P0001', 'assignee must be a member of the list');
select lives_ok($$update public.tasks set assignee_id = tests.user_id('cat@test') where title = 'T1'$$, 'viewer can be assigned');
delete from public.list_members where user_id = tests.user_id('cat@test');
select is((select assignee_id from public.tasks where title = 'T1'), null, 'removing a member clears their assignments');
select lives_ok($$insert into public.tasks(list_id,title,status_id)
  select tests.list_id('Home'), 'P'||g, tests.status_id('In Progress') from generate_series(1,10) g$$, 'no column limit');
select is((select count(*) from public.tasks where status_id = tests.status_id('In Progress')), 10::bigint, '10 tasks in In Progress');
select throws_ok($$insert into public.tasks(list_id,title) values (tests.list_id('Home'),'  ')$$, '23514', null, 'blank title rejected');
select throws_ok($$insert into public.tasks(list_id,title,priority) values (tests.list_id('Home'),'X',4)$$, '23514', null, 'priority 1-3');
update public.lists set archived_at = now() where name = 'Home';
-- as bob (editor)
select lives_ok($$insert into public.tasks(list_id,title,status_id) values (tests.list_id('Home'),'B1',tests.status_id('Waiting for parts'))$$,
  'editor can use the owner''s custom status (and archived list is editable)');
update public.tasks set title = 'B1 renamed' where title = 'B1';
select isnt_empty($$select 1 from public.tasks where title = 'B1 renamed'$$, 'editor updates tasks in an archived list');
select throws_ok($$update public.tasks set list_id = tests.list_id('Work') where title = 'B1 renamed'$$, '42501', null,
  'editor cannot move a task into a list they do not edit');
-- as cat (re-add cat as viewer first, as postgres)
select isnt_empty($$select 1 from public.tasks$$, 'viewer can read tasks');
select throws_ok($$insert into public.tasks(list_id,title) values (tests.list_id('Home'),'C')$$, '42501', null, 'viewer cannot create');
update public.tasks set title = 'cat was here'; delete from public.tasks;
-- as postgres
select is((select count(*) from public.tasks where title = 'cat was here'), 0::bigint, 'viewer cannot update');
select is((select count(*) from public.tasks where list_id = tests.list_id('Home')) > 0, true, 'viewer cannot delete');
-- as dan
select is_empty($$select 1 from public.tasks$$, 'non-member cannot read tasks');
```

Also add `select table_privs_are('public','tasks','anon',array[]::text[]);` and raise the plan to 23.

- [ ] **Step 2: Run to verify it fails**

Run: `pnpm supabase test db`
Expected: FAIL (relation `tasks` does not exist).

- [ ] **Step 3: Implement the table, helper, triggers, grants and policies listed in Interfaces.** Checks: title `char_length(btrim(title)) between 1 and 500`; `priority between 1 and 3`.

- [ ] **Step 4: Generate, apply, test**

Run: `pnpm supabase db schema declarative sync -f todo_05_tasks --apply && pnpm supabase test db`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add supabase/schemas supabase/migrations supabase/tests
git commit -m "feat(db): add tasks with status and assignee validity"
```

---

### Task 6: Status side effects, history and status guards

**Files:**
- Create: `supabase/schemas/42_task_status_events.sql`
- Modify: `supabase/schemas/60_triggers.sql`, `70_policies.sql`
- Test: `supabase/tests/database/50_status_history.test.sql`

**Interfaces:**
- Consumes: `public.tasks`, `public.task_statuses`, `public.is_terminal`.
- Produces:
  - table `public.task_status_events` with the spec's columns and indexes. Both status FKs are `on delete no action` (Deviation 2).
  - `tasks_40_status_effects`: before insert, or before update of `status_id` `when (old.status_id is distinct from new.status_id)`. Looks up old and new behaviours (security definer). It sets:
    - `status_changed_at = now()`
    - `completed_at`: `now()` when entering a terminal behaviour from non-terminal (or on insert into terminal); cleared when the new behaviour is non-terminal; kept when moving terminal → terminal
    - `blocked_reason`: cleared when the old behaviour was `blocked` and the new one isn't
  - `tasks_after_status_event`: after insert, or after update of `status_id` `when (old.status_id is distinct from new.status_id)`, security definer. Inserts one event with from/to ids and behaviour snapshots. `from_*` is null on insert.
  - `task_statuses_guard_behavior`: before update of behavior `when (old.behavior is distinct from new.behavior)`, security definer. If any task uses the status → `status behavior cannot change while tasks use it`.
- Grants: `select` only to `authenticated`. Policy: select where `exists (select 1 from public.tasks t where t.id = task_id)`, which inherits the tasks viewer policy.

- [ ] **Step 1: Write the failing test.** Fixtures:
  - ann owns `Home` with viewer `vi@test`. Users `st@test` and `dan@test`.
  - ann's statuses: `Shipped` (completed), `Waiting for parts` (blocked), `Unused` (todo).
  - as ann: task `T` in Home.

Plan 24:

```sql
-- as ann
select results_eq($$select from_behavior::text, to_behavior::text from public.task_status_events where task_id = tests.task_id('T')$$,
  $$values (null::text, 'todo'::text)$$, 'insert writes one creation event');
update public.tasks set status_id = tests.status_id('Shipped') where title = 'T';
select isnt((select completed_at from public.tasks where title = 'T'), null, 'custom completed-like status sets completed_at');
-- as postgres: update tasks set completed_at = '2000-01-01' where title = 'T'; as ann:
update public.tasks set status_id = tests.status_id('Cancelled') where title = 'T';
select is((select completed_at from public.tasks where title = 'T'), '2000-01-01'::timestamptz, 'terminal to terminal keeps completed_at');
update public.tasks set status_id = tests.status_id('To Do') where title = 'T';
select is((select completed_at from public.tasks where title = 'T'), null, 'back to To Do clears completed_at');
update public.tasks set status_id = tests.status_id('Blocked'), blocked_reason = 'parts' where title = 'T';
update public.tasks set status_id = tests.status_id('Waiting for parts') where title = 'T';
select is((select blocked_reason from public.tasks where title = 'T'), 'parts', 'blocked to blocked keeps reason');
update public.tasks set status_id = tests.status_id('In Progress') where title = 'T';
select is((select blocked_reason from public.tasks where title = 'T'), null, 'leaving blocked clears reason');
select is((select count(*) from public.task_status_events where task_id = tests.task_id('T')), 7::bigint, 'one event per change');
select results_eq($$select from_behavior::text, to_behavior::text from public.task_status_events
  where task_id = tests.task_id('T') order by id desc limit 1$$, $$values ('blocked','in_progress')$$, 'event snapshots behaviours');
-- as postgres: update tasks set status_changed_at = '2000-01-01' where title = 'T'; as ann:
update public.tasks set status_id = status_id where title = 'T';
select is((select count(*) from public.task_status_events where task_id = tests.task_id('T')), 7::bigint, 'no-op status write: no event');
select is((select status_changed_at from public.tasks where title = 'T'), '2000-01-01'::timestamptz, 'no-op keeps status_changed_at');
-- as postgres: create list Work owned by ann; as ann:
update public.tasks set list_id = tests.list_id('Work') where title = 'T';
select is((select count(*) from public.task_status_events where task_id = tests.task_id('T')), 7::bigint, 'list move without status change: no event');
select throws_ok($$insert into public.task_status_events(task_id,to_status_id,to_behavior) values (tests.task_id('T'),tests.status_id('To Do'),'todo')$$, '42501', null, 'clients cannot insert events');
select throws_ok($$update public.task_status_events set to_behavior = 'todo'$$, '42501', null, 'clients cannot update events');
select throws_ok($$delete from public.task_status_events$$, '42501', null, 'clients cannot delete events');
update public.tasks set status_id = tests.status_id('Shipped') where title = 'T';
select throws_ok($$update public.task_statuses set behavior = 'todo' where label = 'Shipped'$$, 'P0001', 'status behavior cannot change while tasks use it');
select lives_ok($$update public.task_statuses set label = 'Shipped!' where label = 'Shipped'$$, 'label can change while used');
update public.tasks set status_id = tests.status_id('To Do') where title = 'T';
select throws_ok($$delete from public.task_statuses where label = 'Shipped!'$$, '23503', null, 'ever-used status cannot be hard-deleted');
select lives_ok($$update public.task_statuses set archived_at = now() where label = 'Shipped!'$$, 'used status can be archived');
select lives_ok($$delete from public.task_statuses where label = 'Unused'$$, 'never-used status can be deleted');
update public.tasks set list_id = tests.list_id('Home') where title = 'T';
-- as vi
select isnt_empty($$select 1 from public.task_status_events$$, 'viewer reads the list''s events');
-- as st
select is_empty($$select 1 from public.task_status_events$$, 'non-member reads no events');
-- as postgres
select tests.task_id('T') as t_id, tests.list_id('Home') as home_id \gset
delete from public.lists where id = :'home_id';
select is_empty(format('select 1 from public.task_status_events where task_id = %L', :'t_id'), 'deleting a list removes its tasks'' events');
select is_empty(format('select 1 from public.list_members where list_id = %L', :'home_id'), 'deleting a list removes its memberships');
select lives_ok($$delete from auth.users where id = tests.user_id('ann@test')$$, 'deleting a user with tasks in their custom status succeeds');
```

Before that last assertion, as ann, put a task in Work into `Waiting for parts`. This makes the user-deletion cascade cross a used custom status. The plan count is 24.

- [ ] **Step 2: Run to verify it fails**

Run: `pnpm supabase test db`
Expected: FAIL (relation `task_status_events` does not exist).

- [ ] **Step 3: Implement the events table, the three triggers, grants and policy listed in Interfaces.**

- [ ] **Step 4: Generate, apply, test**

Run: `pnpm supabase db schema declarative sync -f todo_06_status_history --apply && pnpm supabase test db`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add supabase/schemas supabase/migrations supabase/tests
git commit -m "feat(db): add status side effects, history and status guards"
```

---

### Task 7: Clean-slate verification and generated types

**Files:**
- Create: `types/database.types.ts` (generated)

**Interfaces:**
- Consumes: everything above.
- Produces: `types/database.types.ts` for the Next.js app.

- [ ] **Step 1: Check that the declarative files and migrations agree**

Run: `pnpm supabase db schema declarative sync -f drift_check --no-apply`
Expected: "No schema changes found" and no new file. If a file is written, the migrations drifted: fix the schema file or the migration, delete the drift file, and re-run.

- [ ] **Step 2: Reset from scratch and run the full suite**

Run: `pnpm supabase db reset && pnpm supabase test db`
Expected: reset applies all seven migrations without error; every test file PASSES.

- [ ] **Step 3: Run the advisors**

Run: `pnpm supabase db advisors`
Expected: no security findings for `public` or `private` objects. Fix any finding (for example a mutable search_path or a missing FK index) in the schema files, then repeat Steps 1–2.

- [ ] **Step 4: Generate types**

Run: `pnpm supabase gen types typescript --local > types/database.types.ts`
Expected: the file contains `task_statuses`, `tasks`, `status_behavior` and `transfer_list_ownership`, and no `tests` or `private` schema.

- [ ] **Step 5: Commit**

```bash
git add types/database.types.ts supabase
git commit -m "chore(db): generate database types"
```
