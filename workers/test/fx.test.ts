import { describe, expect, it } from 'vitest'
import { crossRate, parseEcbRates } from '../src/lib/fx'

const SAMPLE_XML = `<?xml version="1.0" encoding="UTF-8"?>
<gesmes:Envelope>
  <Cube>
    <Cube time='2026-06-12'>
      <Cube currency='USD' rate='1.0801'/>
      <Cube currency='GBP' rate='0.8456'/>
      <Cube currency='SEK' rate='11.2050'/>
    </Cube>
  </Cube>
</gesmes:Envelope>`

describe('ecb fx', () => {
  it('parses currency rates and includes EUR base', () => {
    const rates = parseEcbRates(SAMPLE_XML)
    expect(rates.EUR).toBe(1)
    expect(rates.USD).toBe(1.0801)
    expect(rates.GBP).toBe(0.8456)
  })

  it('derives cross rates', () => {
    const rates = parseEcbRates(SAMPLE_XML)
    expect(crossRate(rates, 'EUR', 'USD')).toBeCloseTo(1.0801, 4)
    const usdToGbp = crossRate(rates, 'USD', 'GBP')!
    expect(usdToGbp).toBeCloseTo(0.8456 / 1.0801, 6)
    expect(crossRate(rates, 'EUR', 'ZZZ')).toBeNull()
  })
})
