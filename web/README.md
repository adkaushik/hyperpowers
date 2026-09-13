# hyperpowers-web

Landing page and email sign-in for [hyperpowers](https://github.com/adkaushik/hyperpowers),
built with TanStack Start.

## Run it

```bash
npm install
npm run dev        # http://localhost:3000
```

With no SMTP settings, the sign-in code is printed to the dev server console
instead of being emailed. Copy it from there.

```bash
npm run build      # Nitro output in .output/
npm run preview    # serve the build
npm run typecheck
```

## What is here

| Route | SSR mode | Notes |
|---|---|---|
| `/` | full document | Landing page. |
| `/signin` | full document | Email → six-digit code. Step lives in validated search params. |
| `/dashboard` | `data-only` | Account data; loader on the server, component on the client. |

Server work sits behind explicit boundaries:

- `src/server/*.functions.ts` — `createServerFn` RPCs, the only things client
  code imports.
- `src/server/env.ts`, `db.ts`, `mail.ts`, `session.ts` — marked
  `import '@tanstack/react-start/server-only'`, so importing them from client
  code is a build error rather than a secret in the browser bundle.
- `src/server/auth-middleware.ts` — session enforcement for server functions.
  Server functions are reachable as endpoints regardless of which route
  rendered the caller, so `signOut` enforces auth itself; the `beforeLoad`
  guard on `/dashboard` is UX only.

## Sign-in flow

1. `requestLoginCode({ email })` — issues a 6-digit code, stores only
   `sha256(APP_SECRET:email:code)`, supersedes any outstanding code for that
   address, and mails it. The response is the same whether or not the address
   has an account.
2. `verifyLoginCode({ email, code })` — constant-time compare, creates the
   account on first successful sign-in, revokes existing sessions, sets an
   `HttpOnly` `SameSite=Lax` session cookie (`__Host-` prefixed and `Secure` in
   production).
3. `signOut()` — deletes the session row and clears the cookie.

Limits, all in `src/server/auth.functions.ts`: code TTL 10 minutes, 5 verify
attempts per code, 5 codes per address and 20 per IP per 15 minutes. Every
verification failure returns the same message.

Sessions last 30 days. Expired rows are deleted when read.

## Configuration

See [`.env.example`](.env.example). `APP_SECRET` is required in production and
must be at least 16 characters; the app refuses to start a sign-in without a
mail transport in production rather than dropping the message.

Mail goes out over SMTP through nodemailer — either `SMTP_URL` or the discrete
`SMTP_HOST`/`SMTP_PORT`/`SMTP_USER`/`SMTP_PASS`, with one pooled transport per
process. TLS is required: port 465 connects with implicit TLS, anything else
must offer STARTTLS. `verifyMailTransport()` in `src/server/mail.ts` checks the
credentials without sending a message.

## Data

SQLite via `better-sqlite3` at `DATABASE_PATH` (`.data/hyperpowers.db` by
default, gitignored). Tables — `users`, `login_codes`, `sessions` — are created
on first connection. The native addon stays external to the bundle in both dev
and build (see `NATIVE_DEPS` in `vite.config.ts`), so the deployment target
needs a Node runtime with a filesystem.

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

## Not built yet

Claiming activation codes from `npx hyperpowers-claude`. The account created
here is the anchor that will hang off; the dashboard says so plainly.
