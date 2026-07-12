import { describe, it, expect } from 'vitest'
import { getPublicKey, nip19 } from 'nostr-tools'
import { decodeNsec } from '@/lib/nosskey'

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
