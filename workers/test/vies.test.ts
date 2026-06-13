import { describe, expect, it } from 'vitest'
import { parseViesResponse, splitVAT } from '../src/lib/vies'

describe('vies vat', () => {
  it('splits a vat id into country and number', () => {
    expect(splitVAT('FI12345678')).toEqual({ country: 'FI', number: '12345678' })
    expect(splitVAT('de 123 456 789')).toEqual({ country: 'DE', number: '123456789' })
    expect(splitVAT('12345678')).toBeNull()
    expect(splitVAT('')).toBeNull()
  })

  it('parses a valid VIES response', () => {
    const r = parseViesResponse('FI12345678', { isValid: true, name: 'Aurora Studio Oy', address: 'Helsinki' })
    expect(r).toEqual({
      vatID: 'FI12345678',
      valid: true,
      reachable: true,
      name: 'Aurora Studio Oy',
      address: 'Helsinki',
    })
  })

  it('treats placeholder dashes as absent', () => {
    const r = parseViesResponse('FI12345678', { isValid: false, name: '---', address: '---' })
    expect(r.valid).toBe(false)
    expect(r.name).toBeUndefined()
    expect(r.address).toBeUndefined()
  })
})
