# To-Do App — MVP Product Design

Oct 28, 2026 · Status: draft for review

## Intent

One calm place for everything a busy person needs to do. The win is **opening the app and not having to think**: the first screen already says what needs you next, so you never scan lists or rebuild the plan in your head.

The goal right now is speed. First get a simple, good-looking version 1 working on the owner's machine (Phase 1). Then put it on the internet for the owner and a handful of testers, with automatic checks and deployment (Phase 2). Grow from there. Any.do is the reference for feel (fast, calm, satisfying to tick things off), with a warmer, more stylish look.

The database for this app already exists locally (see `docs/superpowers/specs/2026-10-27-todo-schema-design.md` and `docs/contracts/db-contract.md`). Phase 1 is mostly the web app on top of it.

## Who it's for

- **Phase 1:** the owner, running it locally.
- **Phase 2 onward:** the owner plus a handful of invited testers.
- **Later:** anyone, once sharing and the assistant arrive.

## What success looks like

- **Phase 1:** the owner uses it locally every day, and it feels good to use.
- **Phase 2:** it's live on the owner's domain, testers can sign in, and merging to `main` ships to production with no manual steps.
- Throughout:
  - Opening it shows what to do next within a few seconds, without clicking anything.
  - Adding a task takes one line of typing.
  - Testers say it feels nice to use, not just functional.

---

# Phase 1: MVP (runs locally)

## Goals

1. **Sign in by email link.** No passwords. Locally, the link arrives in the local Supabase mail catcher (Mailpit, opened from `pnpm supabase status`), not a real inbox. The login form never creates accounts. Locally, accounts are created through Supabase Studio's "invite user" or a seed script.
2. **"Next up" is the home screen.** It pulls from all active (not archived) lists and shows these groups, in this order:
   - **Overdue:** open tasks whose due date has passed, with how late they are ("2 days late").
   - **Today:** open tasks due today, with a time if one is set.
   - **Keep it moving:** tasks in progress, blocked or in review, with how long they've been there ("Blocked 6 days") and the blocked reason if one was given.
   - **Suggested from your history:** at most 3 suggestions (see goal 7).

   Above the groups is a header with the weekday, the date and a count ("7 things need you").
3. **Quick add that understands plain text.** One input sits at the top of Next up and of every list. Typing `pay rent fri !high #home` sets:
   - **the due date:** `today`, `tomorrow`, weekday names, `next week`, simple dates like `nov 3`, and an optional time like `5pm`
   - **the priority:** `!high`, `!med`, `!low`
   - **the list:** `#name`, matched to an existing active list. With no match, the task goes to the starter list.

   Chips under the input show how the text was read before Enter is pressed. Anything the parser doesn't recognise stays in the title.
4. **Lists.** Create, rename and archive, all from the sidebar. The sidebar shows:
   - Next up
   - All tasks
   - each active list, with its count of open tasks
   - a collapsed "Archived" group at the bottom, for reopening and unarchiving lists

   New users get one list, "Personal", so quick add always has somewhere to go.
5. **Tasks.** Each task has a title, a note, a due date (with an optional time), a priority (High, Medium, Low or none) and a status from the 7 built-in statuses.
   - Clicking a task opens it for editing in a side panel, or a full-screen sheet on phones. Delete is in the panel.
   - List and All tasks pages show open tasks. A collapsed "Completed" section at the bottom lets you reopen a task.
6. **Completing feels good.** Ticking the circle marks the task Completed with a short check animation, then it slides out. An "Undo" toast shows for a few seconds.
7. **Suggestions follow simple rules, with no AI.** There are two kinds:
   - **Rhythm:** a task you've completed 3 or more times at a roughly regular interval, now due again ("You add this about every 3 months. Last time was Jul 26."). The action is "Add for today", which creates a fresh task.
   - **Stale:** an open task in To Do or Backlog with no due date, untouched for 14+ days ("In To Do for 23 days without a date."). The actions are "Do today", which sets the due date to today, and "Move to Backlog".

   For both kinds:
   - Each suggestion shows a one-line reason, in plain words, for why it's there.
   - "Not now" hides a suggestion for 7 days, and the dismissal is saved in the database.
8. **Daylight look.** Airy, cool-grey surfaces, a coral accent, and a rounded, friendly display typeface paired with a clean body typeface. See option A in the mockup: https://claude.ai/code/artifact/8f3771c0-aa22-4b62-83ca-8455de378ca5. It supports light and dark, following the device setting.
9. **Works in a phone browser.** On narrow screens the sidebar collapses into a menu. No native app.

## Non-goals (Phase 1)

- Anything on the internet: hosting, a domain, real email delivery, CI/CD. That's all Phase 2.
- Reminders and notifications, repeating tasks, steps inside a task.
- Custom statuses. The database supports them, but there's no UI yet.
- Board, calendar or table views; drag-and-drop ordering.
- Sharing, invitations, assignees, live updates.
- Any AI, including the assistant and AI suggestions.
- Voice input, calendar sync, native mobile apps.
- A design system. Use stock shadcn components, styled only through the theme.

