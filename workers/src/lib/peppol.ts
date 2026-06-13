/// Peppol access-point gateway abstraction. Pay Day is NOT an access point and
/// does not implement AS4/SML/SMP; it brokers transmission through a third-party
/// gateway (Storecove-shaped here). When no API key is configured the stub
/// gateway runs, so the whole app — including dev and CI — works without a live
/// Peppol contract, and the seam lets us swap providers later.

import type { Env } from '../env'

export type PeppolRecipient = {
  endpointID: string
  schemeID: string
  countryCode: string
}

export type Reachability = {
  reachable: boolean
  supportedDocumentTypes: string[]
}

export type SendResult = {
  status: 'accepted' | 'failed'
  transmissionID?: string
  reason?: string
}

export interface PeppolGateway {
  lookup(recipient: PeppolRecipient): Promise<Reachability>
  send(ublXML: string, recipient: PeppolRecipient): Promise<SendResult>
}

/// Deterministic offline gateway: a participant id of the form `scheme:number`
/// is considered reachable; sends always "accept" with a synthetic id. Used in
/// dev/CI and as the safe default before a Peppol contract exists.
export class StubPeppolGateway implements PeppolGateway {
  async lookup(recipient: PeppolRecipient): Promise<Reachability> {
    const wellFormed = /^[0-9]{4}$/.test(recipient.schemeID) && recipient.endpointID.includes(':')
    return {
      reachable: wellFormed,
      supportedDocumentTypes: wellFormed ? ['urn:cen.eu:en16931:2017'] : [],
    }
  }

  async send(_ublXML: string, recipient: PeppolRecipient): Promise<SendResult> {
    const reach = await this.lookup(recipient)
    if (!reach.reachable) return { status: 'failed', reason: 'recipient_not_reachable' }
    return { status: 'accepted', transmissionID: `stub-${recipient.endpointID}` }
  }
}

/// Storecove REST adapter (api.storecove.com). Shapes the request the way the
/// provider expects; kept thin so the contract is obvious and replaceable.
export class StorecovePeppolGateway implements PeppolGateway {
  constructor(
    private readonly base: string,
    private readonly apiKey: string,
    private readonly legalEntityID: string,
    private readonly fetchImpl: typeof fetch = fetch
  ) {}

  private headers(): HeadersInit {
    return {
      authorization: `Bearer ${this.apiKey}`,
      'content-type': 'application/json',
    }
  }

  async lookup(recipient: PeppolRecipient): Promise<Reachability> {
    const res = await this.fetchImpl(`${this.base}/discovery/receives`, {
      method: 'POST',
      headers: this.headers(),
      body: JSON.stringify({
        documentTypes: ['invoice'],
        network: 'peppol',
        metaSchemeId: 'iso6523-actorid-upis',
        scheme: recipient.schemeID,
        identifier: recipient.endpointID,
      }),
    })
    if (!res.ok) return { reachable: false, supportedDocumentTypes: [] }
    const body = (await res.json()) as { code?: string }
    return {
      reachable: body.code === 'OK',
      supportedDocumentTypes: body.code === 'OK' ? ['urn:cen.eu:en16931:2017'] : [],
    }
  }

  async send(ublXML: string, recipient: PeppolRecipient): Promise<SendResult> {
    const res = await this.fetchImpl(`${this.base}/document_submissions`, {
      method: 'POST',
      headers: this.headers(),
      body: JSON.stringify({
        legalEntityId: this.legalEntityID,
        routing: {
          eIdentifiers: [{ scheme: recipient.schemeID, id: recipient.endpointID }],
        },
        document: {
          documentType: 'invoice',
          rawDocumentData: {
            document: btoa(unescape(encodeURIComponent(ublXML))),
            parse: true,
            parseStrategy: 'ubl',
          },
        },
      }),
    })
    if (!res.ok) {
      return { status: 'failed', reason: `gateway_${res.status}` }
    }
    const body = (await res.json()) as { guid?: string }
    return { status: 'accepted', transmissionID: body.guid }
  }
}

export function makePeppolGateway(env: Env, fetchImpl: typeof fetch = fetch): PeppolGateway {
  if (env.PEPPOL_API_KEY && env.PEPPOL_GATEWAY_BASE && env.PEPPOL_LEGAL_ENTITY_ID) {
    return new StorecovePeppolGateway(
      env.PEPPOL_GATEWAY_BASE,
      env.PEPPOL_API_KEY,
      env.PEPPOL_LEGAL_ENTITY_ID,
      fetchImpl
    )
  }
  return new StubPeppolGateway()
}
