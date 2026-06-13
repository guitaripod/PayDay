import type { Env } from '../../src/env'
import { makeFakeD1, makeFakeKV } from './fakes'

export const APPLE_CLIENT_ID = 'com.guitaripod.payday'
export const APPLE_TEAM_ID = 'AAAA111111'
export const APP_JWT_SECRET = 'unit-test-secret-do-not-use'

export type TestEnv = Env

export function makeEnv(overrides: Partial<Env> = {}): TestEnv {
  return {
    AUTH_NONCE: makeFakeKV(),
    FX_CACHE: makeFakeKV(),
    DB: makeFakeD1(),
    APP_JWT_SECRET,
    APPLE_CLIENT_ID,
    APPLE_TEAM_ID,
    PEPPOL_API_KEY: '',
    PEPPOL_GATEWAY_BASE: 'https://api.storecove.example/api/v2',
    PEPPOL_LEGAL_ENTITY_ID: '',
    SUPPORTED_CURRENCIES: 'EUR,USD,GBP',
    ENVIRONMENT: 'test',
    ...overrides,
  } as TestEnv
}
