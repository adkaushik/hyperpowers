import { useEffect, useRef, useState } from 'react'
import {
  Link,
  createFileRoute,
  redirect,
  useNavigate,
  useRouter,
} from '@tanstack/react-router'
import { useServerFn } from '@tanstack/react-start'
import { z } from 'zod'
import {
  getCurrentSession,
  requestLoginCode,
  verifyLoginCode,
} from '../server/auth.functions'
import { ArrowRightIcon } from '../components/icons'

/**
 * `redirect` is echoed into a navigation after sign-in, so it is restricted to
 * a site-relative path. `//host` and `/\host` are rejected: both are treated as
 * protocol-relative URLs by browsers and would make this an open redirect.
 */
const internalPath = z
  .string()
  .refine(
    (value) =>
      value.startsWith('/') &&
      !value.startsWith('//') &&
      !value.startsWith('/\\'),
    'Must be a site-relative path',
  )

const searchSchema = z.object({
  step: z.enum(['email', 'code']).optional().catch(undefined),
  email: z.string().trim().toLowerCase().email().optional().catch(undefined),
  redirect: internalPath.optional().catch(undefined),
})

export const Route = createFileRoute('/signin')({
  // The form shell is static and worth rendering on the server; the step is
  // driven by search params, so SSR and client render agree.
  ssr: true,
  validateSearch: searchSchema,
  beforeLoad: async ({ search }) => {
    const session = await getCurrentSession()
    if (session) {
      throw redirect({ to: search.redirect ?? '/dashboard' })
    }
  },
  component: SignIn,
})

function errorMessage(error: unknown) {
  if (error instanceof Error && error.message) return error.message
  return 'Something went wrong. Try again.'
}

