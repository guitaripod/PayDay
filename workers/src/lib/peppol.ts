/// Peppol access-point gateway abstraction. Pay Day is NOT an access point and
/// does not implement AS4/SML/SMP; it brokers transmission through a third-party
/// gateway. Two adapters ship — Recommand (default, app.recommand.eu) and
/// Storecove (api.storecove.com) — selected by `PEPPOL_PROVIDER`. When the
/// provider secrets are absent the stub gateway runs, so the whole app —
/// including dev and CI — works without a live Peppol contract.

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
    private readonly fetchImpl: typeof fetch = fetch.bind(globalThis)
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
        metaScheme: 'iso6523-actorid-upis',
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
        legalEntityId: Number(this.legalEntityID),
        routing: {
          eIdentifiers: [{ scheme: recipient.schemeID, id: recipient.endpointID }],
        },
        document: {
          documentType: 'invoice',
          rawDocumentData: {
            document: btoa(unescape(encodeURIComponent(ublXML))),
            parse: false,
            parseStrategy: 'ubl',
          },
        },
      }),
    })
    if (!res.ok) {
      return { status: 'failed', reason: `gateway_${res.status}: ${await readError(res)}` }
    }
    const body = (await res.json()) as { guid?: string }
    return { status: 'accepted', transmissionID: body.guid }
  }
}

/// Recommand REST adapter (app.recommand.eu). Basic auth (key:secret), the
/// sending company id is carried in the URL path, and app-generated UBL is sent
/// verbatim as documentType:'xml' — no base64, no provider-side regeneration.
export class RecommandPeppolGateway implements PeppolGateway {
  constructor(
    private readonly base: string,
    private readonly apiKey: string,
    private readonly apiSecret: string,
    private readonly companyID: string,
    private readonly fetchImpl: typeof fetch = fetch.bind(globalThis)
  ) {}

  private headers(): HeadersInit {
    return {
      authorization: `Basic ${btoa(`${this.apiKey}:${this.apiSecret}`)}`,
      'content-type': 'application/json',
    }
  }

  async lookup(recipient: PeppolRecipient): Promise<Reachability> {
    const res = await this.fetchImpl(`${this.base}/api/v1/verify`, {
      method: 'POST',
      headers: this.headers(),
      body: JSON.stringify({
        peppolAddress: `${recipient.schemeID}:${recipient.endpointID}`,
      }),
    })
    if (!res.ok) return { reachable: false, supportedDocumentTypes: [] }
    const body = (await res.json()) as { success?: boolean; isValid?: boolean }
    const reachable = body.isValid === true
    return {
      reachable,
      supportedDocumentTypes: reachable ? ['urn:cen.eu:en16931:2017'] : [],
    }
  }

  async send(ublXML: string, recipient: PeppolRecipient): Promise<SendResult> {
    const res = await this.fetchImpl(
      `${this.base}/api/v1/${this.companyID}/send`,
      {
        method: 'POST',
        headers: this.headers(),
        body: JSON.stringify({
          recipient: `${recipient.schemeID}:${recipient.endpointID}`,
          documentType: 'xml',
          document: ublXML,
        }),
      }
    )
    if (!res.ok) {
      return { status: 'failed', reason: `gateway_${res.status}: ${await readError(res)}` }
    }
    const body = (await res.json()) as { id?: string; peppolMessageId?: string }
    return { status: 'accepted', transmissionID: body.peppolMessageId ?? body.id }
  }
}

async function readError(res: Response): Promise<string> {
  try {
    return (await res.text()).slice(0, 300)
  } catch {
    return ''
  }
}

export function makePeppolGateway(env: Env, fetchImpl: typeof fetch = fetch.bind(globalThis)): PeppolGateway {
  if (
    env.PEPPOL_PROVIDER === 'recommand' &&
    env.PEPPOL_API_KEY &&
    env.PEPPOL_API_SECRET &&
    env.PEPPOL_GATEWAY_BASE &&
    env.PEPPOL_LEGAL_ENTITY_ID
  ) {
    return new RecommandPeppolGateway(
      env.PEPPOL_GATEWAY_BASE,
      env.PEPPOL_API_KEY,
      env.PEPPOL_API_SECRET,
      env.PEPPOL_LEGAL_ENTITY_ID,
      fetchImpl
    )
  }
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
