import { Hono } from 'hono'
import type { AppVars, Env } from '../env'

export const configRoutes = new Hono<{ Bindings: Env; Variables: AppVars }>()

configRoutes.get('/v1/config', (c) => {
  const peppolEnabled = Boolean(c.env.PEPPOL_API_KEY && c.env.PEPPOL_LEGAL_ENTITY_ID)
  const currencies = (c.env.SUPPORTED_CURRENCIES ?? 'EUR,USD,GBP')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean)
  return c.json({
    environment: c.env.ENVIRONMENT,
    peppol: { enabled: peppolEnabled, mode: peppolEnabled ? 'gateway' : 'stub' },
    vatValidation: true,
    currencies,
  })
})
