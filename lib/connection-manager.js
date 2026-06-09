/**
 * WebSocket Connection Manager for Nostr
 *
 * Provides robust connection management with:
 * - Singleton pool management
 * - Request queuing with global throttling
 * - Exponential backoff retry logic
 * - Connection health monitoring
 * - Rate limiting to prevent relay bans
 * - Failed relay tracking to skip unreachable relays
 * - Request deduplication to prevent redundant requests
 * - Automatic subscription reconnection
 * - Memory leak prevention with proper cleanup
 */

import { SimplePool } from 'nostr-tools/pool'
import { createRxNostr, createRxOneshotReq, createRxForwardReq, noopVerifier } from 'rx-nostr'
import { WS_CONFIG, DEDUP_CONFIG, CONNECTION_STATE } from './constants'
import { measureAsync } from './performance-metrics'
import { enqueuePublishOutbox, markPublishOutboxPublished, markPublishOutboxFailed } from './publish-outbox'

// ============================================
// Connection State
// ============================================
let pool = null
let poolLastUsed = Date.now()
let healthCheckTimer = null
let isClosing = false
let connectionState = CONNECTION_STATE.DISCONNECTED
let rxNostr = null

// Request queue state
const requestQueue = {
  pending: 0,
  queue: [],
  relayPending: new Map(),
}

// Rate limiter state per relay
const rateLimiters = new Map()

// Failed relay tracking
const failedRelays = new Map()

// Permanently disabled relays (e.g., SSL/TLS errors)
const disabledRelays = new Set()

// ============================================
// Request Deduplication
// ============================================
const pendingRequests = new Map()
const completedResults = new Map()

/**
 * Generate a cache key for a request
 */
function generateRequestKey(filter, relays) {
  const sortedRelays = [...relays].sort()
  return JSON.stringify({ filter, relays: sortedRelays })
}

/**
 * Deduplicate a request - returns existing promise if same request is in flight
 */
function deduplicateRequest(key, executeFn) {
  // Check if we have a recent completed result
  const completed = completedResults.get(key)
  if (completed && Date.now() - completed.timestamp < DEDUP_CONFIG.completedResultTTL) {
    return Promise.resolve(completed.result)
  }

  // Check if there's a pending request
  const pending = pendingRequests.get(key)
  if (pending && Date.now() - pending.timestamp < DEDUP_CONFIG.pendingRequestTTL) {
    return pending.promise
  }

  // Create new request
  const promise = executeFn().then(result => {
    pendingRequests.delete(key)
    completedResults.set(key, { result, timestamp: Date.now() })

    // Cleanup old completed results
    if (completedResults.size > DEDUP_CONFIG.maxPendingRequests) {
      const now = Date.now()
      for (const [k, v] of completedResults) {
        if (now - v.timestamp > DEDUP_CONFIG.completedResultTTL) {
          completedResults.delete(k)
        }
      }
    }

    return result
  }).catch(error => {
    pendingRequests.delete(key)
    throw error
  })

  pendingRequests.set(key, { promise, timestamp: Date.now() })
  return promise
}

// ============================================
// Token Bucket Rate Limiter
// ============================================
class TokenBucket {
  constructor(tokensPerSecond, bucketSize) {
    this.tokensPerSecond = tokensPerSecond
    this.bucketSize = bucketSize
    this.tokens = bucketSize
    this.lastRefill = Date.now()
  }

  refill() {
    const now = Date.now()
    const elapsed = (now - this.lastRefill) / 1000
    this.tokens = Math.min(this.bucketSize, this.tokens + elapsed * this.tokensPerSecond)
    this.lastRefill = now
  }

  tryConsume(count = 1) {
    this.refill()
    if (this.tokens >= count) {
      this.tokens -= count
      return true
    }
    return false
  }

  getWaitTime(count = 1) {
    this.refill()
    if (this.tokens >= count) return 0
    const needed = count - this.tokens
    return (needed / this.tokensPerSecond) * 1000
  }
}

/**
 * Get or create rate limiter for a relay
 */
