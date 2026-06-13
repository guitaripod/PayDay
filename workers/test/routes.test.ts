import { describe, expect, it } from 'vitest'
import app from '../src/index'
import { mintAppJWT } from '../src/lib/jwt'
import { APP_JWT_SECRET, makeEnv } from './helpers/env'

async function authHeader() {
  const token = await mintAppJWT({ uid: 'user-1' }, APP_JWT_SECRET)
  return { authorization: `Bearer ${token}` }
}

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
        headers: { ...(await authHeader()), 'content-type': 'application/json' },
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
        headers: { ...(await authHeader()), 'content-type': 'application/json' },
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