## Anti-goals

Even if everything works, the MVP has failed if:

- **It's a list app with a dashboard bolted on.** Next up must be the reason to open it.
- **It nags.** No red badges, guilt counters or forced daily planning ritual. Suggestions are optional and easy to dismiss.
- **It's slow to add a task.** If adding needs a form, it's wrong.
- **It looks like a generic admin template.** Stock components are fine; an unstyled default look is not.
- **Shipping waits on polish.** Getting it working comes before extra features.

---

# Phase 2: Deployment and CI/CD

## Intent

Put the Phase 1 app on the owner's domain for the owner and a handful of testers. Every change goes through a pull request with automatic checks. Merging to `main` updates the hosted database and the live site, with no manual steps.

## Starting point

- GitHub repo: `bee-squared/my-claude-sandbox`, with no workflows yet.
- A hosted Supabase project exists, but this repo's migrations have never been applied to it.
- No Vercel account, domain or email sender yet.

## How it fits together

- **Pull request:** GitHub Actions runs every check, against a throwaway local database inside the CI run. Vercel also builds a preview link for the PR.
- **Merge to `main`:** GitHub Actions runs the checks again. It then applies new migrations to the hosted Supabase project, and only after that deploys the site to Vercel production. Running these in order means the live site never runs code against a database that isn't ready for it.
- **Secrets** live only in GitHub and Vercel settings, entered by the owner. Nothing secret is committed, and no agent edits `.env*` files.

## Steps for the owner (accounts and settings; Claude can't do these)

Do these in order. Each one notes what it unlocks.

1. **Gather the Supabase details.** From the hosted project's dashboard, note:
   - the project reference
   - the database password
   - the project URL
   - the anon (public) key

   Also create a personal access token at supabase.com → Account → Access Tokens.
2. **Add GitHub repository secrets.** Under Settings → Secrets and variables → Actions, add:
   - `SUPABASE_ACCESS_TOKEN`
   - `SUPABASE_DB_PASSWORD`
   - `SUPABASE_PROJECT_ID`
3. **Create a Vercel account** by signing in with GitHub, then import `my-claude-sandbox`. Vercel detects Next.js and pnpm.
   - Add environment variables for Production and Preview: `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY`.
   - Turn off automatic production deploys from Git, so production only ships after migrations. Keep preview deploys on.
4. **Connect GitHub to Vercel for production deploys.**
   - Create a Vercel access token.
   - Note the Vercel org ID and project ID. Running `vercel link` writes both to `.vercel/project.json`.
   - Add them as GitHub secrets: `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`.
5. **Buy a domain** from any registrar (Vercel sells them too). Add it to the Vercel project and follow Vercel's DNS instructions until it shows as valid.
6. **Set up email sending.**
   - Create a Resend account, or a similar provider, and add the domain.
   - Add the DNS records Resend gives you (SPF and DKIM) and wait until it shows as verified.
   - In Supabase → Authentication → Emails → SMTP settings, enter Resend's SMTP details and a sender address such as `hello@yourdomain`.
7. **Configure Supabase Auth on the hosted project.**
   - Set the Site URL to `https://yourdomain`.
   - Add these redirect URLs: `https://yourdomain/**` and the Vercel preview pattern for your team (`https://*-<team>.vercel.app/**`).
   - Turn off "Allow new users to sign up".
   - Optionally, edit the magic-link email to match the app's tone.
8. **Protect `main`.** Under Settings → Branches (or Rulesets), require a pull request and require the "CI" checks to pass before merging.
9. **Invite testers** from Supabase → Authentication → Users → Invite.

## What gets built in the repo (Claude, after the owner's steps 1–4)

1. **CI workflow** (`.github/workflows/ci.yml`). It runs on every pull request and every push to `main`:
   - install with pnpm, using the version pinned in the repo, with caching
   - lint and type-check
   - ownership guard tests (`pnpm test:guard`)
   - production build
   - start a local Supabase inside CI, apply every migration, run the pgTAP tests (`pnpm supabase test db`), and confirm `lib/database.types.ts` matches the schema (`pnpm db:types:check`)
2. **Deploy workflow** (`.github/workflows/deploy.yml`). It runs on push to `main`, only after CI passes, and one run at a time:
   - link to the hosted project and apply new migrations (`supabase db push`)
   - build and deploy to Vercel production with the Vercel CLI
   - if the migration step fails, skip the deploy
3. **A dry run first.** The first time, run the migration step with `--dry-run` so the owner can see what will be applied to the hosted project. The full set of existing migrations, including the seeding of the 7 built-in statuses, goes out together.
4. **A short `docs/deployment.md`** that records the steps above, which secrets exist and where, and how to roll back. Rolling back means promoting the previous Vercel deployment and writing a new migration that reverses the change. Hosted migrations are never edited.

## Phase 2 success checks

