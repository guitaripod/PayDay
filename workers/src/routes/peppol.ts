import { Hono } from 'hono'
import type { AppVars, Env } from '../env'
import { requireAuth } from '../middleware/requireAuth'
import { makePeppolGateway, type PeppolRecipient, type SendResult } from '../lib/peppol'

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

const MAX_UBL_BYTES = 512 * 1024

/// Transmits a UBL invoice over Peppol, exactly-once and self-healing. A
/// previously-accepted (user, idempotencyKey) replays without re-sending; there is
/// deliberately no in-flight lock, so an interrupted send records and charges
/// nothing and the next attempt simply re-sends. The gateway call is guarded (a
/// throw is treated as a retriable failure), the accepted row is anchored on the
/// UNIQUE key before metering so a concurrent double-tap charges at most once, and
/// the credit is taken only after acceptance so a rejected document never costs.
peppolRoutes.post('/v1/peppol/send', requireAuth, async (c) => {
  let body: { ublXML?: string; recipient?: unknown; invoiceNumber?: string; idempotencyKey?: string }
  try {
    body = await c.req.json()
  } catch {
    return c.json({ error: 'invalid_json' }, 400)
  }
  const ublXML = (body.ublXML ?? '').trim()
  const recipient = parseRecipient(body.recipient)
  if (!ublXML) return c.json({ error: 'ublXML_required' }, 400)
  if (!recipient) return c.json({ error: 'recipient_required' }, 400)
  if (ublXML.length > MAX_UBL_BYTES) return c.json({ error: 'ublXML_too_large' }, 413)
  if (!ublXML.startsWith('<') || !(ublXML.includes('<Invoice') || ublXML.includes('<CreditNote'))) {
    return c.json({ error: 'ublXML_not_an_invoice' }, 400)
  }

  const userId = c.get('userId')
  const invoiceNumber = (body.invoiceNumber ?? '').toString()
  const key = (body.idempotencyKey ?? '').toString().trim() || `${invoiceNumber}|${recipient.endpointID}`

  const prior = await c.env.DB.prepare(
    `SELECT transmission_id FROM peppol_sends WHERE user_id = ? AND idempotency_key = ? AND status = 'accepted'`
  )
    .bind(userId, key)
    .first<{ transmission_id: string | null }>()
  if (prior) {
    return c.json({ status: 'accepted', transmissionID: prior.transmission_id ?? undefined, idempotent: true }, 200)
  }

  const gateway = makePeppolGateway(c.env)
  let result: SendResult
  try {
    result = await gateway.send(ublXML, recipient)
  } catch {
    return c.json({ status: 'failed', reason: 'gateway_unavailable', retriable: true }, 502)
  }

  if (result.status !== 'accepted') {
    await recordSend(c.env.DB, userId, key, invoiceNumber, recipient.endpointID, 'failed', null, result.reason ?? null)
    return c.json(result, 502)
  }

  const rowId = crypto.randomUUID()
  const claim = await c.env.DB.prepare(
    `INSERT INTO peppol_sends (id, user_id, idempotency_key, invoice_number, recipient_endpoint, transmission_id, status, charged)
     VALUES (?, ?, ?, ?, ?, ?, 'accepted', 0) ON CONFLICT(user_id, idempotency_key) DO NOTHING`
  )
    .bind(rowId, userId, key, invoiceNumber, recipient.endpointID, result.transmissionID ?? null)
    .run()
  if ((claim.meta?.changes ?? 0) !== 1) {
    return c.json({ ...result, idempotent: true }, 200)
  }

  const balance = await meterSend(c.env, c.req.header('Authorization')!, key, userId, rowId)
  return c.json(balance === undefined ? result : { ...result, balance }, 200)
})

async function recordSend(
  db: D1Database, userId: string, key: string, invoiceNumber: string,
  endpoint: string, status: string, transmissionID: string | null, reason: string | null
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO peppol_sends (id, user_id, idempotency_key, invoice_number, recipient_endpoint, transmission_id, status, reason)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(user_id, idempotency_key) DO NOTHING`
    )
    .bind(crypto.randomUUID(), userId, key, invoiceNumber, endpoint, transmissionID, status, reason)
    .run()
}

/// Charges the accepted send once (mako is authoritative; charge is post-accept so
/// a rejected document never costs the user). Records the credit on success and
/// returns the new balance; an insufficient/failed/unreachable charge is logged
/// but never undoes the already-delivered transmission.
async function meterSend(
  env: Env, authorization: string, key: string, userId: string, rowId: string
): Promise<number | undefined> {
  try {
    const charge = await fetch(`${env.MAKO_BASE_URL}/v1/credits/charge`, {
      method: 'POST',
      headers: { authorization, 'x-app-id': 'payday', 'content-type': 'application/json' },
      body: JSON.stringify({ capability: 'peppol.send', reference: key }),
    })
    if (charge.ok) {
      await env.DB.prepare(`UPDATE peppol_sends SET charged = 1 WHERE id = ?`).bind(rowId).run()
      return ((await charge.json()) as { balance?: number }).balance
    }
    if (charge.status === 402) {
      console.error(`peppol.send transmitted but user ${userId} had insufficient credits (key=${key})`)
    } else {
      console.error(`peppol.send charge failed status=${charge.status} (key=${key})`)
    }
  } catch (e) {
    console.error(`peppol.send charge threw (key=${key}):`, e)
  }
  return undefined
}
