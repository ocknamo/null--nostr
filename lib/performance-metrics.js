/**
 * Lightweight local performance metrics for null--nostr.
 *
 * Scope:
 * - local/in-memory only; no network upload
 * - sanitized labels only (counts/booleans/small enums, no pubkeys/event IDs/URLs)
 * - safe to import from browser or SSR code
 */

const MAX_METRICS = 300
const metrics = []
const subscribers = new Set()

function nowMs() {
  if (typeof performance !== 'undefined' && performance.now) return performance.now()
  return Date.now()
}

function sanitizeLabels(labels = {}) {
  const out = {}
  for (const [key, value] of Object.entries(labels || {})) {
    if (value == null) continue
    if (typeof value === 'boolean' || typeof value === 'number') {
      out[key] = value
    } else if (typeof value === 'string') {
      // Only keep low-cardinality labels. Do not pass URLs, pubkeys, event IDs, etc.
      out[key] = value.length <= 32 ? value : value.slice(0, 32)
    }
  }
  return out
}

export function recordMetric(name, valueMs, labels = {}) {
  if (!name) return null
  const entry = {
    name,
    valueMs: Math.round(Number(valueMs) || 0),
    labels: sanitizeLabels(labels),
    timestamp: Date.now(),
  }
  metrics.push(entry)
  if (metrics.length > MAX_METRICS) metrics.splice(0, metrics.length - MAX_METRICS)
  for (const cb of subscribers) {
    try { cb(entry) } catch {}
  }
  if (typeof window !== 'undefined' && process.env.NODE_ENV === 'development') {
    window.__NURU_PERF__ = { getMetrics: getPerformanceMetrics, clear: clearPerformanceMetrics }
  }
  return entry
}

export async function measureAsync(name, fn, labels = {}) {
  const start = nowMs()
  try {
    const result = await fn()
    const count = Array.isArray(result) ? result.length : undefined
    recordMetric(name, nowMs() - start, { ...labels, ok: true, ...(count !== undefined ? { count } : {}) })
    return result
  } catch (error) {
    recordMetric(name, nowMs() - start, { ...labels, ok: false })
    throw error
  }
}

export function getPerformanceMetrics() {
  return metrics.slice()
}

export function clearPerformanceMetrics() {
  metrics.length = 0
}

export function subscribePerformanceMetrics(callback) {
  subscribers.add(callback)
  return () => subscribers.delete(callback)
}
