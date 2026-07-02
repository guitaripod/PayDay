import { Hono } from 'hono'
import type { AppVars, Env } from '../env'
import { StubPeppolGateway, makePeppolGateway } from '../lib/peppol'

export const configRoutes = new Hono<{ Bindings: Env; Variables: AppVars }>()

configRoutes.get('/v1/config', (c) => {
  const gateway = makePeppolGateway(c.env)
  const peppolMode = gateway === null ? 'unconfigured' : gateway instanceof StubPeppolGateway ? 'stub' : 'gateway'
  const peppolEnabled = peppolMode === 'gateway'
  const currencies = (c.env.SUPPORTED_CURRENCIES ?? 'EUR,USD,GBP')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean)
  return c.json({
    environment: c.env.ENVIRONMENT,
    peppol: { enabled: peppolEnabled, mode: peppolMode },
    vatValidation: true,
    currencies,
  })
})