function getRateLimiter(relay) {
  if (!rateLimiters.has(relay)) {
    rateLimiters.set(relay, new TokenBucket(
      WS_CONFIG.rateLimit.requestsPerSecond,
      WS_CONFIG.rateLimit.burstSize
    ))
  }
  return rateLimiters.get(relay)
}

// ============================================
// Relay Health Management
// ============================================

/**
 * Check if an error is SSL/TLS related
 */
function isSSLError(error) {
  if (!error) return false
  const message = error.message || error.toString() || ''
  const lowerMessage = message.toLowerCase()

  return lowerMessage.includes('ssl') ||
         lowerMessage.includes('tls') ||
         lowerMessage.includes('certificate') ||
         lowerMessage.includes('cert_') ||
         lowerMessage.includes('handshake') ||
         lowerMessage.includes('secure connection')
}

/**
 * Check if a relay is in cooldown due to repeated failures or permanently disabled
 */
function isRelayInCooldown(relay) {
  if (disabledRelays.has(relay)) return true

  const failureInfo = failedRelays.get(relay)
  if (!failureInfo) return false

  const now = Date.now()
  const cooldownExpired = now - failureInfo.lastFailure > WS_CONFIG.failedRelayCooldown

  if (cooldownExpired) {
    failedRelays.delete(relay)
    return false
  }

  return failureInfo.failures >= WS_CONFIG.maxFailuresBeforeCooldown
}

/**
 * Record a relay failure
 */
function recordRelayFailure(relay, error = null) {
  if (error && isSSLError(error)) {
    disabledRelays.add(relay)
    console.warn(`[Connection Manager] Relay ${relay} permanently disabled due to SSL/TLS error:`, error.message)
    return
  }

  const failureInfo = failedRelays.get(relay) || { failures: 0, lastFailure: 0 }
  failureInfo.failures++
  failureInfo.lastFailure = Date.now()
  failedRelays.set(relay, failureInfo)

  if (failureInfo.failures >= WS_CONFIG.maxFailuresBeforeCooldown) {
    console.warn(`[Connection Manager] Relay ${relay} in cooldown after ${failureInfo.failures} failures`)
  }
}

/**
 * Record a relay success (clears failure record)
 */
function recordRelaySuccess(relay) {
  failedRelays.delete(relay)
}

/**
 * Filter out relays that are in cooldown
 */
export function filterAvailableRelays(relays) {
  const available = relays.filter(relay => !isRelayInCooldown(relay))
  return available.length > 0 ? available : relays
}

// ============================================
// Rate Limiting & Queue Management
// ============================================

/**
 * Wait for rate limit to allow request
 */
async function waitForRateLimit(relay) {
  const limiter = getRateLimiter(relay)
  const waitTime = limiter.getWaitTime()

  if (waitTime > 0) {
    await new Promise(resolve => setTimeout(resolve, waitTime))
  }

  limiter.tryConsume()
}

/**
 * Calculate delay with exponential backoff and jitter
 */
function calculateBackoffDelay(attempt) {
  const { baseDelay, maxDelay, jitter } = WS_CONFIG.retry

  let delay = baseDelay * Math.pow(2, attempt)
  delay = Math.min(delay, maxDelay)

  const jitterAmount = delay * jitter * (Math.random() * 2 - 1)
  delay += jitterAmount

  return Math.max(0, delay)
}

/**
 * Acquire slot from request queue
 */
async function acquireSlot(relay) {
  // Check global limit
  while (requestQueue.pending >= WS_CONFIG.maxConcurrentRequests) {
    await new Promise(resolve => {
      requestQueue.queue.push(resolve)
    })
  }

  // Check per-relay limit
  const relayPending = requestQueue.relayPending.get(relay) || 0
  if (relayPending >= WS_CONFIG.maxRequestsPerRelay) {
    await new Promise(resolve => setTimeout(resolve, 100))
    return acquireSlot(relay)
  }

  // Wait for rate limit
  await waitForRateLimit(relay)

  // Acquire slot
  requestQueue.pending++
  requestQueue.relayPending.set(relay, (requestQueue.relayPending.get(relay) || 0) + 1)
}

/**
 * Release slot back to request queue
 */
