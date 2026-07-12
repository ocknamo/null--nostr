import { nip19 } from 'nostr-tools'

// Storage keys shared across the app for the Nosskey (passkey) manager.
export const NOSSKEY_STORAGE_KEY = 'nurunuru_nosskey'
export const NOSSKEY_REGISTRY_STORAGE_KEY = 'nurunuru_nosskey_accounts'

/**
 * Create a NosskeyManager configured for this app.
 * Centralizes the storage/cache options so LoginScreen, SignUpModal and the
 * session restore path in app/page.js stay in sync.
 * @returns {Promise<import('nosskey-sdk').NosskeyManager>}
 */
export async function createNosskeyManager() {
  const { NosskeyManager } = await import('nosskey-sdk')
  return new NosskeyManager({
    storageOptions: {
      enabled: true,
      storageKey: NOSSKEY_STORAGE_KEY,
      registryStorageKey: NOSSKEY_REGISTRY_STORAGE_KEY,
    },
    cacheOptions: { enabled: true, timeoutMs: 3600000 },
  })
}

/**
 * Decode a user-supplied Nostr secret key into raw 32 bytes.
 * Accepts either an nsec (bech32) string or a 64-char hex string.
 * @param {string} input - nsec1... or 64 hex chars
 * @returns {Uint8Array} 32-byte secret key
 * @throws {Error} if the input is not a valid nsec/hex secret key
 */
export function decodeNsec(input) {
  const trimmed = (input || '').trim()
  if (!trimmed) {
    throw new Error('秘密鍵を入力してください')
  }

  if (trimmed.startsWith('nsec1')) {
    let decoded
    try {
      decoded = nip19.decode(trimmed)
    } catch {
      throw new Error('秘密鍵(nsec)の形式が正しくありません')
    }
    if (decoded.type !== 'nsec') {
      throw new Error('秘密鍵(nsec)を入力してください')
    }
    return decoded.data
  }

  // Allow raw hex secret keys as well.
  if (/^[0-9a-fA-F]{64}$/.test(trimmed)) {
    const bytes = new Uint8Array(32)
    for (let i = 0; i < 32; i++) {
      bytes[i] = parseInt(trimmed.slice(i * 2, i * 2 + 2), 16)
    }
    return bytes
  }

  if (trimmed.startsWith('npub1')) {
    throw new Error('公開鍵(npub)ではなく秘密鍵(nsec)を入力してください')
  }

  throw new Error('秘密鍵(nsec)の形式が正しくありません')
}
