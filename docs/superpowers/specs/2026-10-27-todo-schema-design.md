# To-Do App — Core Supabase Schema Design

Oct 27, 2026 · Status: draft for review

## Intent

The product spec (To-Do App — Product Spec, Oct 27, 2026) describes one calm place for everything a busy person needs to do, across every part of life. This document designs the **database core** that the rest of the app sits on: who owns what, how tasks are grouped, how statuses work, and who may see or change what.

Two things make this core different from Any.do, which offers little more than "open" and "done":

1. **Statuses people can make their own.** Seven built-in statuses ship with the app. A user can create a new one on the spot from the status dropdown ("Create a new status"). Each custom status *works like* one of the seven, so every feature built later (Today view, AI assistant, reports) understands it without knowing its name.
2. **Lists are whatever the user wants them to be.** An area of life, a category, a project, a type of work. The app does not impose a structure.

The schema must let sharing, per-list status settings, steps, reminders and repeats arrive later as **additions**, never as rewrites of what ships now.

## Goals

- Users create as many lists as they like, with free-form names.
- Every task belongs to exactly one list and has exactly one status.
- New tasks start in **To Do**.
- Users create custom statuses from the dropdown with nothing more than a name and a "works like" choice.
- Any status may move to any other.
- Every status change is recorded, for later reporting (cycle time, time spent blocked).
- The sharing model (owner, editor, viewer) is in the schema from day one, so turning sharing on later means inserting rows, not changing tables or policies.
- The database enforces every rule itself, so the web app, scripts and the future phone app all behave the same.

## Non-goals (this design)

- Steps inside a task, reminders and repeating tasks. They are launch must-haves in the product spec but get **their own design pass next**. They will be new tables pointing at `tasks`. Nothing here should need to change for them.
- Sharing UI, invitations (`list_invitations`, `accept_invitation`) and Realtime.
- Per-list status settings: hiding, renaming or reordering statuses per list, or a per-list starting status. See "Later".
- Any limit on how many tasks may sit in a status or column. **Explicitly removed** from the original input.
- Rules about which status may move to which.

## Anti-goals

- **A bossy app.** No column limits, no transition rules, nothing that refuses a reasonable move. "One calm place" beats enforced process.
- **A schema that has to be rebuilt for sharing.** If turning on sharing needs a table change or a policy rewrite, the design failed.
- **Features that break on custom statuses.** No code or query may test a status by its name or id to decide behaviour. It must test the status's *behaviour*.

## Decisions

| Topic | Decision | Notes |
| --- | --- | --- |
| Lists | Free-form; a list is a name plus an optional description. "Areas of life" in the product spec are lists. | User decision |
| Ownership and sharing | `lists.owner_id` plus `list_members` from day one; the owner is a member with role `owner` | From input |
| Roles | Enum `list_role`: `viewer` < `editor` < `owner` | From input |
| Default status | **To Do** | User decision; replaces the input's Backlog |
| Status behaviours | Fixed enum `status_behavior` with seven values, one per built-in status | User accepted "works like" |
| Custom statuses | Owned by a **user**, not a list; available in all that user's lists immediately | User accepted |
| Transitions | Unrestricted | From input |
| Column limits | None | User decision; WIP limit removed |
| Priority | `smallint` 1–3 (3 = High, 2 = Medium, 1 = Low), null = none | Claude's call, from the product spec's High/Medium/Low |
| Ordering | `position double precision` within `(list_id, status_id)` | From input |
| History | `task_status_events` written by trigger | From input |
| Auth helpers | `SECURITY DEFINER` functions in a `private` schema, called from policies as `(select ...)` | From input |
| Schema management | Declarative files in `supabase/schemas/`, diffed into migrations | From input |

## How statuses work

### Behaviours

`status_behavior` is a Postgres enum with exactly these values, in this order:

`backlog`, `todo`, `in_progress`, `blocked`, `in_review`, `completed`, `cancelled`

An enum fits here, unlike for statuses themselves, because behaviours are defined by code (triggers, the AI assistant, the Today view), so the set is fixed and changes only when code does.