function releaseSlot(relay) {
  requestQueue.pending = Math.max(0, requestQueue.pending - 1)

  const relayPending = requestQueue.relayPending.get(relay) || 0
  requestQueue.relayPending.set(relay, Math.max(0, relayPending - 1))

  // Wake up next waiting request
  if (requestQueue.queue.length > 0) {
    const next = requestQueue.queue.shift()
    next()
  }
}


function normalizeRelayUrl(url) {
  try {
    const u = new URL(String(url).trim())
    u.protocol = u.protocol.toLowerCase()
    u.hostname = u.hostname.toLowerCase()
    if (u.pathname === '/') u.pathname = ''
    return u.toString().replace(/\/$/, '')
  } catch (_) {
    return String(url || '').trim().replace(/\/$/, '')
  }
}

function normalizeRelayList(relays = []) {
  const seen = new Set()
  return relays.map(normalizeRelayUrl).filter(url => {
    if (!url || seen.has(url) || disabledRelays.has(url) || isRelayInCooldown(url)) return false
    seen.add(url)
    return true
  })
}

export function getRxNostr() {
  if (!rxNostr) {
    rxNostr = createRxNostr({
      verifier: noopVerifier,
      connectionStrategy: 'lazy-keep',
      retry: { strategy: 'exponential', maxCount: 2, initialDelay: 500, polite: true },
      disconnectTimeout: 15000,
      eoseTimeout: Math.min(WS_CONFIG.eoseTimeout || 8000, 3500),
      okTimeout: Math.min(WS_CONFIG.requestTimeout || 8000, 3000),
      skipFetchNip11: true,
      skipValidateFilterMatching: true,
    })
    rxNostr.createConnectionStateObservable().subscribe(packet => {
      if (packet?.state === 'connected') connectionState = CONNECTION_STATE.CONNECTED
    })
    rxNostr.createAllErrorObservable().subscribe(packet => {
      if (packet?.from) recordRelayFailure(packet.from, packet.reason || new Error('rx-nostr error'))
    })
  }
  return rxNostr
}

export async function fetchEventsRxManaged(filter, relays, options = {}) {
  const { timeoutMs = 3000, limit = filter?.limit || 50, dedupe = true } = options
  const targetRelays = normalizeRelayList(relays)
  if (targetRelays.length === 0) return []

  const executeFn = async () => new Promise((resolve) => {
    const rx = getRxNostr()
    rx.setDefaultRelays(targetRelays.map(url => ({ url, read: true, write: false })))
    const req = createRxOneshotReq({ filters: filter })
    const seen = new Set()
    const events = []
    let settled = false
    let sub = null

    const finish = () => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      try { sub?.unsubscribe() } catch (_) {}
      events.sort((a, b) => b.created_at - a.created_at)
      resolve(events.slice(0, limit))
    }

    const timer = setTimeout(finish, timeoutMs)
    sub = rx.use(req).subscribe({
      next(packet) {
        if (packet?.type !== 'EVENT' || !packet.event) return
        const ev = packet.event
        if (seen.has(ev.id)) return
        seen.add(ev.id)
        events.push(ev)
        // First-paint optimization: if enough events are available, return
        // immediately instead of waiting for every relay's EOSE.
        if (events.length >= limit) finish()
      },
      error() { finish() },
      complete() { finish() },
    })
  })

  if (!dedupe) return executeFn()
  return deduplicateRequest(generateRequestKey(filter, targetRelays) + ':rx', executeFn)
}

export function subscribeRxManaged(filter, relays, callbacks = {}, options = {}) {
  const targetRelays = normalizeRelayList(relays)
  const rx = getRxNostr()
  rx.setDefaultRelays(targetRelays.map(url => ({ url, read: true, write: false })))
  const req = createRxForwardReq(options.rxReqId)
  const sub = rx.use(req).subscribe(packet => {
    if (packet?.type === 'EVENT') callbacks.onEvent?.(packet.event)
    if (packet?.type === 'EOSE') callbacks.onEose?.()
  })
  req.emit(filter)
  return { close: () => sub.unsubscribe(), isActive: () => !sub.closed, getStats: () => ({ isConnected: !sub.closed }) }
}

