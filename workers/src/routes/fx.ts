import { Hono } from 'hono'
import type { AppVars, Env } from '../env'
import { requireAuth } from '../middleware/requireAuth'
import { crossRate, loadRates } from '../lib/fx'

export const fxRoutes = new Hono<{ Bindings: Env; Variables: AppVars }>()

fxRoutes.get('/v1/fx/rates', requireAuth, async (c) => {
  const base = (c.req.query('base') ?? 'EUR').toUpperCase()
  const quote = (c.req.query('quote') ?? '').toUpperCase()
  if (quote.length !== 3) return c.json({ error: 'quote_required' }, 400)
  try {
    const rates = await loadRates(c.env.FX_CACHE)
    const rate = crossRate(rates, base, quote)
    if (rate === null) return c.json({ error: 'unsupported_currency' }, 404)
    return c.json({ base, quote, rate: Number(rate.toFixed(6)) })
  } catch {
    return c.json({ error: 'fx_unavailable' }, 503)
  }
})
