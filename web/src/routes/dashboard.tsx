import { useState } from 'react'
import { createFileRoute, redirect, useRouter } from '@tanstack/react-router'
import { useServerFn } from '@tanstack/react-start'
import { getCurrentSession, signOut } from '../server/auth.functions'
import CopyCommand from '../components/CopyCommand'

export const Route = createFileRoute('/dashboard')({
  // Account data: nothing here belongs in a crawlable or cacheable document,
  // so the loader runs on the server and the component renders on the client.
  ssr: 'data-only',
  beforeLoad: async () => {
    const session = await getCurrentSession()
    if (!session) {
      // Route guards are UX; the server functions below enforce auth themselves.
      throw redirect({ to: '/signin', search: { redirect: '/dashboard' } })
    }
    return { session }
  },
  loader: ({ context }) => ({ session: context.session }),
  component: Dashboard,
})

function formatDate(value: number) {
  return new Date(value).toLocaleString(undefined, {
    dateStyle: 'medium',
    timeStyle: 'short',
  })
}

function Dashboard() {
  const { session } = Route.useLoaderData()
  const router = useRouter()
  const signOutFn = useServerFn(signOut)
  const [pending, setPending] = useState(false)

  async function onSignOut() {
    setPending(true)
    try {
      await signOutFn({ data: undefined })
      await router.invalidate({ sync: true })
      await router.navigate({ to: '/' })
    } finally {
      setPending(false)
    }
  }

  return (
    <main className="px-4 py-14 sm:py-20">
      <div className="page-wrap max-w-3xl">
        <div className="mb-8 flex flex-wrap items-end justify-between gap-4">
          <div>
            <p className="kicker mb-2">Account</p>
            <h1 className="m-0 text-2xl font-semibold tracking-tight text-[var(--ink)] sm:text-3xl">
              {session.email}
            </h1>
          </div>
          <button
            type="button"
            onClick={onSignOut}
            disabled={pending}
            className="btn btn-ghost"
          >
            {pending ? 'Signing out…' : 'Sign out'}
          </button>
        </div>

        <section className="panel mb-4 p-6">
          <p className="rule-label mb-4">Session</p>
          <dl className="m-0 grid gap-3 sm:grid-cols-2">
            <div>
              <dt className="mb-1 text-xs text-[var(--ink-dim)]">Signed in</dt>
              <dd className="m-0 font-mono text-sm text-[var(--ink)]">
                {formatDate(session.createdAt)}
              </dd>
            </div>
            <div>
              <dt className="mb-1 text-xs text-[var(--ink-dim)]">Expires</dt>
              <dd className="m-0 font-mono text-sm text-[var(--ink)]">
                {formatDate(session.expiresAt)}
              </dd>
            </div>
          </dl>
        </section>

        <section className="panel p-6">
          <p className="rule-label mb-4">Install</p>
          <h2 className="mb-3 text-lg font-semibold text-[var(--ink)]">
            Add the plugin to Claude Code
          </h2>
          <div className="grid gap-2">
            <CopyCommand command="npx hyperpowers-claude" prompt="$" />
            <CopyCommand command="/hyperpower:init" prompt="›" />
          </div>
          <p className="mt-4 mb-0 text-sm leading-relaxed text-[var(--ink-soft)]">
            The installer prints an activation code and waits for it to be
            claimed. Claiming is not wired up yet; this account is what it will
            hang off once it is. In the meantime, pass the key directly:{' '}
            <code>npx hyperpowers-claude --key &lt;key&gt;</code>.
          </p>
        </section>
      </div>
    </main>
  )
}
