/**
 * Web durable publish outbox.
 *
 * Stores fully-signed event JSON only. No private keys, unsigned events, or
 * signing material are stored here. The data remains local in the browser.
 */

const OUTBOX_KEY = 'nurunuru_publish_outbox_v1'
const MAX_ITEMS = 100

function nowMs() { return Date.now() }

function readItems() {
  if (typeof window === 'undefined') return []
  try {
    const raw = localStorage.getItem(OUTBOX_KEY)
    const parsed = raw ? JSON.parse(raw) : []
    return Array.isArray(parsed) ? parsed : []
  } catch {
    return []
  }
}

function writeItems(items) {
  if (typeof window === 'undefined') return
  try {
    localStorage.setItem(OUTBOX_KEY, JSON.stringify(items.slice(-MAX_ITEMS)))
  } catch {}
}

export function enqueuePublishOutbox(event, relayUrls = []) {
  if (!event?.id || !event?.sig) return null
  const items = readItems()
  const idx = items.findIndex(item => item.eventId === event.id)
  const ts = nowMs()
  const item = {
    eventId: event.id,
    eventJson: JSON.stringify(event),
    relayUrls: Array.isArray(relayUrls) ? relayUrls : [],
    createdAtMs: idx >= 0 ? items[idx].createdAtMs : ts,
    updatedAtMs: ts,
    attempts: idx >= 0 ? items[idx].attempts || 0 : 0,
    state: idx >= 0 && items[idx].state === 'published' ? 'published' : 'pending',
    lastError: '',
  }
  if (idx >= 0) items[idx] = item
  else items.push(item)
  writeItems(items)
  return item
}

export function markPublishOutboxPublished(eventId) {
  const items = readItems()
  const item = items.find(it => it.eventId === eventId)
  if (item) {
    item.state = 'published'
    item.updatedAtMs = nowMs()
    item.lastError = ''
    writeItems(items)
  }
}

export function markPublishOutboxFailed(eventId, error = 'publish failed') {
  const items = readItems()
  const item = items.find(it => it.eventId === eventId)
  if (item) {
    item.state = 'failed'
    item.updatedAtMs = nowMs()
    item.attempts = (item.attempts || 0) + 1
    item.lastError = String(error || 'publish failed').slice(0, 512)
    writeItems(items)
  }
}

export function getPendingPublishOutbox(limit = 50) {
  return readItems()
    .filter(item => item.state !== 'published')
    .sort((a, b) => (a.createdAtMs || 0) - (b.createdAtMs || 0))
    .slice(0, limit)
}

export function getPublishOutboxStats() {
  const items = readItems()
  return {
    total: items.length,
    pending: items.filter(item => item.state === 'pending').length,
    failed: items.filter(item => item.state === 'failed').length,
    published: items.filter(item => item.state === 'published').length,
  }
}

export function clearPublishedPublishOutbox() {
  const items = readItems().filter(item => item.state !== 'published')
  writeItems(items)
}
