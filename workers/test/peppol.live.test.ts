// @ts-nocheck — node-runtime live smoke harness (uses node fs/process); runs
// under vitest, not part of the worker's type-checked surface.
import { describe, it, expect } from 'vitest'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import { RecommandPeppolGateway } from '../src/lib/peppol'

/// Live sandbox smoke test against the Recommand PLAYGROUND. Skipped unless
/// PEPPOL_LIVE_SMOKE=1 and the four Recommand vars are present, so the normal
/// `npm test` never touches the network. Run via scripts/peppol-sandbox-smoke.sh.
const live = process.env.PEPPOL_LIVE_SMOKE === '1'
const base = process.env.PEPPOL_GATEWAY_BASE ?? ''
const key = process.env.PEPPOL_API_KEY ?? ''
const secret = process.env.PEPPOL_API_SECRET ?? ''
const companyID = process.env.PEPPOL_LEGAL_ENTITY_ID ?? ''
const ready = live && base && key && secret && companyID

const fixture = readFileSync(
  join(dirname(fileURLToPath(import.meta.url)), 'fixtures', 'sample-invoice.ubl.xml'),
  'utf8'
)

const recipient = {
  schemeID: process.env.PEPPOL_TEST_SCHEME ?? '9930',
  endpointID: process.env.PEPPOL_TEST_ENDPOINT ?? 'DE123456789',
  countryCode: 'DE',
}

const basicAuth = `Basic ${btoa(`${key}:${secret}`)}`

describe.skipIf(!ready)('recommand playground live smoke', () => {
  it('verify endpoint accepts the peppolAddress wire shape (not 400/404)', async () => {
    const res = await fetch(`${base}/api/v1/verify`, {
      method: 'POST',
      headers: { authorization: basicAuth, 'content-type': 'application/json' },
      body: JSON.stringify({ peppolAddress: `${recipient.schemeID}:${recipient.endpointID}` }),
    })
    const text = await res.text()
    console.log(`[smoke] verify HTTP ${res.status} ${text.slice(0, 200)}`)
    expect(res.status).not.toBe(400)
    expect(res.status).not.toBe(404)
  })

  it('lookup() returns a Reachability without throwing', async () => {
    const gw = new RecommandPeppolGateway(base, key, secret, companyID)
    const reach = await gw.lookup(recipient)
    console.log(`[smoke] lookup reachable=${reach.reachable} docs=${reach.supportedDocumentTypes.join(',')}`)
    expect(typeof reach.reachable).toBe('boolean')
  })

  it('send() transmits the UBL fixture (accepted once the company is verified)', async () => {
    const gw = new RecommandPeppolGateway(base, key, secret, companyID)
    const result = await gw.send(fixture, recipient)
    console.log(`[smoke] send status=${result.status} id=${result.transmissionID ?? '-'} reason=${result.reason ?? '-'}`)
    expect(result.reason ?? '').not.toMatch(/gateway_(400|404)/)
    if (result.status === 'accepted') {
      expect(result.transmissionID).toBeTruthy()
    } else {
      expect(result.reason ?? '').toMatch(/verif/i)
      console.log('[smoke] NOTE: wire shape is correct; verify the company in the Recommand dashboard, then re-run for a real accepted send.')
    }
  })
})