- A PR with a failing test can't be merged.
- Every PR gets a working preview link.
- After merging a PR that adds a migration, the hosted database has it before the new site goes live.
- A tester invited from the dashboard gets a branded email from the owner's domain and can sign in on the live site.
- Someone who wasn't invited can't create an account.

## Notes and risks

- **Previews share the production database.** For a handful of testers this is fine. A preview built from a PR that needs a *new* migration will fail on those parts until it's merged. Separate preview databases (Supabase branching, a paid feature) are a later option.
- **Agents still can't touch the hosted database.** The `backend` agent's guard blocks `db push` and `--linked`, and that stays. Only the deploy workflow pushes migrations.
- **The Supabase CLI version in CI** should match the one in `package.json` (2.120), so CI generates the same types as local.

---

# Constraints (all phases)

- **Use what's already built.** The Next.js 16 app in this repo, Tailwind 4, and Supabase with the existing schema. Use pnpm for everything.
- **The database enforces the rules.** The app never re-implements access or status rules as the source of truth. It treats database errors as the real answer (see the contract's error catalogue).
- **Never decide by status name.** "Open", "active" and "done" come from a status's *behaviour*, never its label or id (a schema anti-goal). This matters for Next up and suggestions.
- **Team roles.**
  - Database changes go through the `backend` agent.
  - App code goes through the `frontend` agent.
  - The orchestrator handles dependencies, config, workflows and deployment docs (see `CLAUDE.md`).
  - Schema changes land before the app work that needs them.
- **Next.js has changed.** Read the guides in `node_modules/next/dist/docs/` before using any Next.js API (see `AGENTS.md`).

# Decisions

| Topic | Decision | Source |
| --- | --- | --- |
| Home screen | Next up, as in mockup option A | User |
| Suggestions | Rule-based in the MVP; AI later | User accepted |
| Who signs in | The owner, then a handful of invited testers | User |
| Look | Daylight (option A) | User |
| Component library | shadcn, with no custom design system | User |
| Phase 1 | Runs locally only | User |
| Phase 2 | Deployment: Vercel, domain, GitHub Actions CI/CD | User |
| Supabase | The existing hosted project is used for production | User |
| Sign-in method | Email magic link | Claude's call, accepted in playback |
| Hosting | Vercel | Claude's call, accepted in playback |
| Email provider | Resend, through Supabase's SMTP settings | Claude's call; any SMTP provider works |
| Production deploys | From GitHub Actions after migrations, not from Vercel's Git integration; Vercel still builds PR previews | Claude's call; keeps database changes ahead of code |
| Preview database | Previews use the production Supabase project | Claude's call; acceptable at tester scale |
| Starter list | Every new user gets "Personal", created by the database when the account is made | Claude's call |
| "Keep it moving" scope | All active behaviours: in progress, blocked and in review | Claude's call; otherwise in-review tasks never show up |
| Adding testers | Through the Supabase dashboard; no in-app admin screen. The login form never creates accounts | Claude's call |
| Archived lists | Left out of Next up, All tasks, suggestions and `#list` matching; reopened from the sidebar's Archived group | Claude's call |
| Completed tasks | Kept in a collapsed "Completed" section on list pages, where they can be reopened | Claude's call |
| Stale rule | To Do or Backlog, with no due date, untouched for 14+ days | Claude's call; tune after testing |
| "Not now" | Hides a suggestion for 7 days | Claude's call |
| Rhythm rule | The same title (ignoring case and spacing) completed 3+ times | Claude's call; tune after testing |
| Unmatched `#list` | Goes to the starter list, with a chip saying so | Claude's call |

# Future phases

Each phase ships on its own. The order can change after tester feedback.

**Phase 3: Daily habits.**
- Reminders (in-app and email) and repeating tasks. These need their own design pass, as the schema spec planned.
- Steps inside a task.
- Custom statuses from the status dropdown ("works like…").
- A board view per list, with drag to reorder. The database already stores positions.

**Phase 4: The assistant.**
- Type or talk to an agent that sets up tasks. For example, "remind me to renew my passport before the March trip" becomes a task with a sensible date and list.
- AI suggestions that build on the MVP's rules and the status history the database keeps.
- A connector so Claude or ChatGPT can add and update tasks. Each task is labelled with where it came from.

**Phase 5: Sharing.**
- Invitations, shared lists, assignees and live updates.
- The schema already has roles and membership. Invitations still need their design pass (see the schema spec's open items).
- Separate preview databases, if more people start contributing.

**Later.** Native mobile apps and calendar sync.

# Left to the builder

- The exact fonts and colours within the Daylight direction, and the animation details.
- How plain-text dates are parsed (a library is fine), and how a date-only due date versus a timed one is stored in `due_at`, including time zones.
- Whether suggestions are computed in the database or in the app, as long as the rules above hold and status checks use behaviour.
- How dismissals and the starter list are stored. These need small schema additions, requested through `docs/contracts/requests/`.
- Page structure, loading states and empty states. Every screen needs a friendly empty state ("Nothing needs you right now").
- Exact workflow details: action versions, caching, job names. The required check names must match the branch protection rule.
