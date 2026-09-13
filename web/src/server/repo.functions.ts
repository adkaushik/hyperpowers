import { createServerFn } from '@tanstack/react-start'

const REPO = 'adkaushik/hyperpowers'
const CACHE_TTL_MS = 10 * 60 * 1000

export type RepoStats = {
  stars: number | null
  forks: number | null
  pushedAt: string | null
  license: string | null
}

let cache: { at: number; value: RepoStats } | null = null

/**
 * Public repository facts for the landing page. Streamed rather than blocking
 * the document: GitHub being slow or rate-limited must not delay first paint,
 * so every failure degrades to nulls instead of throwing.
 */
export const getRepoStats = createServerFn({ method: 'GET' }).handler(
  async (): Promise<RepoStats> => {
    if (cache && Date.now() - cache.at < CACHE_TTL_MS) return cache.value

    const empty: RepoStats = {
      stars: null,
      forks: null,
      pushedAt: null,
      license: null,
    }

    try {
      const response = await fetch(`https://api.github.com/repos/${REPO}`, {
        headers: {
          accept: 'application/vnd.github+json',
          'user-agent': 'hyperpowers-web',
          ...(process.env.GITHUB_TOKEN
            ? { authorization: `Bearer ${process.env.GITHUB_TOKEN}` }
            : {}),
        },
        signal: AbortSignal.timeout(4000),
      })

      if (!response.ok) return empty

      const body = (await response.json()) as {
        stargazers_count?: number
        forks_count?: number
        pushed_at?: string
        license?: { spdx_id?: string } | null
      }

      const value: RepoStats = {
        stars: body.stargazers_count ?? null,
        forks: body.forks_count ?? null,
        pushedAt: body.pushed_at ?? null,
        license: body.license?.spdx_id ?? null,
      }

      cache = { at: Date.now(), value }
      return value
    } catch {
      return empty
    }
  },
)
