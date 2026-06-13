import { describe, expect, it } from 'vitest'
import {
  RecommandPeppolGateway,
  StorecovePeppolGateway,
  StubPeppolGateway,
  makePeppolGateway,
} from '../src/lib/peppol'
import { makeEnv } from './helpers/env'

type Captured = { url: string; init: RequestInit }

function recordingFetch(response: unknown, ok = true, status = 200) {
  const calls: Captured[] = []
  const impl = (async (url: string | URL | Request, init?: RequestInit) => {
    calls.push({ url: String(url), init: init ?? {} })
    return {
      ok,
      status,
      async json() {
        return response
      },
      async text() {
        return JSON.stringify(response)
      },
    } as unknown as Response
  }) as unknown as typeof fetch
  return { impl, calls }
}

function bodyOf(call: Captured): Record<string, unknown> {
  return JSON.parse(call.init.body as string)
}

describe('peppol gateway', () => {
  it('stub gateway reaches well-formed participants', async () => {
    const gw = new StubPeppolGateway()
    const reach = await gw.lookup({ endpointID: '0037:12345678', schemeID: '0037', countryCode: 'FI' })
    expect(reach.reachable).toBe(true)
    const bad = await gw.lookup({ endpointID: 'nope', schemeID: 'x', countryCode: 'FI' })
    expect(bad.reachable).toBe(false)
  })

  it('stub gateway accepts a send to a reachable participant', async () => {
    const gw = new StubPeppolGateway()
    const result = await gw.send('<Invoice/>', { endpointID: '9930:DE123', schemeID: '9930', countryCode: 'DE' })
    expect(result.status).toBe('accepted')
    expect(result.transmissionID).toContain('9930:DE123')
  })

  it('falls back to the stub gateway when no API key is configured', () => {
    const gw = makePeppolGateway(makeEnv())
    expect(gw).toBeInstanceOf(StubPeppolGateway)
  })

  it('selects the Recommand gateway when provider=recommand and all vars set', () => {
    const gw = makePeppolGateway(
      makeEnv({
        PEPPOL_PROVIDER: 'recommand',
        PEPPOL_API_KEY: 'k',
        PEPPOL_API_SECRET: 's',
        PEPPOL_GATEWAY_BASE: 'https://app.recommand.eu',
        PEPPOL_LEGAL_ENTITY_ID: 'company_123',
      })
    )
    expect(gw).toBeInstanceOf(RecommandPeppolGateway)
  })

  it('selects the Storecove gateway when its three vars are set (default provider)', () => {
    const gw = makePeppolGateway(
      makeEnv({
        PEPPOL_API_KEY: 'k',
        PEPPOL_GATEWAY_BASE: 'https://api.storecove.com/api/v2',
        PEPPOL_LEGAL_ENTITY_ID: '4242',
      })
    )
    expect(gw).toBeInstanceOf(StorecovePeppolGateway)
  })
})

describe('recommand adapter wire shape', () => {
  const recipient = { endpointID: '987654321', schemeID: '0208', countryCode: 'BE' }

  it('sends raw UBL verbatim as documentType:xml with Basic auth and companyId in path', async () => {
    const { impl, calls } = recordingFetch({ id: 'doc_01', peppolMessageId: 'msg_99' })
    const gw = new RecommandPeppolGateway('https://app.recommand.eu', 'key', 'secret', 'company_123', impl)
    const result = await gw.send('<Invoice>raw</Invoice>', recipient)

    expect(calls[0].url).toBe('https://app.recommand.eu/api/v1/company_123/send')
    const headers = calls[0].init.headers as Record<string, string>
    expect(headers.authorization).toBe(`Basic ${btoa('key:secret')}`)
    const body = bodyOf(calls[0])
    expect(body.recipient).toBe('0208:987654321')
    expect(body.documentType).toBe('xml')
    expect(body.document).toBe('<Invoice>raw</Invoice>')
    expect(result.status).toBe('accepted')
    expect(result.transmissionID).toBe('msg_99')
  })

  it('verifies reachability via /api/v1/verify using peppolAddress and isValid', async () => {
    const { impl, calls } = recordingFetch({ success: true, isValid: true })
    const gw = new RecommandPeppolGateway('https://app.recommand.eu', 'key', 'secret', 'company_123', impl)
    const reach = await gw.lookup(recipient)
    expect(calls[0].url).toBe('https://app.recommand.eu/api/v1/verify')
    expect(bodyOf(calls[0]).peppolAddress).toBe('0208:987654321')
    expect(reach.reachable).toBe(true)
  })

  it('reports unreachable when verify returns isValid:false', async () => {
    const { impl } = recordingFetch({ success: true, isValid: false })
    const gw = new RecommandPeppolGateway('https://app.recommand.eu', 'key', 'secret', 'company_123', impl)
    const reach = await gw.lookup(recipient)
    expect(reach.reachable).toBe(false)
  })

  it('surfaces the provider error body in reason on a non-OK send', async () => {
    const { impl } = recordingFetch({ error: 'validation-failed' }, false, 422)
    const gw = new RecommandPeppolGateway('https://app.recommand.eu', 'key', 'secret', 'company_123', impl)
    const result = await gw.send('<Invoice/>', recipient)
    expect(result.status).toBe('failed')
    expect(result.reason).toContain('gateway_422')
    expect(result.reason).toContain('validation-failed')
  })
})

describe('storecove adapter wire shape (post-fix)', () => {
  const recipient = { endpointID: 'DE123456', schemeID: '9930', countryCode: 'DE' }

  it('uses metaScheme (not metaSchemeId) on discovery', async () => {
    const { impl, calls } = recordingFetch({ code: 'OK' })
    const gw = new StorecovePeppolGateway('https://api.storecove.com/api/v2', 'key', '4242', impl)
    const reach = await gw.lookup(recipient)
    const body = bodyOf(calls[0])
    expect(body.metaScheme).toBe('iso6523-actorid-upis')
    expect(body).not.toHaveProperty('metaSchemeId')
    expect(reach.reachable).toBe(true)
  })

  it('sends legalEntityId as a number and base64 UBL with parse:false', async () => {
    const { impl, calls } = recordingFetch({ guid: 'g-1' })
    const gw = new StorecovePeppolGateway('https://api.storecove.com/api/v2', 'key', '4242', impl)
    const result = await gw.send('<Invoice/>', recipient)
    const body = bodyOf(calls[0]) as { legalEntityId: unknown; document: { rawDocumentData: { parse: boolean } } }
    expect(body.legalEntityId).toBe(4242)
    expect(body.document.rawDocumentData.parse).toBe(false)
    expect(result.transmissionID).toBe('g-1')
  })
})