Derived meanings, used everywhere instead of names:

| Meaning | Behaviours |
| --- | --- |
| Not started | `backlog`, `todo` |
| Active | `in_progress`, `blocked`, `in_review` |
| Done (terminal) | `completed`, `cancelled` |

"Open tasks" means behaviour not in (`completed`, `cancelled`). A SQL helper such as `public.is_terminal(status_behavior)` (immutable) keeps this in one place. *Claude's call.*

### Built-in statuses

Seven rows in `task_statuses` with `owner_id` null, one per behaviour. Seeded by a hand-written migration, because declarative diffs do not capture inserted rows. Not in `seed.sql`, which runs only locally.

| behavior | label | sort_order | Meaning |
| --- | --- | --- | --- |
| backlog | Backlog | 10 | An idea or "someday" task, not planned yet |
| todo | To Do | 20 | Planned and ready to start |
| in_progress | In Progress | 30 | Started |
| blocked | Blocked | 40 | Waiting on someone or something |
| in_review | In Review | 50 | Done but needs a check first |
| completed | Completed | 60 | Finished |
| cancelled | Cancelled | 70 | Dropped on purpose; kept for the record |

### Custom statuses

- Created from the dropdown with a **label** and a **behaviour** ("works like"). The UI may pre-select a behaviour; the database requires one.
- Owned by the creating user (`owner_id`) and usable in **any list that user owns or edits**. See "Status validity" for the exact rule.
- Labels are unique per owner, case-insensitively, and may not duplicate a built-in label. For example, a user cannot create a second "To Do". *Claude's call.*
- Default `sort_order` places a custom status just after the built-in it works like, for example "Waiting for parts" (blocked) at 41. The database fills this in when the client omits it. *Claude's call.*
- **Retiring a status:** a custom status can be archived (`archived_at`). It leaves the dropdown, and tasks already in it keep it until moved. A hard delete is allowed only if no task or status event has ever used it, because the foreign keys are `on delete restrict`. *Claude's call; keeps history intact.*
- **Changing behaviour:** allowed only while no task currently uses the status. Otherwise the derived fields (`completed_at`, `blocked_reason`) would silently disagree with the new behaviour. Renaming is always allowed. *Claude's call.*

### Which statuses a list's board shows (v1)

Not a schema concern, noted for the builder of the UI. Until per-list settings exist, a board shows the seven built-ins plus the viewing user's own non-archived custom statuses, plus any other status a task in that list currently uses. That last case only arises once sharing exists.

## Tables

All tables are in `public` except the helper functions (`private`). Every timestamp is `timestamptz`. Every foreign key column has an index.

### profiles

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| id | uuid | no | | PK; FK `auth.users(id)` on delete cascade |
| display_name | text | yes | | Shown to collaborators |
| avatar_url | text | yes | | |
| created_at | timestamptz | no | now() | |

### lists

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| id | uuid | no | gen_random_uuid() | PK |
| owner_id | uuid | no | auth.uid() | FK `auth.users(id)` on delete cascade |
| name | text | no | | Check: 1–200 characters after trimming |
| description | text | yes | | |
| archived_at | timestamptz | yes | | Soft archive; null = active |
| created_at | timestamptz | no | now() | |
| updated_at | timestamptz | no | now() | Set by trigger |

**Archiving tucks a list away; it does not freeze it.** An archived list is hidden from the app's main navigation, but its tasks stay fully readable and editable by the same roles, and the owner can unarchive it at any time. No policy, trigger or helper looks at `archived_at`; it is purely a display flag. *User decision.*

No built-in "kind" or "type" column: a list's name is all the structure the user asked for. Colour, icon and sidebar order are UI additions for later.

### list_members

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| list_id | uuid | no | | PK part 1; FK `lists(id)` on delete cascade |
| user_id | uuid | no | | PK part 2; FK `auth.users(id)` on delete cascade |
| role | list_role | no | 'editor' | |
| invited_by | uuid | yes | | FK `auth.users(id)` on delete set null |
| created_at | timestamptz | no | now() | |

Indexes: unique `(list_id) where role = 'owner'`; `(user_id, list_id)`.

