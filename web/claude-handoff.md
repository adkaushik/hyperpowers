# Handoff — hyperpowers-web

Marketing site and sign-in portal for the Hyperpowers Claude Code plugin. Lives
at `web/` inside the `adkaushik/hyperpowers` repo (public), alongside the plugin
source in `plugins/`.

## Stack

TanStack Start (file-based router, server functions, full-document SSR),
React 19, Tailwind 4, better-sqlite3, nodemailer, Zod, `marked` for the command
docs. Vite 8 + Nitro for the build.

```bash
npm install
npm run dev          # vite dev --port 3000
npm run typecheck    # tsc --noEmit
npm run build        # vite build -> .output/
node .output/server/index.mjs   # production check
```

## Layout

```
src/routes/__root.tsx        document shell, theme, session in router context
src/routes/index.tsx         landing page (full-document SSR, streamed stats)
src/routes/signin.tsx        email + code sign-in, Zod-validated ?redirect
src/routes/dashboard.tsx     auth-gated, ssr: 'data-only'
src/components/CommandReference.tsx  accordion + anchored index for 26 commands
src/data/commands.ts         command docs: invoke / when / expect / markdown body
src/server/env.ts            all env parsing, server-only boundary
src/server/db.ts             sqlite schema + queries
src/server/session.ts        session tokens, cookie handling
src/server/auth.functions.ts requestCode / verifyCode server functions
src/server/auth-middleware.ts  session resolution for protected routes
src/server/mail.ts           pooled SMTP transporter, verifyMailTransport()
src/server/repo.functions.ts GitHub stats for the landing page
```

Every module under `src/server/` imports `@tanstack/react-start/server-only`
transitively via `env.ts`. Importing one from client code is a build error, not
a runtime surprise. Keep it that way.

## Auth

Passwordless email codes:

1. `requestCode(email)` — generates a six-digit code, stores `sha256(code +
   APP_SECRET)`, 10-minute TTL, sends it over SMTP.
2. `verifyCode(email, code)` — constant-time compare, 5 attempts per code,
   creates the account on first success, sets an HttpOnly session cookie.

Rate limits: 5 codes per email and 20 per IP per 15 minutes.

`?redirect` on `/signin` is validated as site-relative only (no open redirect).
Anonymous hits on `/dashboard` get `307 /signin?redirect=%2Fdashboard`.

## Mail

nodemailer over SMTP, one pooled transporter per process. `requireTLS: true`,
so port 465 uses implicit TLS and everything else must offer STARTTLS —
cleartext connections are refused, verified against a sink with STARTTLS
disabled. Config is `SMTP_URL` or the discrete `SMTP_HOST/PORT/USER/PASS`
variables; the URL wins when both are set.

Without any SMTP config, development prints the code to the server console and
production refuses to start a sign-in. Mail failures log detail server-side and
show the visitor a generic message. `verifyMailTransport()` checks credentials
before a deploy.

## Environment

See `.env.example`. `APP_SECRET` (16+ chars) is required in production and is
the pepper for both codes and session tokens — rotating it invalidates every
outstanding code and session. `DATABASE_PATH` defaults to
`.data/hyperpowers.db`. `GITHUB_TOKEN` is optional and only raises the API rate
limit for the landing page stats.

## Deploying

`NITRO_PRESET` picks the runtime without touching application code. The target
needs a Node filesystem: better-sqlite3 is externalized from the bundle. A
serverless target means swapping the driver behind `src/server/db.ts`, which is
the only module that talks to sqlite.

## The open piece: activation-code claiming

The installer (`npx hyperpowers-claude`, separate package at
`~/Projects/hyperpowers-claude`, not in this repo) prints a one-time activation
code. The user is meant to sign in here, paste the code, and have the portal
return the decryption key for the bundled encrypted plugin payload.

**None of that backend exists yet.** The dashboard says so plainly rather than
faking it with stubs. What still needs building:

- `POST /device/code` — issue an activation code plus device code
- `POST /device/token` — the CLI polls this; returns the key once claimed
- `POST /portal/claim` — signed-in user submits the code; checks a paid
  entitlement before releasing anything
- Code expiry, rate limiting, per-account activation caps
- The decryption key stored as a server-side secret, never logged, never
  returned to an unentitled account

The interim workaround for anyone who has the key is `npx hyperpowers-claude
--key <key>`.

Design decision already locked, do not redesign: one shared decryption key for
the single bundled ciphertext. The activation code is unique per install; the
key is not, and cannot be for one bundled file. This is accepted. Per-install
keys and per-seat caps were explicitly out of scope.

Note that this repo is public, which undercuts the original reason for
encrypting the payload at all. Worth settling before the portal gets built.

## House style

No AI slop in user-facing copy. Specifically: no "X, not Y" headlines, no
aphoristic closers, no em-dashes in prose, no rhetorical triads, no tagline-shaped
section titles. Plain declarative sentences that say what the thing does. The
landing page was rewritten once to remove all of this; do not reintroduce it.
