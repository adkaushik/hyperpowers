import { Link } from '@tanstack/react-router'
import ThemeToggle from './ThemeToggle'

export default function Header({ signedIn }: { signedIn: boolean }) {
  return (
    <header className="sticky top-0 z-50 border-b border-[var(--line)] bg-[color-mix(in_srgb,var(--bg)_86%,transparent)] px-4 backdrop-blur-xl">
      <nav className="page-wrap flex items-center gap-4 py-3">
        <Link
          to="/"
          className="flex flex-shrink-0 items-center gap-2 no-underline"
        >
          <span
            aria-hidden="true"
            className="grid h-7 w-7 place-items-center rounded-md border border-[color-mix(in_srgb,var(--amber)_40%,transparent)] bg-[var(--amber-bg)] font-mono text-[0.8125rem] font-bold text-[var(--amber)]"
          >
            hp
          </span>
          <span className="font-mono text-sm font-bold tracking-tight text-[var(--ink)]">
            hyperpowers
          </span>
        </Link>

        <div className="ml-2 hidden items-center gap-5 md:flex">
          <a href="/#pipeline" className="nav-link">
            Pipeline
          </a>
          <a href="/#memory" className="nav-link">
            Memory
          </a>
          <a href="/#commands" className="nav-link">
            Commands
          </a>
          <a href="/#install" className="nav-link">
            Install
          </a>
        </div>

        <div className="ml-auto flex items-center gap-2">
          <ThemeToggle />
          {signedIn ? (
            <Link to="/dashboard" className="btn btn-primary !px-4 !py-2">
              Dashboard
            </Link>
          ) : (
            <Link to="/signin" className="btn btn-primary !px-4 !py-2">
              Sign in
            </Link>
          )}
        </div>
      </nav>
    </header>
  )
}
