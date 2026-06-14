import type { MiddlewareHandler } from 'hono'
import type { AppVars, Env } from '../env'

/// payday-worker does not own identity — mako does. Rather than verify its own
/// JWT, it forwards the caller's mako api-key to mako's /v1/identity/me to
/// validate it and resolve the stable user id. The iOS app authenticates every
/// request with its AICredits (mako) api-key, so this is the single auth model.
export const requireAuth: MiddlewareHandler<{ Bindings: Env; Variables: AppVars }> = async (
  c,
  next
) => {
  const header = c.req.header('Authorization')
  if (!header?.startsWith('Bearer ')) {
    return c.json({ error: 'missing_bearer' }, 401)
  }
  let body: { user_id?: string }
  try {
    const res = await fetch(`${c.env.MAKO_BASE_URL}/v1/identity/me`, {
      headers: { authorization: header, 'x-app-id': 'payday' },
    })
    if (!res.ok) return c.json({ error: 'invalid_token' }, 401)
    body = (await res.json()) as { user_id?: string }
  } catch {
    return c.json({ error: 'auth_unavailable' }, 503)
  }
  if (!body.user_id) return c.json({ error: 'invalid_token' }, 401)
  c.set('userId', body.user_id)
  await next()
}
