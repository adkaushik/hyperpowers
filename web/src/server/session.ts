import '@tanstack/react-start/server-only'
import { createHash, randomBytes, randomUUID } from 'node:crypto'
import {
  getRequestHeader,
  setResponseHeader,
} from '@tanstack/react-start/server'
import { APP_SECRET, isProduction } from './env'
import { db, type SessionRow, type UserRow } from './db'

/**
 * `__Host-` binds the cookie to this exact origin, but it requires `Secure`,
 * which a plain-HTTP dev server cannot satisfy. Dev therefore uses an
 * unprefixed name; production gets the hardened one.
 */
const COOKIE_NAME = isProduction ? '__Host-hp_session' : 'hp_session'
const SESSION_TTL_SECONDS = 60 * 60 * 24 * 30

export function hashToken(token: string) {
  return createHash('sha256').update(`${APP_SECRET}:${token}`).digest('hex')
}

export function readSessionToken(): string | null {
  const header = getRequestHeader('cookie')
  if (!header) return null
  for (const part of header.split(/;\s*/)) {
    // Split on the first '=' only: base64url tokens can contain '='.
    const eq = part.indexOf('=')
    if (eq === -1) continue
    if (part.slice(0, eq) === COOKIE_NAME) {
      return decodeURIComponent(part.slice(eq + 1)) || null
    }
  }
  return null
}

function writeCookie(value: string, maxAgeSeconds: number) {
  setResponseHeader(
    'Set-Cookie',
    [
      `${COOKIE_NAME}=${value}`,
      'HttpOnly',
      ...(isProduction ? ['Secure'] : []),
      'SameSite=Lax',
      'Path=/',
      `Max-Age=${maxAgeSeconds}`,
    ].join('; '),
  )
}

export function clearSessionCookie() {
  writeCookie('', 0)
}

export type Session = {
  id: string
  userId: string
  email: string
  createdAt: number
  expiresAt: number
}

export function createSession(
  userId: string,
  meta: { userAgent: string | null; requestIp: string | null },
): Session {
  const token = randomBytes(32).toString('base64url')
  const now = Date.now()
  const expiresAt = now + SESSION_TTL_SECONDS * 1000
  const id = randomUUID()

  db.prepare(
    `INSERT INTO sessions (id, token_hash, user_id, created_at, expires_at, user_agent, request_ip)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
  ).run(
    id,
    hashToken(token),
    userId,
    now,
    expiresAt,
    meta.userAgent,
    meta.requestIp,
  )

  writeCookie(token, SESSION_TTL_SECONDS)

  const email = (
    db.prepare(`SELECT email FROM users WHERE id = ?`).get(userId) as
      | Pick<UserRow, 'email'>
      | undefined
  )?.email

  return {
    id,
    userId,
    email: email ?? '',
    createdAt: now,
    expiresAt,
  }
}

/**
 * Resolves the caller's session, or null. Expired rows are deleted on read so
 * the table does not accumulate them.
 */
export function readSession(): Session | null {
  const token = readSessionToken()
  if (!token) return null

  const row = db
    .prepare(
      `SELECT s.*, u.email AS user_email
         FROM sessions s
         JOIN users u ON u.id = s.user_id
        WHERE s.token_hash = ?`,
    )
    .get(hashToken(token)) as (SessionRow & { user_email: string }) | undefined

  if (!row) return null

  if (row.expires_at <= Date.now()) {
    db.prepare(`DELETE FROM sessions WHERE id = ?`).run(row.id)
    return null
  }

  return {
    id: row.id,
    userId: row.user_id,
    email: row.user_email,
    createdAt: row.created_at,
    expiresAt: row.expires_at,
  }
}

export function revokeSession(sessionId: string) {
  db.prepare(`DELETE FROM sessions WHERE id = ?`).run(sessionId)
}

export function revokeAllSessionsForUser(userId: string) {
  db.prepare(`DELETE FROM sessions WHERE user_id = ?`).run(userId)
}

export function requestMeta() {
  const forwardedFor = getRequestHeader('x-forwarded-for')
  return {
    userAgent: getRequestHeader('user-agent') ?? null,
    requestIp: forwardedFor?.split(',')[0]?.trim() ?? null,
  }
}