### task_statuses

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| id | uuid | no | gen_random_uuid() | PK |
| owner_id | uuid | yes | | FK `auth.users(id)` on delete cascade; **null = built-in** |
| label | text | no | | Check: 1–50 characters after trimming |
| behavior | status_behavior | no | | What the status works like |
| sort_order | smallint | no | | Set by trigger when omitted (see Custom statuses) |
| archived_at | timestamptz | yes | | Custom statuses only |
| created_at | timestamptz | no | now() | |

Indexes:
- unique `(behavior) where owner_id is null`: one built-in per behaviour, and the lookup for "the built-in To Do"
- unique `(owner_id, lower(label)) nulls not distinct`
- `(owner_id)`

Check: built-ins have `archived_at` null.

**On delete cascade of `owner_id`:** if a user is deleted, their custom statuses go too. In v1 their lists go with them, so nothing dangles. Once sharing exists, a deleted user's status could still be used on a shared list's tasks. The `restrict` foreign key from `tasks` would then block the user deletion. The sharing design must decide what happens, for example reassigning those tasks to the built-in with the same behaviour. *Flagged for the sharing pass.*

### tasks

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| id | uuid | no | gen_random_uuid() | PK |
| list_id | uuid | no | | FK `lists(id)` on delete cascade |
| title | text | no | | Check: 1–500 characters after trimming |
| description | text | yes | | The spec's "note" |
| status_id | uuid | no | | FK `task_statuses(id)` on delete restrict; set to built-in To Do by trigger when null |
| position | double precision | no | 0 | Order within `(list_id, status_id)` |
| priority | smallint | yes | | Check: 1–3 |
| assignee_id | uuid | yes | | FK `auth.users(id)` on delete set null |
| created_by | uuid | yes | auth.uid() | FK `auth.users(id)` on delete set null |
| blocked_reason | text | yes | | "What are you waiting on?" Cleared on leaving a blocked-behaviour status |
| due_at | timestamptz | yes | | |
| status_changed_at | timestamptz | no | now() | Set by trigger |
| completed_at | timestamptz | yes | | Set or cleared by trigger |
| created_at | timestamptz | no | now() | |
| updated_at | timestamptz | no | now() | Set by trigger |

Indexes: `(list_id, status_id, position)`; `(status_id)`; `(assignee_id)`; `(created_by)`.

`status_id` is nullable on input only in the sense that the trigger fills it before the not-null check. The column itself is `not null`, and a `BEFORE INSERT` trigger assigns the default.

### task_status_events

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| id | bigint | no | identity | PK |
| task_id | uuid | no | | FK `tasks(id)` on delete cascade |
| from_status_id | uuid | yes | | FK `task_statuses(id)` on delete restrict; null on creation |
| to_status_id | uuid | no | | FK `task_statuses(id)` on delete restrict |
| from_behavior | status_behavior | yes | | Snapshot at the time of the change; null on creation |
| to_behavior | status_behavior | no | | Snapshot at the time of the change |
| changed_by | uuid | yes | auth.uid() | FK `auth.users(id)` on delete set null |
| changed_at | timestamptz | no | now() | |

Indexes: `(task_id, changed_at)`; `(from_status_id)`; `(to_status_id)`.

The behaviour snapshots mean reports such as "time spent blocked" stay true even if a custom status's behaviour is later changed while unused. *Claude's call.*

## Business rules

All enforced in the database.

1. **New user → profile.** An insert on `auth.users` creates the `profiles` row. `display_name` is taken from `raw_user_meta_data` if present. *Claude's call.*
2. **New list → owner membership.** After a `lists` insert, `(list_id, owner_id, 'owner')` is added to `list_members`.
3. **One owner, always.** The partial unique index allows at most one owner. A trigger stops the owner's membership row from being deleted or downgraded, except from inside `transfer_list_ownership`, for example via a transaction-local setting the function sets. When a list itself is deleted, the cascade must still be allowed to remove the owner row.
4. **Ownership transfer.** RPC `public.transfer_list_ownership(list_id uuid, new_owner uuid)`, `SECURITY DEFINER`:
   - Only the current owner may call it.
   - `new_owner` must already be a member.
   - The old owner becomes `editor`.
   - `lists.owner_id` is updated.
   - All in one transaction.