// ============================================
// Pool Management
// ============================================

/**
 * Get or create the pool singleton
 */
export function getPool() {
  if (!pool || isClosing) {
    pool = new SimplePool({
      // Disable noisy WebSocket error logging in production
      verifyEvent: () => true,
      eoseSubTimeout: WS_CONFIG.eoseTimeout,
      getTimeout: WS_CONFIG.requestTimeout,
    })
    isClosing = false
    connectionState = CONNECTION_STATE.CONNECTING
    startHealthCheck()
  }
  poolLastUsed = Date.now()
  return pool
}

/**
 * Get current connection state
 */
export function getConnectionState() {
  return connectionState
}

/**
 * Reset the connection pool
 */
export async function resetPool() {
  if (pool) {
    isClosing = true
    connectionState = CONNECTION_STATE.RECONNECTING
    try {
      pool.close([])
    } catch (e) {
      // Silently ignore pool close errors
    }
    pool = null
  }
  if (rxNostr) {
    try { rxNostr.dispose() } catch (_) {}
    rxNostr = null
  }

  // Clear pending requests
  requestQueue.pending = 0
  requestQueue.queue.forEach(resolve => resolve())
  requestQueue.queue = []
  requestQueue.relayPending.clear()

  // Reset rate limiters
  rateLimiters.clear()

  // Clear deduplication caches
  pendingRequests.clear()
  completedResults.clear()

  // Create new pool
  isClosing = false
  return getPool()
}

/**
 * Start health check timer
 */
function startHealthCheck() {
  if (healthCheckTimer) {
    clearInterval(healthCheckTimer)
  }

  if (typeof window === 'undefined') return

  healthCheckTimer = setInterval(() => {
    // Reset pool if idle for too long
    if (pool && Date.now() - poolLastUsed > WS_CONFIG.poolIdleTimeout) {
      if (process.env.NODE_ENV === 'development') {
        console.log('[ConnectionManager] Auto-resetting idle pool')
      }
      resetPool()
    }

    // Clean up expired failure records
    const now = Date.now()
    for (const [relay, info] of failedRelays.entries()) {
      if (now - info.lastFailure > WS_CONFIG.failedRelayCooldown) {
        failedRelays.delete(relay)
      }
    }

    // Clean up stale pending requests
    for (const [key, req] of pendingRequests.entries()) {
      if (now - req.timestamp > DEDUP_CONFIG.pendingRequestTTL) {
        pendingRequests.delete(key)
      }
    }

    // Clean up old completed results
    for (const [key, result] of completedResults.entries()) {
      if (now - result.timestamp > DEDUP_CONFIG.completedResultTTL) {
        completedResults.delete(key)
      }
    }
  }, WS_CONFIG.healthCheckInterval)
}

// ============================================
// Core Request Execution
// ============================================

/**
 * Execute a query with retry logic
 */
export async function executeWithRetry(queryFn, relays, options = {}) {
  const {
    maxAttempts = WS_CONFIG.retry.maxAttempts,
    signal,
    silent = false,
  } = options

  const availableRelays = filterAvailableRelays(relays)
  let lastError = null
  let currentRelayIndex = 0

  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    if (signal?.aborted) {
      throw new DOMException('Request cancelled', 'AbortError')
    }

    const relay = availableRelays[currentRelayIndex % availableRelays.length]

    if (isRelayInCooldown(relay)) {
      currentRelayIndex++
      continue
    }

    try {
      await acquireSlot(relay)

      try {
        const result = await Promise.race([
          queryFn([relay]),
          new Promise((_, reject) => {
            const timeoutId = setTimeout(
              () => reject(new Error('Request timeout')),
              WS_CONFIG.requestTimeout
            )

            signal?.addEventListener('abort', () => {
              clearTimeout(timeoutId)
              reject(new DOMException('Request cancelled', 'AbortError'))
            })
          })
        ])

        recordRelaySuccess(relay)
        return result
      } finally {
        releaseSlot(relay)
      }
    } catch (e) {
      lastError = e
      recordRelayFailure(relay, e)

      if (e.name === 'AbortError') {
        throw e
      }

      if (!silent && process.env.NODE_ENV === 'development') {
        console.warn(
          `[ConnectionManager] Request failed on ${relay} (attempt ${attempt + 1}/${maxAttempts}):`,
          e.message
        )
      }

      currentRelayIndex++

      if (attempt < maxAttempts - 1) {
        const delay = calculateBackoffDelay(attempt)

        if (!silent && process.env.NODE_ENV === 'development') {
          console.log(`[ConnectionManager] Retrying in ${Math.round(delay)}ms...`)
        }

        await new Promise(resolve => setTimeout(resolve, delay))

        if (attempt >= 1) {
          await resetPool()
        }
      }
    }
  }

  throw lastError || new Error('All retry attempts exhausted')
}

