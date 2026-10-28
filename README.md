# my-claude-sandbox

A sandbox project for working with Claude Code.

## Status

This repo is currently just scaffolding — no application code yet. It contains local editor and Claude Code configuration only.

## Getting Started

First, run the development server:

```bash
npm run dev
# or
yarn dev
# or
pnpm dev
# or
bun dev
```

Open [http://localhost:3000](http://localhost:3000) with your browser to see the result.

You can start editing the page by modifying `app/page.tsx`. The page auto-updates as you edit the file.

This project uses [`next/font`](https://nextjs.org/docs/app/building-your-application/optimizing/fonts) to automatically optimize and load [Geist](https://vercel.com/font), a new font family for Vercel.

## Linting and formatting

This project uses [Biome](https://biomejs.dev) for both.

- `pnpm lint` runs `biome check` with warnings treated as errors.
- `pnpm lint:fix` auto-fixes `app/` and `lib/`.
- `pnpm format` formats the repo.

The Supabase guardrails are GritQL plugins in `scripts/biome-plugins/`, tested by `pnpm test:guard`.

One-time setup so blame skips the Biome reformat commit:

```bash
git config blame.ignoreRevsFile .git-blame-ignore-revs
```

In VS Code, install the recommended Biome extension (`biomejs.biome`). It formats on save.

## Learn More

To learn more about Next.js, take a look at the following resources:

- [Next.js Documentation](https://nextjs.org/docs) - learn about Next.js features and API.
- [Learn Next.js](https://nextjs.org/learn) - an interactive Next.js tutorial.

You can check out [the Next.js GitHub repository](https://github.com/vercel/next.js) - your feedback and contributions are welcome!

## Deploy on Vercel

The easiest way to deploy your Next.js app is to use the [Vercel Platform](https://vercel.com/new?utm_medium=default-template&filter=next.js&utm_source=create-next-app&utm_campaign=create-next-app-readme) from the creators of Next.js.

Check out our [Next.js deployment documentation](https://nextjs.org/docs/app/building-your-application/deploying) for more details.
