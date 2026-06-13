import { Hono } from 'hono'
import type { AppVars, Env } from '../env'
import { requireAuth } from '../middleware/requireAuth'
import { checkVAT, splitVAT } from '../lib/vies'

export const vatRoutes = new Hono<{ Bindings: Env; Variables: AppVars }>()

vatRoutes.post('/v1/vat/validate', requireAuth, async (c) => {
  let body: { vatID?: string }
  try {
    body = await c.req.json<{ vatID?: string }>()
  } catch {
    return c.json({ error: 'invalid_json' }, 400)
  }
  const vatID = (body.vatID ?? '').trim()
  if (!vatID) return c.json({ error: 'vatID_required' }, 400)
  if (!splitVAT(vatID)) {
    return c.json({ vatID, valid: false, reachable: true })
  }
  const result = await checkVAT(vatID)
  return c.json(result)
})
