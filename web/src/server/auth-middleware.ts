import { createMiddleware } from '@tanstack/react-start'
import { readSession } from './session'

/**
 * Server functions are reachable as RPC endpoints regardless of which route
 * rendered the caller, so anything touching account data enforces auth here
 * rather than relying on a route guard.
 */
export const authMiddleware = createMiddleware({ type: 'function' }).server(
  async ({ next }) => {
    const session = readSession()
    if (!session) throw new Error('Unauthorized')
    return next({ context: { session } })
  },
)