// ============================================
// Managed Operations
// ============================================

/**
 * Fetch events with automatic retry, throttling, and deduplication
 */
export async function fetchEventsManaged(filter, relays, options = {}) {
  const { dedupe = true, preferRx = true, fast = false, ...restOptions } = options
  return measureAsync('nostr.fetchEventsManaged', async () => {
    const normalizedRelays = normalizeRelayList(relays)
    if (preferRx || fast) {
      try {
        return await fetchEventsRxManaged(filter, normalizedRelays, {
          dedupe,
          limit: filter?.limit || options.limit || 50,
          timeoutMs: fast ? 2500 : Math.min(WS_CONFIG.requestTimeout || 8000, 4500),
        })
      } catch (e) {
        if (process.env.NODE_ENV === 'development') console.warn('[ConnectionManager] rx-nostr fetch failed, falling back:', e?.message || e)
      }
    }
    const p = getPool()
    const executeFn = async () => {
      return executeWithRetry(
        async (currentRelays) => {
          const events = await p.querySync(currentRelays, filter)
          return events.sort((a, b) => b.created_at - a.created_at)
        },
        normalizedRelays,
        restOptions
      )
    }
    if (dedupe) {
      const key = generateRequestKey(filter, normalizedRelays)
      return deduplicateRequest(key, executeFn)
    }
    return executeFn()
  }, {
    relayCount: Array.isArray(relays) ? relays.length : 0,
    kindCount: Array.isArray(filter?.kinds) ? filter.kinds.length : 0,
    hasAuthors: Array.isArray(filter?.authors) && filter.authors.length > 0,
    hasTags: !!filter && Object.keys(filter).some(k => k.startsWith('#')),
    fast,
    preferRx,
  })
}

// ============================================
// Resilient Subscription Manager
// ============================================

/**
 * Create a resilient subscription with auto-reconnect
 */
