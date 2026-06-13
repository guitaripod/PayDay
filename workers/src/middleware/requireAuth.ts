import type { MiddlewareHandler } from 'hono'
import type { AppVars, Env } from '../env'
import { verifyAppJWT } from '../lib/jwt'

export const requireAuth: MiddlewareHandler<{ Bindings: Env; Variables: AppVars }> = async (
  c,
  next
) => {
  const header = c.req.header('Authorization')
  if (!header?.startsWith('Bearer ')) {
    return c.json({ error: 'missing_bearer' }, 401)
  }
  try {
    const claims = await verifyAppJWT(header.slice(7), c.env.APP_JWT_SECRET)
    c.set('userId', claims.uid)
  } catch {
    return c.json({ error: 'invalid_token' }, 401)
  }
  await next()
}
