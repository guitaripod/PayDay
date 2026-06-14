import type { Env } from '../../src/env'
import { makeFakeD1, makeFakeKV } from './fakes'


export type TestEnv = Env

export function makeEnv(overrides: Partial<Env> = {}): TestEnv {
  return {
    AUTH_NONCE: makeFakeKV(),
    FX_CACHE: makeFakeKV(),
    DB: makeFakeD1(),
    MAKO_BASE_URL: 'https://mako.test',
    PEPPOL_PROVIDER: '',
    PEPPOL_API_KEY: '',
    PEPPOL_API_SECRET: '',
    PEPPOL_GATEWAY_BASE: 'https://api.storecove.example/api/v2',
    PEPPOL_LEGAL_ENTITY_ID: '',
    SUPPORTED_CURRENCIES: 'EUR,USD,GBP',
    ENVIRONMENT: 'test',
    ...overrides,
  } as TestEnv
}
