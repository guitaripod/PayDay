import { Hono } from 'hono'
import type { AppVars, Env } from '../env'
import { requireAuth } from '../middleware/requireAuth'
import { makePeppolGateway, type PeppolRecipient } from '../lib/peppol'

export const peppolRoutes = new Hono<{ Bindings: Env; Variables: AppVars }>()

function parseRecipient(value: unknown): PeppolRecipient | null {
  if (typeof value !== 'object' || value === null) return null
  const r = value as Record<string, unknown>
  const endpointID = typeof r.endpointID === 'string' ? r.endpointID.trim() : ''
  const schemeID = typeof r.schemeID === 'string' ? r.schemeID.trim() : ''
  const countryCode = typeof r.countryCode === 'string' ? r.countryCode.trim() : ''
  if (!endpointID || !schemeID) return null
  return { endpointID, schemeID, countryCode }
}

peppolRoutes.post('/v1/peppol/lookup', requireAuth, async (c) => {
  let body: { recipient?: unknown }
  try {
    body = await c.req.json()
  } catch {
    return c.json({ error: 'invalid_json' }, 400)
  }
  const recipient = parseRecipient(body.recipient)
  if (!recipient) return c.json({ error: 'recipient_required' }, 400)
  const gateway = makePeppolGateway(c.env)
  const reachability = await gateway.lookup(recipient)
  return c.json(reachability)
})

peppolRoutes.post('/v1/peppol/send', requireAuth, async (c) => {
  let body: { ublXML?: string; recipient?: unknown; invoiceNumber?: string }
  try {
    body = await c.req.json()
  } catch {
    return c.json({ error: 'invalid_json' }, 400)
  }
  const ublXML = (body.ublXML ?? '').trim()
  const recipient = parseRecipient(body.recipient)
  if (!ublXML) return c.json({ error: 'ublXML_required' }, 400)
  if (!recipient) return c.json({ error: 'recipient_required' }, 400)

  const userId = c.get('userId')
  const gateway = makePeppolGateway(c.env)
  const result = await gateway.send(ublXML, recipient)

  await c.env.DB.prepare(
    `INSERT INTO peppol_sends (id, user_id, invoice_number, recipient_endpoint, transmission_id, status, reason)
     VALUES (?, ?, ?, ?, ?, ?, ?)`
  )
    .bind(
      crypto.randomUUID(),
      userId,
      body.invoiceNumber ?? '',
      recipient.endpointID,
      result.transmissionID ?? null,
      result.status,
      result.reason ?? null
    )
    .run()

  const status = result.status === 'accepted' ? 200 : 502
  return c.json(result, status)
})
