# Handoff — hyperpowers-web

Marketing site and sign-in portal for the Hyperpowers Claude Code plugin. Lives
at `web/` inside the `adkaushik/hyperpowers` repo (being made private), alongside the plugin
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
src/routes/index.tsx         landing page (full-document SSR)
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
`.data/hyperpowers.db`. `CLIENT_IP_HEADER` names the header the hosting proxy sets to the
visitor address (`fly-client-ip` on Fly.io). Without it, every visitor shares
one sign-in rate limit.

## Deploying

The site runs on Fly.io. `Dockerfile` builds it on Node 22, which TanStack Start
requires, and `fly.toml` configures the app. SQLite lives on a Fly volume mounted
at `/data`. A volume attaches to one Machine only, so the app runs exactly one
Machine. Keep it at one while SQLite is the database.

First deploy, from `web/`:

```bash
fly launch --copy-config --no-deploy
fly secrets set APP_SECRET="$(openssl rand -base64 48)"
fly secrets set SMTP_URL='smtps://user:pass@smtp.example.com:465' MAIL_FROM='Hyperpowers <login@example.com>'
fly deploy --ha=false
```

`--ha=false` stops Fly from adding a spare Machine. A spare would get its own empty
volume, so sign-ins would land in two different databases. The first deploy
creates the volume from `initial_size` in `fly.toml`, and after that `fly deploy`
ships each new version. If the app name `hyperpowers-web` is taken, `fly launch`
asks for another.

`fly.toml` sets `DATABASE_PATH=/data/hyperpowers.db` and
`CLIENT_IP_HEADER=fly-client-ip`. Set secrets with `fly secrets`. They do not
belong in `fly.toml`.

## The open piece: installer sign-in

The installer (`npx hyperpowers-claude`, separate package at
`~/Projects/hyperpowers-claude`, not in this repo and not yet on npm) prints a
one-time code. The user signs in here, enters the code, and the installer
receives a token that belongs to that account.

**Decision, 2026-09-13: per-user tokens.** This replaces the earlier shared-key
design, where one decryption key unlocked an encrypted payload bundled in the
npm package. The repo is being made private, and a shared key cannot be taken
back once someone shares it. A per-user token can be revoked for one account
without affecting anyone else.

**None of that backend exists yet.** The dashboard says so plainly rather than
faking it with stubs. What still needs building:

- `POST /device/code` — issue a user code plus a device code
- `POST /device/token` — the CLI polls this; returns the account's token once
  the code is claimed
- `POST /portal/claim` — signed-in user submits the code; checks a paid
  entitlement before issuing anything
- A download endpoint that serves the plugin only to a valid, unrevoked token
- Token revocation, code expiry, rate limiting, per-account caps

Until the package name is reserved on npm, keep `npx hyperpowers-claude` off
the public site. `npx` runs whatever is published under that name.

## House style

No AI slop in user-facing copy. Specifically: no "X, not Y" headlines, no
aphoristic closers, no em-dashes in prose, no rhetorical triads, no tagline-shaped
section titles. Plain declarative sentences that say what the thing does. The
landing page was rewritten once to remove all of this; do not reintroduce it.