5. **Default status.** A task inserted without `status_id` gets the built-in `todo` status.
6. **Status validity.** A task's status must be a built-in, or a non-archived custom status owned by a current member of the task's list with role editor or higher. Checked on insert and on update of `status_id`. On a change of `list_id` alone, the status is re-checked only for ownership: an archived status may travel with the task. An archived status already on a task may stay there; it just can't be newly chosen. In v1 this reduces to "built-in or mine". Once sharing exists, editors on a shared list can use each other's statuses. *Claude's call.*
6a. **Assignee is a member.** `assignee_id`, when set, must be a current member of the task's list (any role). Checked on insert and on update of `assignee_id` or `list_id`. Removing someone from a list clears their assignments on that list's tasks. *Claude's call.*
7. **Any transition allowed.**
8. **Status side effects**, all based on behaviour, on insert and on change of `status_id`:
   - Set `status_changed_at = now()`.
   - Entering a terminal behaviour from a non-terminal one sets `completed_at = now()`. Moving to a non-terminal behaviour clears it. Moving between two terminal statuses keeps the original `completed_at`.
   - Leaving a `blocked`-behaviour status for a non-blocked one clears `blocked_reason`. Moving between two blocked-behaviour statuses keeps it.
9. **Status history.** Every insert and every change of `status_id` writes one `task_status_events` row. The trigger runs `AFTER`, as `SECURITY DEFINER`, because clients have no insert rights on the table. Moving a task to another list without changing its status writes no event.
10. **Custom status guards.**
    - Built-ins cannot be inserted, updated or deleted by clients.
    - A custom status's `behavior` cannot change while any task uses it.
    - Hard delete fails, through the foreign keys, if the status was ever used.
    - A custom label may not match a built-in label, case-insensitively. The unique index only covers one owner's own labels, so a trigger checks this.
11. **Timestamps.** `updated_at` is maintained on `lists` and `tasks`.

## Access control

RLS is on for every table. `anon` has no grants; everything below is for `authenticated`.

| Table | Read | Create | Update | Delete |
| --- | --- | --- | --- | --- |
| lists | Any member | Anyone, with `owner_id` = themselves | Owner | Owner |
| list_members | Members of the same list | Owner | Owner (role changes) | Owner; or a non-owner removing themselves |
| tasks | Viewer and up | Editor and up | Editor and up, in both the old and the new list | Editor and up |
| task_statuses, built-in | Everyone | Nobody | Nobody | Nobody |
| task_statuses, custom | Its owner; and anyone who shares a list with its owner | Anyone, with `owner_id` = themselves | Owner | Owner (subject to rule 10) |
| task_status_events | Viewer and up of the task's list | Triggers only | Nobody | Nobody |
| profiles | Yourself, and anyone you share a list with | Trigger only | Yourself | Nobody |

The second read clause on custom statuses ("shares a list with its owner") does nothing in v1. It is there so that sharing needs no policy change: a collaborator can see and pick your "Waiting for parts" on a shared list, matching rule 6. Status labels are not sensitive, so seeing a co-member's statuses beyond that one list is acceptable. *Claude's call.*

Helpers, all `SECURITY DEFINER`, `STABLE`, `set search_path = ''`, in schema `private`, which is not exposed through the API:

- `private.list_role_of(list_id uuid) returns list_role`: the caller's role, or null
- `private.has_list_role(list_id uuid, min_role list_role) returns boolean`
- `private.can_read_status(status_id uuid) returns boolean`: for the custom-status read policy

Policies call them as `(select private.has_list_role(list_id, 'editor'))`.

## Later, as additions

Each item below is a new table or function. None changes a table above.

