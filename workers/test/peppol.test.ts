import { describe, expect, it } from 'vitest'
import { StubPeppolGateway, makePeppolGateway } from '../src/lib/peppol'
import { makeEnv } from './helpers/env'

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
})