export function subscribeManaged(filter, relays, callbacks, options = {}) {
  const {
    onEvent,
    onEose,
    onError,
    onReconnect,
  } = callbacks

  const {
    autoReconnect = true,
    maxReconnectAttempts = WS_CONFIG.subscription.maxReconnectAttempts,
  } = options

  let isActive = true
  let sub = null
  let reconnectAttempts = 0
  let reconnectDelay = WS_CONFIG.subscription.reconnectDelay
  let reconnectTimer = null
  let heartbeatTimer = null
  let lastEventTime = Date.now()

  const filters = Array.isArray(filter) ? filter : [filter]
  const availableRelays = filterAvailableRelays(relays)

  // Cleanup function
  const cleanup = () => {
    isActive = false
    if (reconnectTimer) {
      clearTimeout(reconnectTimer)
      reconnectTimer = null
    }
    if (heartbeatTimer) {
      clearInterval(heartbeatTimer)
      heartbeatTimer = null
    }
    if (sub) {
      try {
        sub.close()
      } catch (e) {
        // Ignore
      }
      sub = null
    }
  }

  // Reconnect function
  const reconnect = () => {
    if (!isActive || !autoReconnect) return
    if (reconnectAttempts >= maxReconnectAttempts) {
      console.warn('[ConnectionManager] Max reconnect attempts reached for subscription')
      if (onError) onError(new Error('Max reconnect attempts reached'))
      return
    }

    reconnectAttempts++
    reconnectDelay = Math.min(
      reconnectDelay * WS_CONFIG.subscription.reconnectBackoffMultiplier,
      WS_CONFIG.subscription.maxReconnectDelay
    )

    if (process.env.NODE_ENV === 'development') {
      console.log(`[ConnectionManager] Reconnecting subscription (attempt ${reconnectAttempts})...`)
    }

    reconnectTimer = setTimeout(() => {
      if (isActive) {
        createSubscription()
        if (onReconnect) onReconnect(reconnectAttempts)
      }
    }, reconnectDelay)
  }

  // Create subscription
  const createSubscription = () => {
    try {
      const p = getPool()
      sub = p.subscribeMany(availableRelays, filters, {
        onevent: (event) => {
          if (isActive && onEvent) {
            lastEventTime = Date.now()
            reconnectAttempts = 0 // Reset on successful event
            reconnectDelay = WS_CONFIG.subscription.reconnectDelay
            connectionState = CONNECTION_STATE.CONNECTED
            onEvent(event)
          }
        },
        oneose: () => {
          if (isActive && onEose) {
            connectionState = CONNECTION_STATE.CONNECTED
            onEose()
          }
        },
        onclose: (reason) => {
          if (isActive) {
            // Only log in development mode
            if (process.env.NODE_ENV === 'development') {
              console.warn('[ConnectionManager] Subscription closed:', reason)
            }
            sub = null
            reconnect()
          }
        }
      })

      // Start heartbeat monitoring
      if (heartbeatTimer) clearInterval(heartbeatTimer)
      heartbeatTimer = setInterval(() => {
        if (!isActive) return

        const timeSinceLastEvent = Date.now() - lastEventTime
        // If no events for 2x heartbeat interval, consider connection stale
        if (timeSinceLastEvent > WS_CONFIG.subscription.heartbeatInterval * 2) {
          if (process.env.NODE_ENV === 'development') {
            console.warn('[ConnectionManager] Subscription appears stale, reconnecting...')
          }
          if (sub) {
            try {
              sub.close()
            } catch (e) {
              // Ignore
            }
            sub = null
          }
          reconnect()
        }
      }, WS_CONFIG.subscription.heartbeatInterval)

    } catch (e) {
      if (onError) onError(e)
      reconnect()
    }
  }

  // Initial subscription
  createSubscription()

  // Return subscription handle with cleanup
  return {
    close: cleanup,
    isActive: () => isActive,
    getStats: () => ({
      reconnectAttempts,
      lastEventTime,
      isConnected: sub !== null,
    })
  }
}

/**
 * Publish event with structured delivery information.
 * Stores fully-signed events in the local durable outbox before network send.
 */
export async function publishManagedResult(event, relays, options = {}) {
  const p = getPool()
  const availableRelays = filterAvailableRelays(relays)
  const startedAt = Date.now()
  const eventId = event?.id || ''

  // Enqueue before relay availability checks so a signed event survives
  // offline/cooldown states as well as publish ACK failures. The Web outbox
  // stores signed event JSON only; no private keys or unsigned signing material.
  if (options.enqueueOutbox !== false) {
    enqueuePublishOutbox(event, availableRelays.length > 0 ? availableRelays : relays)
  }

  if (availableRelays.length === 0) {
    if (eventId) markPublishOutboxFailed(eventId, '利用可能なリレーがありません')
    return { eventId, ok: false, okRelays: [], failedRelays: [], firstOkMs: 0, retryQueued: true, error: '利用可能なリレーがありません' }
  }

  const settled = await Promise.allSettled(availableRelays.map(async relay => {
    const pub = p.publish([relay], event)
    const promise = pub?.[0]
    if (!promise) throw new Error(`リレー ${relay} への送信に失敗しました`)
    await Promise.race([
      promise,
      new Promise((_, reject) => setTimeout(() => reject(new Error('Publish timeout')), options.timeoutMs || 8000))
    ])
    return relay
  }))

  const okRelays = []
  const failedRelays = []
  const errors = []
  settled.forEach((result, index) => {
    const relay = availableRelays[index]
    if (result.status === 'fulfilled') {
      okRelays.push(relay)
      recordRelaySuccess(relay)
    } else {
      failedRelays.push(relay)
      errors.push(`${relay}: ${result.reason?.message || '接続失敗'}`)
      recordRelayFailure(relay, result.reason)
    }
  })

  const ok = okRelays.length > 0
  if (ok) markPublishOutboxPublished(eventId)
  else markPublishOutboxFailed(eventId, errors.join(', ') || 'publish failed')

  return {
    eventId,
    ok,
    okRelays,
    failedRelays,
    firstOkMs: ok ? Date.now() - startedAt : 0,
    retryQueued: !ok,
    error: ok ? '' : (errors.join(', ') || 'publish failed'),
  }
}