| Addition | Shape |
| --- | --- |
| Per-list status settings | `list_statuses (list_id, status_id, hidden, label_override, sort_order, is_default)`: hide, rename or reorder per list, and a per-list starting status. Also the natural place for an optional per-list nudge if column limits are ever wanted. When it lands, rule 5 checks it first and falls back to built-in To Do. |
| Sharing statuses in shared lists | Comes with `list_statuses`: members can see and pick statuses enabled on the list |
| Invitations | `list_invitations` plus `accept_invitation` RPC |
| Steps | `task_steps (task_id, …)` |
| Reminders and repeats | Their own design pass; tables pointing at `tasks` |
| Realtime | `alter publication supabase_realtime add table tasks` |

## Delivery

Declarative files in `supabase/schemas/`, applied alphabetically:

| File | Contents |
| --- | --- |
| 00_schemas.sql | `create schema private` |
| 10_types.sql | `list_role`, `status_behavior` enums |
| 20_profiles.sql | profiles |
| 30_lists.sql | lists |
| 31_list_members.sql | list_members |
| 40_task_statuses.sql | task_statuses |
| 41_tasks.sql | tasks |
| 42_task_status_events.sql | task_status_events |
| 50_auth_helpers.sql | `private.*` functions, `public.is_terminal` |
| 60_triggers.sql | trigger functions and triggers |
| 65_rpc.sql | `transfer_list_ownership` |
| 70_policies.sql | RLS, grants, policies |

Steps:
1. Set `schema_paths = ["./schemas/*.sql"]` in `supabase/config.toml` (currently `[]`).
2. `pnpm supabase db diff -f todo_init`.
3. Hand-write a second migration seeding the seven built-in statuses.
4. `pnpm supabase db reset`, then `pnpm supabase gen types typescript --local`.
5. pgTAP tests in `supabase/tests/`, run with `pnpm supabase test db`.

The project uses pnpm for everything and Postgres 17 (`major_version = 17`), so `nulls not distinct` is available.

## Acceptance criteria

Each is a pgTAP test passing on a freshly reset local database.

**Accounts and lists**
- [ ] Signing up creates a profile.
- [ ] Creating a list makes the creator its owner member.
- [ ] A non-member cannot read a list, its tasks or its members.

**Roles and membership**
- [ ] A viewer can read tasks but cannot create, update or delete them.
- [ ] An editor can manage tasks but cannot add, remove or change members.
- [ ] An editor cannot move a task into a list where they are not an editor.
- [ ] A member can leave a list; the owner cannot remove or downgrade themselves.
- [ ] `transfer_list_ownership` leaves exactly one owner, updates `lists.owner_id`, and turns the old owner into an editor.
- [ ] Deleting a list removes its memberships, tasks and events.

**Statuses**
- [ ] A task created without a status lands in To Do.
- [ ] A task can move from any status to any other.
- [ ] A user can create a custom status and use it in any of their lists.
- [ ] A task cannot use a custom status owned by someone who isn't an editor-or-higher member of its list, nor newly pick an archived one.
- [ ] An editor on a list can use the owner's custom status (sharing simulated by inserting a `list_members` row).
- [ ] A task cannot be assigned to a non-member; removing a member clears their assignments in that list.
- [ ] A task in an archived custom status can move to another list without changing status.
- [ ] A custom status that works like Completed sets `completed_at` on entry, the same as the built-in. Moving back to To Do clears it.
- [ ] Moving out of any blocked-behaviour status clears `blocked_reason`. Moving between two blocked-behaviour statuses keeps it.
- [ ] A custom status's behaviour cannot change while a task uses it; its label can.
- [ ] A used custom status cannot be hard-deleted, but can be archived.
- [ ] Duplicate labels (case-insensitive, including built-in labels) are rejected for the same user.
- [ ] Every insert and every status change writes exactly one `task_status_events` row, with the behaviours at that moment.
- [ ] Clients cannot insert, update or delete built-in statuses or status events.
- [ ] Moving a task into a column has no count limit: 10 tasks can sit in In Progress in one list.

## Left to the builder

- Exact names of trigger functions and indexes.
- How rule 3's "except inside the transfer" is signalled.
- Test file layout and fixtures. Use `tests.create_supabase_user`-style helpers or equivalent.
- Error codes and messages, as long as each rule raises a distinct, readable error.
