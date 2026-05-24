const RELAYS = [
  'wss://yabu.me',
  'wss://relay-jp.nostr.wirednet.jp',
  'wss://r.kojira.io',
  'wss://relay.damus.io',
  'wss://search.nos.today',
]

function isHex64(value) {
  return typeof value === 'string' && /^[0-9a-fA-F]{64}$/.test(value)
}

function withTimeout(promise, ms) {
  return new Promise((resolve) => {
    const timer = setTimeout(() => resolve(null), ms)
    promise.then(
      (value) => { clearTimeout(timer); resolve(value) },
      () => { clearTimeout(timer); resolve(null) },
    )
  })
}

async function fetchOne(filter, timeoutMs = 2800) {
  if (typeof WebSocket === 'undefined') return null
  const subId = `nuru-${Math.random().toString(36).slice(2)}`
  const query = JSON.stringify(['REQ', subId, filter])

  const attempts = RELAYS.map((relay) => withTimeout(new Promise((resolve) => {
    let settled = false
    let ws
    const finish = (value) => {
      if (settled) return
      settled = true
      try { ws?.send(JSON.stringify(['CLOSE', subId])) } catch (_) {}
      try { ws?.close() } catch (_) {}
      resolve(value)
    }
    try {
      ws = new WebSocket(relay)
      ws.onopen = () => ws.send(query)
      ws.onmessage = (message) => {
        try {
          const data = JSON.parse(typeof message.data === 'string' ? message.data : '')
          if (data?.[0] === 'EVENT' && data?.[1] === subId && data?.[2]?.id) finish(data[2])
          if (data?.[0] === 'EOSE' && data?.[1] === subId) finish(null)
        } catch (_) {}
      }
      ws.onerror = () => finish(null)
      ws.onclose = () => finish(null)
    } catch (_) {
      finish(null)
    }
  }), timeoutMs))

  const results = await Promise.all(attempts)
  return results.find(Boolean) || null
}

export function cleanPostContent(content, maxLength = 180) {
  const cleaned = String(content || '')
    .replace(/https?:\/\/\S+\.(?:jpg|jpeg|png|gif|webp|avif|mp4|mov|webm|m3u8)(\?\S*)?/gi, '')
    .replace(/(?:nostr:)?(?:note1|nevent1|naddr1)[a-z0-9]+/gi, '')
    .replace(/\s+/g, ' ')
    .trim()
  if (!cleaned) return 'メディア投稿'
  return cleaned.length > maxLength ? `${cleaned.slice(0, maxLength - 1)}…` : cleaned
}

function parseProfile(event) {
  if (!event?.content) return null
  try {
    const profile = JSON.parse(event.content)
    return {
      name: profile.display_name || profile.name || '',
      picture: profile.picture || '',
    }
  } catch (_) {
    return null
  }
}

export async function getEventPreview(eventId) {
  if (!isHex64(eventId)) return null
  const event = await fetchOne({ ids: [eventId.toLowerCase()], limit: 1 })
  if (!event) return null
  const profileEvent = event.pubkey
    ? await fetchOne({ kinds: [0], authors: [event.pubkey], limit: 1 }, 2200)
    : null
  const profile = parseProfile(profileEvent)
  const authorName = profile?.name || (event.pubkey ? `${event.pubkey.slice(0, 8)}…${event.pubkey.slice(-4)}` : 'ぬるぬる')
  const content = cleanPostContent(event.content)
  return { event, profile, authorName, content }
}
