import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import app from '../src/index'
import { makeEnv } from './helpers/env'

// Auth + metering go through mako; stub those endpoints so route tests stay offline.
function authHeader() {
  return { authorization: 'Bearer mako-api-key-user-1' }
}

beforeEach(() => {
  vi.stubGlobal('fetch', async (input: RequestInfo | URL) => {
    const url = typeof input === 'string' ? input : input.toString()
    if (url.endsWith('/v1/identity/me')) {
      return new Response(JSON.stringify({ user_id: 'user-1', app_id: 'payday' }), { status: 200 })
    }
    if (url.endsWith('/v1/credits/charge')) {
      return new Response(JSON.stringify({ charged: 30, balance: 70 }), { status: 200 })
    }
    return new Response('not mocked', { status: 404 })
  })
})

afterEach(() => vi.unstubAllGlobals())

describe('worker routes', () => {
  it('healthz is open', async () => {
    const res = await app.request('/v1/healthz', {}, makeEnv())
    expect(res.status).toBe(200)
    expect((await res.json<{ ok: boolean }>()).ok).toBe(true)
  })

  it('config reports stub peppol mode and currencies', async () => {
    const res = await app.request('/v1/config', {}, makeEnv())
    const body = await res.json<{ peppol: { enabled: boolean; mode: string }; currencies: string[] }>()
    expect(body.peppol.enabled).toBe(false)
    expect(body.peppol.mode).toBe('stub')
    expect(body.currencies).toContain('EUR')
  })

  it('protected routes reject missing auth', async () => {
    const res = await app.request('/v1/vat/validate', { method: 'POST', body: '{}' }, makeEnv())
    expect(res.status).toBe(401)
  })

  it('peppol lookup works with a valid token', async () => {
    const res = await app.request(
      '/v1/peppol/lookup',
      {
        method: 'POST',
        headers: { ...authHeader(), 'content-type': 'application/json' },
        body: JSON.stringify({ recipient: { endpointID: '0037:12345678', schemeID: '0037', countryCode: 'FI' } }),
      },
      makeEnv()
    )
    expect(res.status).toBe(200)
    expect((await res.json<{ reachable: boolean }>()).reachable).toBe(true)
  })

  it('peppol send records the transmission and returns 200', async () => {
    const env = makeEnv()
    const res = await app.request(
      '/v1/peppol/send',
      {
        method: 'POST',
        headers: { ...authHeader(), 'content-type': 'application/json' },
        body: JSON.stringify({
          ublXML: '<Invoice/>',
          invoiceNumber: 'INV-2026-0007',
          recipient: { endpointID: '9930:DE123456789', schemeID: '9930', countryCode: 'DE' },
        }),
      },
      env
    )
    expect(res.status).toBe(200)
    const body = await res.json<{ status: string; transmissionID: string }>()
    expect(body.status).toBe('accepted')
    expect((env.DB as unknown as { __sends: unknown[] }).__sends.length).toBe(1)
  })

  it('unknown path returns 404', async () => {
    const res = await app.request('/nope', {}, makeEnv())
    expect(res.status).toBe(404)
  })
})

type SendRow = { status: string; transmission_id: string | null; charged: number }
function ledger(env: ReturnType<typeof makeEnv>): SendRow[] {
  return (env.DB as unknown as { __sends: SendRow[] }).__sends
}
function sendRequest(env: ReturnType<typeof makeEnv>, overrides: Record<string, unknown> = {}) {
  return app.request(
    '/v1/peppol/send',
    {
      method: 'POST',
      headers: { ...authHeader(), 'content-type': 'application/json' },
      body: JSON.stringify({
        ublXML: '<Invoice/>',
        invoiceNumber: 'INV-2026-0007',
        recipient: { endpointID: '9930:DE123456789', schemeID: '9930', countryCode: 'DE' },
        ...overrides,
      }),
    },
    env
  )
}

describe('peppol send hardening', () => {
  it('rejects an oversized UBL payload before any work', async () => {
    const env = makeEnv()
    const res = await sendRequest(env, { ublXML: `<Invoice>${'x'.repeat(600 * 1024)}</Invoice>` })
    expect(res.status).toBe(413)
    expect(ledger(env).length).toBe(0)
  })

  it('rejects a payload that is not an invoice document', async () => {
    const env = makeEnv()
    const res = await sendRequest(env, { ublXML: '<nope/>' })
    expect(res.status).toBe(400)
    expect(ledger(env).length).toBe(0)
  })

  it('records a rejected send as failed and never charges for it', async () => {
    let charges = 0
    vi.stubGlobal('fetch', async (input: RequestInfo | URL) => {
      const url = input.toString()
      if (url.endsWith('/v1/identity/me')) return new Response(JSON.stringify({ user_id: 'user-1' }), { status: 200 })
      if (url.endsWith('/v1/credits/charge')) { charges++; return new Response(JSON.stringify({ balance: 60 }), { status: 200 }) }
      return new Response('not mocked', { status: 404 })
    })
    const env = makeEnv()
    // An endpoint without a scheme separator is unreachable to the stub gateway.
    const res = await sendRequest(env, { recipient: { endpointID: 'unreachable', schemeID: '9930', countryCode: 'DE' } })
    expect(res.status).toBe(502)
    const rows = ledger(env)
    expect(rows.length).toBe(1)
    expect(rows[0].status).toBe('failed')
    expect(rows[0].charged).toBe(0)
    expect(charges).toBe(0)
  })

  it('delivers and logs (does not fail the send) when the charge is insufficient', async () => {
    vi.stubGlobal('fetch', async (input: RequestInfo | URL) => {
      const url = input.toString()
      if (url.endsWith('/v1/identity/me')) return new Response(JSON.stringify({ user_id: 'user-1' }), { status: 200 })
      if (url.endsWith('/v1/credits/charge')) return new Response(JSON.stringify({ error: 'insufficient' }), { status: 402 })
      return new Response('not mocked', { status: 404 })
    })
    const env = makeEnv()
    const res = await sendRequest(env)
    expect(res.status).toBe(200)
    const rows = ledger(env)
    expect(rows.length).toBe(1)
    expect(rows[0].status).toBe('accepted')
    expect(rows[0].charged).toBe(0)
  })

  it('is idempotent: a replayed send transmits and charges exactly once', async () => {
    let charges = 0
    vi.stubGlobal('fetch', async (input: RequestInfo | URL) => {
      const url = input.toString()
      if (url.endsWith('/v1/identity/me')) return new Response(JSON.stringify({ user_id: 'user-1' }), { status: 200 })
      if (url.endsWith('/v1/credits/charge')) {
        charges++
        return new Response(JSON.stringify({ charged: 5, balance: 65 }), { status: 200 })
      }
      return new Response('not mocked', { status: 404 })
    })
    const env = makeEnv()
    const first = await sendRequest(env, { idempotencyKey: 'dup-key' })
    expect(first.status).toBe(200)
    const second = await sendRequest(env, { idempotencyKey: 'dup-key' })
    expect(second.status).toBe(200)
    expect((await second.json<{ idempotent?: boolean }>()).idempotent).toBe(true)
    expect(charges).toBe(1)
    const rows = ledger(env)
    expect(rows.length).toBe(1)
    expect(rows[0].status).toBe('accepted')
  })
})
