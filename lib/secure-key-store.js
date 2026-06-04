/**
 * Secure Key Store for Nostr Private Keys
 *
 * This module provides a secure way to store private keys in memory
 * without exposing them on the global window object.
 *
 * Security features:
 * - Keys stored in module-private closure (not accessible from global scope)
 * - Keys are cleared from memory on page unload
 * - Explicitly exported keys are persisted encrypted-at-rest for auto-sign restore
 * - No direct access to raw key material from outside
 * - Automatic cleanup on logout
 *
 * @module secure-key-store
 */

/** @type {Map<string, Uint8Array>} */
const keyStore = new Map()

/** @type {string | null} */
let currentPubkey = null

const PERSIST_DB_NAME = 'nurunuru_secure_key_store'
const PERSIST_DB_VERSION = 1
const PERSIST_STORE_NAME = 'crypto_keys'
const PERSIST_KEY_ID = 'private_key_encryption_key'
const PERSIST_STORAGE_PREFIX = 'nurunuru_encrypted_private_key:'

let persistentCryptoKeyPromise = null

function persistentStorageKey(pubkey) {
  return `${PERSIST_STORAGE_PREFIX}${pubkey}`
}

function bytesToBase64(bytes) {
  let binary = ''
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000))
  }
  return btoa(binary)
}

function base64ToBytes(value) {
  const binary = atob(value)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i)
  }
  return bytes
}

function openPersistentKeyDb() {
  return new Promise((resolve, reject) => {
    if (typeof indexedDB === 'undefined') {
      reject(new Error('IndexedDB is not available'))
      return
    }

    const request = indexedDB.open(PERSIST_DB_NAME, PERSIST_DB_VERSION)
    request.onupgradeneeded = () => {
      const db = request.result
      if (!db.objectStoreNames.contains(PERSIST_STORE_NAME)) {
        db.createObjectStore(PERSIST_STORE_NAME)
      }
    }
    request.onsuccess = () => resolve(request.result)
    request.onerror = () => reject(request.error || new Error('Failed to open IndexedDB'))
  })
}

function idbGet(db, key) {
  return new Promise((resolve, reject) => {
    const tx = db.transaction(PERSIST_STORE_NAME, 'readonly')
    const req = tx.objectStore(PERSIST_STORE_NAME).get(key)
    req.onsuccess = () => resolve(req.result || null)
    req.onerror = () => reject(req.error || new Error('IndexedDB get failed'))
  })
}

function idbPut(db, key, value) {
  return new Promise((resolve, reject) => {
    const tx = db.transaction(PERSIST_STORE_NAME, 'readwrite')
    const req = tx.objectStore(PERSIST_STORE_NAME).put(value, key)
    req.onsuccess = () => resolve()
    req.onerror = () => reject(req.error || new Error('IndexedDB put failed'))
  })
}

async function getPersistentCryptoKey() {
  if (persistentCryptoKeyPromise) return persistentCryptoKeyPromise

  persistentCryptoKeyPromise = (async () => {
    const db = await openPersistentKeyDb()
    try {
      const existing = await idbGet(db, PERSIST_KEY_ID)
      if (existing) return existing

      const key = await crypto.subtle.generateKey(
        { name: 'AES-GCM', length: 256 },
        false,
        ['encrypt', 'decrypt']
      )
      await idbPut(db, PERSIST_KEY_ID, key)
      return key
    } finally {
      db.close?.()
    }
  })()

  return persistentCryptoKeyPromise
}

/**
 * Store a private key securely in memory.
 * @param {string} pubkey - The public key associated with this private key
 * @param {string} privateKeyHex - The private key in hex format
 * @param {{ persist?: boolean }} [options] - Persist encrypted-at-rest when explicitly requested
 * @returns {boolean} True if stored successfully
 */
export function storePrivateKey(pubkey, privateKeyHex, options = {}) {
  if (!pubkey || !privateKeyHex) return false

  try {
    // Convert hex to bytes for storage
    const bytes = hexToBytes(privateKeyHex)
    keyStore.set(pubkey, bytes)
    currentPubkey = pubkey

    // Persist only when an explicit key-export flow requests it. This keeps
    // normal passkey login single-prompt and avoids silently writing the raw
    // key from sign-up / DM fallback paths. The raw key is never attached to
    // window and the persistent copy is encrypted with a non-extractable
    // per-origin AES-GCM CryptoKey in IndexedDB.
    if (options.persist) {
      void persistPrivateKey(pubkey, privateKeyHex)
    }
    return true
  } catch (e) {
    console.error('Failed to store private key:', e)
    return false
  }
}

/**
 * Check whether an encrypted persistent private key exists for a pubkey.
 * This does not decrypt or load the key into memory.
 * @param {string} [pubkey]
 * @returns {boolean}
 */
export function hasPersistedPrivateKey(pubkey) {
  if (typeof window === 'undefined') return false
  const key = pubkey || currentPubkey
  return !!key && localStorage.getItem(persistentStorageKey(key)) !== null
}

/**
 * Persist a private key encrypted at rest for auto-sign restoration.
 * @param {string} pubkey
 * @param {string} privateKeyHex
 * @returns {Promise<boolean>}
 */
