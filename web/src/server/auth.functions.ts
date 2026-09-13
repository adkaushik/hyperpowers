import { createHash, randomInt, randomUUID, timingSafeEqual } from 'node:crypto'
import { createServerFn } from '@tanstack/react-start'
import { z } from 'zod'
import { APP_SECRET } from './env'
import { db, type LoginCodeRow, type UserRow } from './db'
import { loginCodeMail, sendMail } from './mail'
import { authMiddleware } from './auth-middleware'
import {
  clearSessionCookie,
  createSession,
  readSession,
  requestMeta,
  revokeAllSessionsForUser,
  revokeSession,
} from './session'

const CODE_TTL_MINUTES = 10
const MAX_ATTEMPTS_PER_CODE = 5
const MAX_CODES_PER_EMAIL_PER_WINDOW = 5
const MAX_CODES_PER_IP_PER_WINDOW = 20
const RATE_WINDOW_MS = 15 * 60 * 1000

const emailSchema = z
  .string()
  .trim()
  .toLowerCase()
  .min(3)
  .max(254)
  .email('Enter a valid email address.')

function hashCode(email: string, code: string) {
  return createHash('sha256')
    .update(`${APP_SECRET}:${email}:${code}`)
    .digest('hex')
}

function constantTimeEquals(a: string, b: string) {
  const left = Buffer.from(a)
  const right = Buffer.from(b)
  if (left.length !== right.length) return false
  return timingSafeEqual(left, right)
}

function countRecent(column: 'email' | 'request_ip', value: string) {
  const row = db
    .prepare(
      `SELECT COUNT(*) AS n FROM login_codes
        WHERE ${column} = ? AND created_at > ?`,
    )
    .get(value, Date.now() - RATE_WINDOW_MS) as { n: number }
  return row.n
}

/**
 * Issues a one-time sign-in code. The response is identical whether or not the
 * address already has an account — the account is created on successful
 * verification, so there is nothing to disclose here either way.
 */
export const requestLoginCode = createServerFn({ method: 'POST' })
  .validator(z.object({ email: emailSchema }))
  .handler(async ({ data }) => {
    const { email } = data
    const meta = requestMeta()

    if (countRecent('email', email) >= MAX_CODES_PER_EMAIL_PER_WINDOW) {
      throw new Error(
        'Too many codes requested for this address. Try again in 15 minutes.',
      )
    }
    if (
      meta.requestIp &&
      countRecent('request_ip', meta.requestIp) >= MAX_CODES_PER_IP_PER_WINDOW
    ) {
      throw new Error('Too many sign-in attempts. Try again in 15 minutes.')
    }

    const now = Date.now()

    // Supersede any outstanding code for this address: one live code at a time.
    db.prepare(
      `UPDATE login_codes SET consumed_at = ?
        WHERE email = ? AND consumed_at IS NULL`,
    ).run(now, email)

    const code = String(randomInt(0, 1_000_000)).padStart(6, '0')

    db.prepare(
      `INSERT INTO login_codes (id, email, code_hash, created_at, expires_at, request_ip)
       VALUES (?, ?, ?, ?, ?, ?)`,
    ).run(
      randomUUID(),
      email,
      hashCode(email, code),
      now,
      now + CODE_TTL_MINUTES * 60 * 1000,
      meta.requestIp,
    )

    try {
      await sendMail(loginCodeMail(email, code, CODE_TTL_MINUTES))
    } catch (caught) {
      // Transport problems are an operator's business, not the visitor's: log
      // the detail, show a message that leaks no configuration.
      console.error('[auth] sign-in code delivery failed:', caught)
      throw new Error('We could not send the code right now. Try again shortly.')
    }

    return { email, expiresInMinutes: CODE_TTL_MINUTES }
  })

/**
 * Verifies a code and, on success, creates the account if needed and issues a
 * session cookie. Every failure returns the same message so the response does
 * not distinguish "no such code" from "wrong code".
 */
export const verifyLoginCode = createServerFn({ method: 'POST' })
  .validator(
    z.object({
      email: emailSchema,
      code: z
        .string()
        .trim()
        .regex(/^\d{6}$/, 'Enter the 6-digit code from your email.'),
    }),
  )
  .handler(async ({ data }) => {
    const { email, code } = data
    const now = Date.now()
    const invalid = new Error('That code is not valid. Request a new one.')

    const row = db
      .prepare(
        `SELECT * FROM login_codes
          WHERE email = ? AND consumed_at IS NULL AND expires_at > ?
          ORDER BY created_at DESC LIMIT 1`,
      )
      .get(email, now) as LoginCodeRow | undefined

    if (!row) throw invalid

    if (row.attempts + 1 >= MAX_ATTEMPTS_PER_CODE) {
      // Burn the code on the last allowed attempt, whatever the outcome.
      db.prepare(`UPDATE login_codes SET consumed_at = ? WHERE id = ?`).run(
        now,
        row.id,
      )
    } else {
      db.prepare(`UPDATE login_codes SET attempts = attempts + 1 WHERE id = ?`).run(
        row.id,
      )
    }

    if (!constantTimeEquals(row.code_hash, hashCode(email, code))) {
      throw invalid
    }

    db.prepare(`UPDATE login_codes SET consumed_at = ? WHERE id = ?`).run(
      now,
      row.id,
    )

    let user = db.prepare(`SELECT * FROM users WHERE email = ?`).get(email) as
      | UserRow
      | undefined

    if (!user) {
      const id = randomUUID()
      db.prepare(
        `INSERT INTO users (id, email, created_at, last_login_at) VALUES (?, ?, ?, ?)`,
      ).run(id, email, now, now)
      user = { id, email, created_at: now, last_login_at: now }
    } else {
      db.prepare(`UPDATE users SET last_login_at = ? WHERE id = ?`).run(
        now,
        user.id,
      )
    }

    // Rotate on privilege change: an anonymous visitor becomes a principal.
    revokeAllSessionsForUser(user.id)
    createSession(user.id, requestMeta())

    return { email: user.email, isNewAccount: user.created_at === now }
  })

/** Reads the caller's session, or null. Safe to call unauthenticated. */
export const getCurrentSession = createServerFn({ method: 'GET' }).handler(
  async () => {
    const session = readSession()
    if (!session) return null
    return {
      email: session.email,
      createdAt: session.createdAt,
      expiresAt: session.expiresAt,
    }
  },
)

export const signOut = createServerFn({ method: 'POST' })
  .middleware([authMiddleware])
  .handler(async ({ context }) => {
    revokeSession(context.session.id)
    clearSessionCookie()
    return { ok: true }
  })