/**
 * Publish event with retry and improved error handling.
 * Legacy wrapper: throws when no relay accepted the event.
 */
export async function publishManaged(event, relays, options = {}) {
  const result = await publishManagedResult(event, relays, options)
  if (!result.ok) throw new Error(result.error || 'すべてのリレーへの送信に失敗')
  return { relay: result.okRelays[0], success: true, result }
}

/**
 * Batch fetch with controlled concurrency and deduplication
 */
export async function batchFetchManaged(queries, relays, options = {}) {
  const { concurrency = 3 } = options
  const results = []
  const p = getPool()

  for (let i = 0; i < queries.length; i += concurrency) {
    const batch = queries.slice(i, i + concurrency)

    const batchResults = await Promise.allSettled(
      batch.map(query => {
        const key = generateRequestKey(query, relays)
        return deduplicateRequest(key, () =>
          executeWithRetry(
            async (currentRelays) => p.querySync(currentRelays, query),
            relays,
            options
          )
        )
      })
    )

    results.push(...batchResults)
  }

  return results
}

// ============================================
// Statistics & Debugging
// ============================================

/**
 * Get connection statistics
 */
export function getConnectionStats() {
  return {
    state: connectionState,
    pending: requestQueue.pending,
    queueLength: requestQueue.queue.length,
    relayPending: Object.fromEntries(requestQueue.relayPending),
    rateLimiters: rateLimiters.size,
    failedRelays: Object.fromEntries(failedRelays),
    disabledRelays: Array.from(disabledRelays),
    poolActive: pool !== null && !isClosing,
    lastUsed: poolLastUsed,
    idleTime: Date.now() - poolLastUsed,
    pendingRequests: pendingRequests.size,
    cachedResults: completedResults.size,
  }
}

/**
 * Get relay health info
 */
export function getRelayHealth(relay) {
  if (disabledRelays.has(relay)) {
    return { status: 'disabled', reason: 'SSL/TLS error' }
  }

  const failureInfo = failedRelays.get(relay)
  if (!failureInfo) {
    return { status: 'healthy', failures: 0 }
  }

  const inCooldown = failureInfo.failures >= WS_CONFIG.maxFailuresBeforeCooldown
  const cooldownRemaining = inCooldown
    ? Math.max(0, WS_CONFIG.failedRelayCooldown - (Date.now() - failureInfo.lastFailure))
    : 0

  return {
    status: inCooldown ? 'cooldown' : 'degraded',
    failures: failureInfo.failures,
    lastFailure: failureInfo.lastFailure,
    cooldownRemaining,
  }
}

// ============================================
// Cleanup
// ============================================

/**
 * Cleanup - call when app is unmounting
 */
export function cleanup() {
  if (healthCheckTimer) {
    clearInterval(healthCheckTimer)
    healthCheckTimer = null
  }

  if (pool) {
    try {
      pool.close([])
    } catch (e) {
      // Ignore
    }
    pool = null
  }

  connectionState = CONNECTION_STATE.DISCONNECTED

  // Clear all state
  requestQueue.pending = 0
  requestQueue.queue = []
  requestQueue.relayPending.clear()
  rateLimiters.clear()
  failedRelays.clear()
  pendingRequests.clear()
  completedResults.clear()
}

// Export config for testing/debugging
export { WS_CONFIG as CONNECTION_CONFIG }
