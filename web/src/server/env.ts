// Marks this module server-only: importing it from client code is a build
// error rather than a secret in the browser bundle.
import '@tanstack/react-start/server-only'

export const isProduction = process.env.NODE_ENV === 'production'

/**
 * Pepper for hashing one-time login codes and session tokens. Rotating this
 * value invalidates every outstanding code and session, which is the intended
 * behaviour.
 */
export const APP_SECRET = (() => {
  const value = process.env.APP_SECRET
  if (value && value.length >= 16) return value
  if (isProduction) {
    throw new Error(
      'APP_SECRET must be set to at least 16 characters in production.',
    )
  }
  return 'development-only-insecure-app-secret'
})()

export const DATABASE_PATH = process.env.DATABASE_PATH ?? '.data/hyperpowers.db'

export const MAIL_FROM =
  process.env.MAIL_FROM ?? 'Hyperpowers <no-reply@localhost>'

/**
 * The request header the hosting proxy sets to the visitor's address, such as
 * `fly-client-ip` on Fly.io. Unset, every visitor shares one sign-in rate limit.
 */
export const CLIENT_IP_HEADER = (process.env.CLIENT_IP_HEADER ?? '')
  .trim()
  .toLowerCase()

if (isProduction && !CLIENT_IP_HEADER) {
  console.warn(
    '[env] CLIENT_IP_HEADER is not set, so every visitor shares one sign-in rate limit.',
  )
}

/**
 * SMTP settings for nodemailer. Either a single `SMTP_URL` connection string
 * or the discrete host/port/user/pass variables; the URL wins when both are
 * present.
 */
export const SMTP = (() => {
  const url = process.env.SMTP_URL ?? ''
  const host = process.env.SMTP_HOST ?? ''
  const port = Number(process.env.SMTP_PORT ?? 587)
  const secureEnv = process.env.SMTP_SECURE

  return {
    url,
    host,
    port: Number.isFinite(port) ? port : 587,
    secure: secureEnv === undefined ? undefined : secureEnv === 'true',
    user: process.env.SMTP_USER ?? '',
    pass: process.env.SMTP_PASS ?? '',
    configured: Boolean(url || host),
  }
})()
