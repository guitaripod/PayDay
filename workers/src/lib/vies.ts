/// EU VIES VAT-number validation via the official REST API. Validation is
/// advisory: any failure to reach VIES degrades to `reachable: false` and must
/// never block the app from issuing an invoice.

export type VATValidationResult = {
  vatID: string
  valid: boolean
  reachable: boolean
  name?: string
  address?: string
}

type ViesRestResponse = {
  isValid?: boolean
  name?: string
  address?: string
  userError?: string
}

/// Split a VAT id like "FI12345678" into the 2-letter member-state code and the
/// remaining number. Returns null when the shape is obviously invalid.
export function splitVAT(vatID: string): { country: string; number: string } | null {
  const cleaned = vatID.replace(/[\s-]/g, '').toUpperCase()
  const match = /^([A-Z]{2})([0-9A-Z]+)$/.exec(cleaned)
  if (!match) return null
  return { country: match[1], number: match[2] }
}

export function parseViesResponse(vatID: string, body: ViesRestResponse): VATValidationResult {
  return {
    vatID,
    valid: body.isValid === true,
    reachable: true,
    name: body.name && body.name !== '---' ? body.name : undefined,
    address: body.address && body.address !== '---' ? body.address : undefined,
  }
}

const VIES_BASE = 'https://ec.europa.eu/taxation_customs/vies/rest-api/ms'

export async function checkVAT(
  vatID: string,
  fetchImpl: typeof fetch = fetch,
  timeoutMs = 6000
): Promise<VATValidationResult> {
  const parts = splitVAT(vatID)
  if (!parts) return { vatID, valid: false, reachable: true }

  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), timeoutMs)
  try {
    const res = await fetchImpl(`${VIES_BASE}/${parts.country}/vat/${parts.number}`, {
      headers: { accept: 'application/json' },
      signal: controller.signal,
    })
    if (!res.ok) return { vatID, valid: false, reachable: false }
    const body = (await res.json()) as ViesRestResponse
    return parseViesResponse(vatID, body)
  } catch {
    return { vatID, valid: false, reachable: false }
  } finally {
    clearTimeout(timer)
  }
}
