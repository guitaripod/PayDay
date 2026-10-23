import { Hono } from 'hono'
import type { AppVars, Env } from '../env'
import { requireAuth } from '../middleware/requireAuth'
import { purgeUser } from '../lib/purge'

export const accountRoutes = new Hono<{ Bindings: Env; Variables: AppVars }>()

/// Account-deletion hook for the Peppol transmission records (App Store 5.1.1(v) and
/// GDPR Art. 17). The app calls it BEFORE mako's DELETE /v1/identity, because the mako
/// delete invalidates the api-key and this worker can then no longer authenticate the
/// caller to learn whose rows to erase. Authentication is the same requireAuth bearer
/// check every per-user route uses. Answers 204 with no body and is idempotent: a
/// re-run after the rows are gone is another 204. The log carries the total only.
accountRoutes.delete('/v1/account', requireAuth, async (c) => {
  const { total } = await purgeUser(c.env, c.get('userId'))
  console.log(JSON.stringify({ event: 'account_purge', total }))
  return c.body(null, 204)
})