export async function persistPrivateKey(pubkey, privateKeyHex) {
  if (typeof window === 'undefined' || !pubkey || !privateKeyHex) return false

  try {
    const cryptoKey = await getPersistentCryptoKey()
    const iv = crypto.getRandomValues(new Uint8Array(12))
    const plaintext = new TextEncoder().encode(JSON.stringify({
      privateKeyHex,
      createdAt: Date.now()
    }))
    const ciphertext = new Uint8Array(await crypto.subtle.encrypt(
      { name: 'AES-GCM', iv },
      cryptoKey,
      plaintext
    ))

    localStorage.setItem(persistentStorageKey(pubkey), JSON.stringify({
      v: 1,
      alg: 'AES-GCM',
      iv: bytesToBase64(iv),
      ciphertext: bytesToBase64(ciphertext)
    }))
    return true
  } catch (e) {
    console.error('Failed to persist private key:', e)
    return false
  }
}

/**
 * Restore an encrypted persistent private key into the in-memory key store.
 * Does not trigger WebAuthn / passkey prompts.
 * @param {string} pubkey
 * @returns {Promise<boolean>}
 */
export async function restorePrivateKey(pubkey) {
  if (typeof window === 'undefined' || !pubkey) return false

  const stored = localStorage.getItem(persistentStorageKey(pubkey))
  if (!stored) return false

  try {
    const payload = JSON.parse(stored)
    if (payload?.v !== 1 || payload?.alg !== 'AES-GCM') return false

    const cryptoKey = await getPersistentCryptoKey()
    const plaintext = await crypto.subtle.decrypt(
      { name: 'AES-GCM', iv: base64ToBytes(payload.iv) },
      cryptoKey,
      base64ToBytes(payload.ciphertext)
    )
    const { privateKeyHex } = JSON.parse(new TextDecoder().decode(plaintext))
    if (!privateKeyHex) return false

    const bytes = hexToBytes(privateKeyHex)
    keyStore.set(pubkey, bytes)
    currentPubkey = pubkey
    return true
  } catch (e) {
    console.error('Failed to restore private key:', e)
    return false
  }
}

/**
 * Remove the encrypted persistent private key for a pubkey.
 * @param {string} [pubkey]
 */
export function removePersistedPrivateKey(pubkey) {
  if (typeof window === 'undefined') return
  const key = pubkey || currentPubkey
  if (key) {
    localStorage.removeItem(persistentStorageKey(key))
  }
}

/**
 * Check if a private key is stored for the given pubkey
 * @param {string} [pubkey] - The public key to check (defaults to current)
 * @returns {boolean} True if a key is stored
 */
export function hasPrivateKey(pubkey) {
  const key = pubkey || currentPubkey
  return key ? keyStore.has(key) : false
}

/**
 * Get the stored private key as hex string
 * @param {string} [pubkey] - The public key to get (defaults to current)
 * @returns {string | null} The private key in hex format, or null if not found
 */
export function getPrivateKeyHex(pubkey) {
  const key = pubkey || currentPubkey
  if (!key) return null

  const bytes = keyStore.get(key)
  if (!bytes) return null

  return bytesToHex(bytes)
}

/**
 * Get the stored private key as Uint8Array
 * @param {string} [pubkey] - The public key to get (defaults to current)
 * @returns {Uint8Array | null} The private key as bytes, or null if not found
 */
export function getPrivateKeyBytes(pubkey) {
  const key = pubkey || currentPubkey
  if (!key) return null

  const bytes = keyStore.get(key)
  if (!bytes) return null

  // Return a copy to prevent external modification
  return new Uint8Array(bytes)
}

/**
 * Clear the private key for a specific pubkey
 * @param {string} [pubkey] - The public key to clear (defaults to current)
 */
export function clearPrivateKey(pubkey) {
  const key = pubkey || currentPubkey
  if (key) {
    // Overwrite with zeros before deleting (defense in depth)
    const bytes = keyStore.get(key)
    if (bytes) {
      bytes.fill(0)
    }
    keyStore.delete(key)
    removePersistedPrivateKey(key)

    if (currentPubkey === key) {
      currentPubkey = null
    }
  }
}

/**
 * Clear all stored private keys
 */
export function clearAllPrivateKeys() {
  // Overwrite all keys with zeros before clearing
  for (const bytes of keyStore.values()) {
    bytes.fill(0)
  }
  keyStore.clear()
  currentPubkey = null
}

/**
 * Set the current active pubkey
 * @param {string | null} pubkey
 */
export function setCurrentPubkey(pubkey) {
  currentPubkey = pubkey
}

/**
 * Get the current active pubkey
 * @returns {string | null}
 */
export function getCurrentPubkey() {
  return currentPubkey
}

// Helper functions (duplicated here to avoid circular imports)

/**
 * Convert hex string to Uint8Array
 * @param {string} hex
 * @returns {Uint8Array}
 */
function hexToBytes(hex) {
  const bytes = new Uint8Array(hex.length / 2)
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.substr(i, 2), 16)
  }
  return bytes
}

/**
 * Convert Uint8Array to hex string
 * @param {Uint8Array} bytes
 * @returns {string}
 */
function bytesToHex(bytes) {
  return Array.from(bytes)
    .map(b => b.toString(16).padStart(2, '0'))
    .join('')
}

// Cleanup on page unload
if (typeof window !== 'undefined') {
  window.addEventListener('beforeunload', () => {
    clearAllPrivateKeys()
  })

  // Keys remain in memory until explicit logout or page unload
}
