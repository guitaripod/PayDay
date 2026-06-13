/// ECB daily euro reference rates. EUR is always the base in the published
/// feed; cross rates are derived. Display-only — never used to alter an
/// invoice's own monetary terms. Cached in KV for the day.

const ECB_DAILY = 'https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml'

/// Parse the ECB daily XML into a `{ CUR: rate-per-EUR }` map. The relevant
/// lines look like `<Cube currency="USD" rate="1.0801"/>`. Hand-parsed so the
/// worker carries no XML dependency.
export function parseEcbRates(xml: string): Record<string, number> {
  const rates: Record<string, number> = { EUR: 1 }
  const re = /currency=['"]([A-Z]{3})['"]\s+rate=['"]([0-9.]+)['"]/g
  let m: RegExpExecArray | null
  while ((m = re.exec(xml)) !== null) {
    const value = Number(m[2])
    if (Number.isFinite(value) && value > 0) rates[m[1]] = value
  }
  return rates
}

export function crossRate(rates: Record<string, number>, base: string, quote: string): number | null {
  const b = rates[base.toUpperCase()]
  const q = rates[quote.toUpperCase()]
  if (!b || !q) return null
  return q / b
}

export async function loadRates(
  cache: KVNamespace,
  fetchImpl: typeof fetch = fetch
): Promise<Record<string, number>> {
  const cached = await cache.get('ecb-daily', 'json')
  if (cached) return cached as Record<string, number>
  const res = await fetchImpl(ECB_DAILY)
  if (!res.ok) throw new Error(`ecb_unavailable_${res.status}`)
  const rates = parseEcbRates(await res.text())
  await cache.put('ecb-daily', JSON.stringify(rates), { expirationTtl: 12 * 60 * 60 })
  return rates
}
