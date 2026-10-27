# Database Contract

The interface between the database (owned by the `backend` agent) and the Next.js app (owned by the `frontend` agent).

## How to use

- **Backend writes, frontend reads.** The backend updates this file in the same commit as any schema change and regenerates `lib/database.types.ts` with `pnpm db:types`.
- **Types are the source for shapes.** Import `Database` from `@/lib/database.types`. This file covers what types can't express: which columns clients may write, what the RPCs do, and what errors mean.
- **The database enforces every rule.** The frontend may validate early for a better UX, but it must handle the errors below as the real answer.
- **Need something that isn't here?** File a request in `docs/contracts/requests/` (see `_template.md`).
- **Status values:** `planned` (designed in `docs/superpowers/specs/2026-10-27-todo-schema-design.md`, not yet in the database) or `live`.

## Status rule

Never branch on a status's name or id. Branch on `behavior` only:

| Meaning | Behaviours |
| --- | --- |
| Not started | `backlog`, `todo` |
| Active | `in_progress`, `blocked`, `in_review` |
| Done (terminal) | `completed`, `cancelled` |

"Open" means behaviour not in (`completed`, `cancelled`). New tasks start in the built-in `todo` status when `status_id` is omitted.

## Tables and client-writable columns

Everything is for the `authenticated` role. `anon` has no access. Columns not listed under insert/update are set by defaults or triggers.

| Table | Status | Select | Insert columns | Update columns | Delete |
| --- | --- | --- | --- | --- | --- |
| `profiles` | planned | yes | none (created by trigger on sign-up) | `display_name`, `avatar_url` | no |
| `lists` | planned | yes | `id`, `name`, `description`, `owner_id` (must be you) | `name`, `description`, `archived_at` | yes |
| `list_members` | planned | yes | `list_id`, `user_id`, `role`, `invited_by` | `role` | yes |
| `task_statuses` | planned | yes | `id`, `owner_id`, `label`, `behavior`, `sort_order` | `label`, `behavior`, `sort_order`, `archived_at` | yes |
| `tasks` | planned | yes | `id`, `list_id`, `title`, `description`, `status_id`, `position`, `priority`, `assignee_id`, `blocked_reason`, `due_at` | `list_id`, `title`, `description`, `status_id`, `position`, `priority`, `assignee_id`, `blocked_reason`, `due_at` | yes |
| `task_status_events` | planned | yes | none (written by trigger) | none | no |

Notes:
- `lists.owner_id` cannot be updated. Use `transfer_list_ownership`.
- `lists.archived_at` is a display flag only. Archived lists stay fully readable and editable.
- Labels are stored trimmed. `" To Do "` collides with the built-in.
- Row visibility follows list membership (`viewer` < `editor` < `owner`).

## RPCs

| Function | Status | Signature | Notes |
| --- | --- | --- | --- |
| `transfer_list_ownership` | planned | `(list_id uuid, new_owner uuid) returns void` | Caller must be the list owner. The new owner must already be a member. Transferring to yourself is a no-op. Call with `supabase.rpc("transfer_list_ownership", { list_id, new_owner })`. |

## Error catalogue

Custom raises use SQLSTATE `P0001` with these exact messages:

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