function SignIn() {
  const search = Route.useSearch()
  const navigate = useNavigate({ from: Route.fullPath })
  const router = useRouter()

  const sendCode = useServerFn(requestLoginCode)
  const verifyCode = useServerFn(verifyLoginCode)

  const [email, setEmail] = useState(search.email ?? '')
  const [code, setCode] = useState('')
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const codeInput = useRef<HTMLInputElement>(null)

  const step = search.step === 'code' && search.email ? 'code' : 'email'

  useEffect(() => {
    if (step === 'code') codeInput.current?.focus()
  }, [step])

  async function onSubmitEmail(event: React.FormEvent) {
    event.preventDefault()
    setError(null)
    setNotice(null)
    setPending(true)
    try {
      const result = await sendCode({ data: { email } })
      await navigate({
        search: (prev) => ({
          ...prev,
          step: 'code' as const,
          email: result.email,
        }),
      })
      setNotice(
        `Code sent to ${result.email}. It expires in ${result.expiresInMinutes} minutes.`,
      )
    } catch (caught) {
      setError(errorMessage(caught))
    } finally {
      setPending(false)
    }
  }

  async function onSubmitCode(event: React.FormEvent) {
    event.preventDefault()
    setError(null)
    setPending(true)
    try {
      await verifyCode({ data: { email: search.email ?? email, code } })
      // The session cookie is now set; re-run loaders so the guarded route
      // sees it, then leave the sign-in page. `href` rather than `to` because
      // the destination is a validated runtime string, not a literal route.
      await router.invalidate({ sync: true })
      await router.navigate({ href: search.redirect ?? '/dashboard' })
    } catch (caught) {
      setError(errorMessage(caught))
      setCode('')
      codeInput.current?.focus()
    } finally {
      setPending(false)
    }
  }

  async function onResend() {
    setError(null)
    setNotice(null)
    setPending(true)
    try {
      const result = await sendCode({ data: { email: search.email ?? email } })
      setNotice(`New code sent to ${result.email}.`)
      setCode('')
      codeInput.current?.focus()
    } catch (caught) {
      setError(errorMessage(caught))
    } finally {
      setPending(false)
    }
  }

  return (
    <main className="px-4 py-16 sm:py-24">
      <div className="page-wrap max-w-md">
        <div className="panel-raised rise-in p-7 sm:p-9">
          <p className="kicker mb-3">
            {step === 'email' ? 'Sign in' : 'Check your email'}
          </p>

          {step === 'email' ? (
            <>
              <h1 className="mb-2 text-2xl font-semibold tracking-tight text-[var(--ink)]">
                Sign in with email
              </h1>
              <p className="mb-6 text-sm leading-relaxed text-[var(--ink-soft)]">
                We send a six-digit code, so there is no password to remember.
                You do not need to create an account first; signing in for the
                first time makes one.
              </p>

              <form onSubmit={onSubmitEmail} className="grid gap-3">
                <label
                  htmlFor="email"
                  className="rule-label !text-[var(--ink-soft)]"
                >
                  Email address
                </label>
                <input
                  id="email"
                  className="field"
                  type="email"
                  name="email"
                  autoComplete="email"
                  inputMode="email"
                  required
                  autoFocus
                  placeholder="you@example.com"
                  value={email}
                  onChange={(event) => setEmail(event.target.value)}
                  disabled={pending}
                />
                <button
                  type="submit"
                  className="btn btn-primary mt-1 w-full"
                  disabled={pending || email.trim().length < 3}
                >
                  {pending ? 'Sending code…' : 'Send me a code'}
                  {pending ? null : <ArrowRightIcon />}
                </button>
              </form>
            </>
          ) : (
            <>
              <h1 className="mb-2 text-2xl font-semibold tracking-tight text-[var(--ink)]">
                Enter your code
              </h1>
              <p className="mb-6 text-sm leading-relaxed text-[var(--ink-soft)]">
                Sent to{' '}
                <span className="font-mono text-[var(--ink)]">
                  {search.email}
                </span>
                . Single use, expires in 10 minutes.
              </p>

              <form onSubmit={onSubmitCode} className="grid gap-3">
                <label
                  htmlFor="code"
                  className="rule-label !text-[var(--ink-soft)]"
                >
                  Six-digit code
                </label>
                <input
                  id="code"
                  ref={codeInput}
                  className="field field-code"
                  name="code"
                  autoComplete="one-time-code"
                  inputMode="numeric"
                  pattern="\d{6}"
                  maxLength={6}
                  required
                  placeholder="000000"
                  value={code}
                  onChange={(event) =>
                    setCode(event.target.value.replace(/\D/g, '').slice(0, 6))
                  }
                  disabled={pending}
                />
                <button
                  type="submit"
                  className="btn btn-primary mt-1 w-full"
                  disabled={pending || code.length !== 6}
                >
                  {pending ? 'Verifying…' : 'Verify and sign in'}
                </button>
              </form>

              <div className="mt-5 flex items-center justify-between gap-3 text-xs">
                <button
                  type="button"
                  onClick={onResend}
                  disabled={pending}
                  className="nav-link !text-xs underline decoration-[var(--line-strong)] underline-offset-4 disabled:opacity-50"
                >
                  Send a new code
                </button>
                <Link
                  to="/signin"
                  search={(prev) => ({ ...prev, step: 'email' as const })}
                  className="nav-link !text-xs underline decoration-[var(--line-strong)] underline-offset-4"
                >
                  Use a different email
                </Link>
              </div>
            </>
          )}

          {notice ? (
            <p
              role="status"
              className="mt-5 mb-0 rounded-lg border border-[color-mix(in_srgb,var(--green)_40%,transparent)] bg-[var(--green-bg)] px-3 py-2 text-xs leading-relaxed text-[var(--ink)]"
            >
              {notice}
            </p>
          ) : null}

          {error ? (
            <p
              role="alert"
              className="mt-3 mb-0 rounded-lg border border-[color-mix(in_srgb,var(--red)_45%,transparent)] bg-[var(--red-bg)] px-3 py-2 text-xs leading-relaxed text-[var(--ink)]"
            >
              {error}
            </p>
          ) : null}
        </div>

        <p className="mt-5 text-center text-xs leading-relaxed text-[var(--ink-dim)]">
          Signing in stores your email address and a session cookie. Nothing
          else.{' '}
          <Link to="/" className="nav-link !text-xs underline underline-offset-4">
            Back to the overview
          </Link>
        </p>
      </div>
    </main>
  )
}
