import { describe, it, expect } from 'vitest'
import { getPublicKey, nip19 } from 'nostr-tools'
import { decodeNsec, passkeyErrorMessage } from '@/lib/nosskey'

describe('decodeNsec', () => {
  // A fixed, well-known secret key for deterministic assertions.
  const skHex = '0000000000000000000000000000000000000000000000000000000000000001'
  const skBytes = Uint8Array.from(
    skHex.match(/.{2}/g)!.map((b) => parseInt(b, 16))
  )
  const nsec = nip19.nsecEncode(skBytes)

  it('decodes a valid nsec into 32 raw bytes', () => {
    const decoded = decodeNsec(nsec)
    expect(decoded).toBeInstanceOf(Uint8Array)
    expect(decoded.length).toBe(32)
    expect(Array.from(decoded)).toEqual(Array.from(skBytes))
    // Round-trips to the same pubkey as the original key.
    expect(getPublicKey(decoded)).toBe(getPublicKey(skBytes))
  })

  it('decodes a 64-char hex secret key', () => {
    const decoded = decodeNsec(skHex)
    expect(decoded.length).toBe(32)
    expect(Array.from(decoded)).toEqual(Array.from(skBytes))
  })

  it('accepts hex regardless of case and surrounding whitespace', () => {
    const decoded = decodeNsec(`  ${skHex.toUpperCase()}  `)
    expect(Array.from(decoded)).toEqual(Array.from(skBytes))
  })

  it('trims whitespace around an nsec', () => {
    const decoded = decodeNsec(`  ${nsec}  `)
    expect(Array.from(decoded)).toEqual(Array.from(skBytes))
  })

  it('rejects an empty input', () => {
    expect(() => decodeNsec('')).toThrow()
    expect(() => decodeNsec('   ')).toThrow()
  })

  it('rejects an npub (public key)', () => {
    const npub = nip19.npubEncode(getPublicKey(skBytes))
    expect(() => decodeNsec(npub)).toThrow(/nsec/)
  })

  it('rejects a malformed nsec', () => {
    expect(() => decodeNsec('nsec1notarealkey')).toThrow()
  })

  it('rejects hex that is not 64 characters', () => {
    expect(() => decodeNsec('abcd')).toThrow()
    expect(() => decodeNsec(skHex + 'ab')).toThrow()
  })

  it('rejects non-hex garbage', () => {
    expect(() => decodeNsec('not a key at all')).toThrow()
  })
})

describe('passkeyErrorMessage', () => {
  it('returns the given cancelled text for NotAllowedError', () => {
    const err = Object.assign(new Error('The operation either timed out or was not allowed'), {
      name: 'NotAllowedError',
    })
    expect(passkeyErrorMessage(err, { cancelled: '登録がキャンセルされました' })).toBe(
      '登録がキャンセルされました'
    )
  })

  it('uses a default cancelled message when none is provided', () => {
    const err = Object.assign(new Error('cancelled'), { name: 'NotAllowedError' })
    expect(passkeyErrorMessage(err)).toBe('パスキー認証がキャンセルされました')
  })

  it('returns the "not found" message when no credentials exist', () => {
    const err = new Error('No credentials available')
    expect(passkeyErrorMessage(err)).toMatch(/パスキーが見つかりません/)
  })

  it('includes the password-manager hint for a generic passkey failure', () => {
    const err = new Error('PRF secret not available')
    const msg = passkeyErrorMessage(err)
    expect(msg).toMatch(/パスキーの認証に失敗しました/)
    expect(msg).toMatch(/Bitwarden/)
    expect(msg).toMatch(/PRF/)
  })

  it('includes the hint when passed a non-Error value', () => {
    const msg = passkeyErrorMessage(undefined)
    expect(msg).toMatch(/Bitwarden/)
  })
})
