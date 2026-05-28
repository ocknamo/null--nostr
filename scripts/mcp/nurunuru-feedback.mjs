const DEFAULT_SEARCH_RELAYS = ['wss://search.nos.today']
const DEFAULT_FEEDBACK_QUERIES = [
  'ぬるぬる',
  '#ぬるぬるはじめました',
  'nullnull Android',
  'nullnull iOS',
  'nullnull',
  'via nullnull Android',
  'via nullnull iOS',
  'via nullnull',
]
const DEFAULT_KINDS = [1]
const MAX_LIMIT = 100
const DEFAULT_TIMEOUT_MS = 5000

const KEYWORDS = {
  p0: ['秘密鍵', 'private key', 'nsec', 'ログインできない', 'login failed', '起動しない', 'クラッシュ', 'crash'],
  p1: ['投稿できない', '送信できない', '保存できない', '画像投稿できない', '通知こない', '通知がこない', '落ちる', '固まる', 'フリーズ', 'freeze', 'broken'],
  bug: ['バグ', '不具合', 'エラー', '失敗', 'できない', '動かない', '表示されない', '消える', '壊れ', '落ちる', 'クラッシュ', 'crash', 'bug', 'error', 'failed', 'fail'],
  feature: ['ほしい', '欲しい', 'できるように', '追加して', '要望', 'feature request', 'request', 'would like'],
  design: ['見づらい', '読みにくい', '押しにくい', 'わかりにくい', 'ダサい', 'デザイン', 'ui', 'ux', 'layout'],
  copy: ['文言', 'コピー', '表記', '誤字', 'typo', 'wording'],
  performance: ['重い', '遅い', 'カクつく', 'ロード長い', 'performance', 'slow', 'lag'],
  praise: ['ありがとう', '便利', '最高', '好き', '良い', 'よい', 'love', 'thanks', 'great'],
}

const PLATFORM_KEYWORDS = [
  ['android', ['nullnull android', 'via nullnull android', 'android', 'アンドロイド', 'pixel', 'galaxy', 'apk']],
  ['ios', ['nullnull ios', 'via nullnull ios', 'ios', 'iphone', 'ipad', 'testflight', 'app store']],
  ['web', ['web', 'pwa', 'ブラウザ', 'safari', 'chrome']],
]

const FEATURE_AREAS = [
  ['signing', ['署名', 'signing', 'signer', 'sign', 'external signer', '外部署名', 'nip-46', 'nip46', 'amber', 'nosskey']],
  ['auth', ['ログイン', 'login', 'signup', '新規登録', 'アカウント']],
  ['post_content', ['url', 'リンク', 'link', 'ogp', 'preview', 'プレビュー', 'カード', 'クリック', 'click', 'tap', 'タップ', '開けない', '飛べる', '飛べない']],
  ['timeline', ['タイムライン', 'timeline', 'フィード', 'feed', 'おすすめ', 'フォロー', '更新できない']],
  ['post_composer', ['投稿', 'post', 'composer', '140', '下書き', '送信']],
  ['image_upload', ['画像', '写真', 'image', 'upload', 'アップロード', 'blossom', 'nostr.build']],
  ['notification', ['通知', 'notification', 'mention', 'メンション']],
  ['relay', ['リレー', 'relay', '接続', 'websocket', 'search.nos.today']],
  ['talk', ['トーク', 'dm', 'メッセージ', 'mls', 'talk']],
  ['video', ['動画', 'ろくなな', 'video', '67']],
  ['zap', ['zap', 'ザップ', 'lightning', 'lnurl']],
  ['design', ['デザイン', 'ui', 'ux', '見た目', 'コピー']],
]

const VAGUE_BUG_WORDS = ['壊れている', '壊れた', 'broken', '動かない', '変', 'おかしい', 'だめ', 'ダメ']

function asArray(value) {
  if (value == null) return []
  return Array.isArray(value) ? value : [value]
}

function unique(values) {
  return [...new Set(values.filter(Boolean))]
}

function normalizeLimit(limit, fallback = 20) {
  const n = Number(limit ?? fallback)
  if (!Number.isFinite(n) || n <= 0) return fallback
  return Math.min(Math.floor(n), MAX_LIMIT)
}

function normalizeRelayUrl(url) {
  if (typeof url !== 'string') return null
  const trimmed = url.trim()
  if (!trimmed) return null
  try {
    const parsed = new URL(trimmed)
    if (parsed.protocol !== 'wss:' && parsed.protocol !== 'ws:') return null
    return parsed.toString().replace(/\/$/, '')
  } catch {
    return null
  }
}

function includesAny(text, words) {
  const lower = String(text ?? '').toLowerCase()
  return words.some((word) => lower.includes(String(word).toLowerCase()))
}

function matchedWords(text, words) {
  const lower = String(text ?? '').toLowerCase()
  return words.filter((word) => lower.includes(String(word).toLowerCase()))
}

function extractEventTags(event) {
  return Array.isArray(event?.tags) ? event.tags.filter((tag) => Array.isArray(tag)) : []
}

function tagValues(event, names) {
  const wanted = new Set(asArray(names).map((name) => String(name).toLowerCase()))
  return extractEventTags(event)
    .filter((tag) => wanted.has(String(tag[0] ?? '').toLowerCase()))
    .flatMap((tag) => tag.slice(1).map(String))
    .filter(Boolean)
}

function parseJsonStrings(value) {
  const parsed = []
  if (typeof value !== 'string') return parsed
  try {
    parsed.push(JSON.parse(value))
  } catch {}
  return parsed
}

function collectJsonStringValues(value, keys = ['via', 'client']) {
  const values = []
  if (!value || typeof value !== 'object') return values
  if (Array.isArray(value)) {
    for (const item of value) values.push(...collectJsonStringValues(item, keys))
    return values
  }
  for (const [key, child] of Object.entries(value)) {
    if (keys.includes(String(key).toLowerCase())) {
      if (typeof child === 'string') values.push(child)
      else if (Array.isArray(child)) values.push(...child.map(String))
      else if (child && typeof child === 'object') values.push(JSON.stringify(child))
    }
    if (child && typeof child === 'object') values.push(...collectJsonStringValues(child, keys))
  }
  return values
}

function eventMetadataText(event) {
  if (!event || typeof event !== 'object') return ''
  const tagText = tagValues(event, ['client', 'via', 'app']).join(' ')
  const jsonValues = [event.content, event.text, event.summary]
    .flatMap(parseJsonStrings)
    .flatMap((json) => collectJsonStringValues(json, ['via', 'client', 'app']))
    .join(' ')
  return [tagText, jsonValues].filter(Boolean).join(' ')
}

function isVagueFeedback(source, classification) {
  const compact = String(source ?? '').replace(/\s+/g, '')
  if (classification.featureArea !== 'unknown') return false
  if (compact.length > 40) return false
  return includesAny(source, VAGUE_BUG_WORDS)
}

export function buildNip50Filter(input = {}) {
  const query = String(input.query ?? '').trim()
  if (!query) throw new Error('query is required')

  const filter = {
    search: query,
    kinds: asArray(input.kinds).length ? asArray(input.kinds).map(Number).filter(Number.isFinite) : DEFAULT_KINDS,
    limit: normalizeLimit(input.limit),
  }

  if (input.since != null) filter.since = Math.floor(Number(input.since))
  if (input.until != null) filter.until = Math.floor(Number(input.until))
  if (asArray(input.authors).length) filter.authors = unique(asArray(input.authors).map(String))

  const tags = input.tags && typeof input.tags === 'object' ? input.tags : {}
  for (const [tagName, values] of Object.entries(tags)) {
    const cleanName = tagName.startsWith('#') ? tagName : '#' + tagName
    const cleanValues = unique(asArray(values).map(String).map((v) => v.trim()).filter(Boolean))
    if (cleanValues.length) filter[cleanName] = cleanValues
  }

  return filter
}

export function eventToFeedbackText(event) {
  if (!event) return ''
  if (typeof event === 'string') return event
  return String(event.content ?? event.text ?? event.summary ?? '')
}

export function classifyFeedbackText(text, options = {}) {
  const source = String(text ?? '')
  const signals = []
  const labels = []

  let type = 'other'
  if (includesAny(source, KEYWORDS.bug)) type = 'bug'
  else if (includesAny(source, KEYWORDS.performance)) type = 'performance'
  else if (includesAny(source, KEYWORDS.design)) type = 'design'
  else if (includesAny(source, KEYWORDS.copy)) type = 'copy'
  else if (includesAny(source, KEYWORDS.feature)) type = 'feature'
  else if (includesAny(source, KEYWORDS.praise)) type = 'praise'

  if (includesAny(source, KEYWORDS.copy)) type = 'copy'
  if (includesAny(source, KEYWORDS.design)) type = type === 'bug' ? 'bug' : 'design'
  if (includesAny(source, KEYWORDS.performance)) type = type === 'bug' ? 'bug' : 'performance'

  const p0Matches = matchedWords(source, KEYWORDS.p0)
  const p1Matches = matchedWords(source, KEYWORDS.p1)
  const bugMatches = matchedWords(source, KEYWORDS.bug)
  const featureMatches = matchedWords(source, KEYWORDS.feature)
  const designMatches = matchedWords(source, KEYWORDS.design)
  const performanceMatches = matchedWords(source, KEYWORDS.performance)

  signals.push(...p0Matches, ...p1Matches, ...bugMatches, ...featureMatches, ...designMatches, ...performanceMatches)

  let severity = 'p3'
  if (p0Matches.length) severity = 'p0'
  else if (p1Matches.length || (type === 'bug' && bugMatches.length >= 2)) severity = 'p1'
  else if (type === 'bug' || type === 'performance') severity = 'p2'

  let platform = options.defaultPlatform ?? 'unknown'
  for (const [candidate, words] of PLATFORM_KEYWORDS) {
    if (includesAny(source, words)) {
      platform = candidate
      break
    }
  }

  let featureArea = 'unknown'
  for (const [candidate, words] of FEATURE_AREAS) {
    if (includesAny(source, words)) {
      featureArea = candidate
      break
    }
  }

  if (type !== 'other') labels.push('type:' + type)
  if (platform !== 'unknown') labels.push('platform:' + platform)
  if (severity) labels.push('severity:' + severity)
  if (featureArea !== 'unknown') labels.push('area:' + featureArea)

  const preliminary = { type, severity, platform, featureArea }
  if (isVagueFeedback(source, preliminary)) labels.push('needs:thread-context')

  const confidence = Math.min(1, 0.2 + signals.length * 0.15 + (type !== 'other' ? 0.2 : 0) + (platform !== 'unknown' ? 0.05 : 0) + (featureArea !== 'unknown' ? 0.05 : 0))
  return {
    type,
    severity,
    platform,
    featureArea,
    confidence: Number(confidence.toFixed(2)),
    labels: unique(labels),
    signals: unique(signals).slice(0, 12),
  }
}

export function classifyFeedbackEvent(event, options = {}) {
  const text = eventToFeedbackText(event)
  const metadata = eventMetadataText(event)
  const classification = classifyFeedbackText([text, metadata].filter(Boolean).join(' '), options)
  return { event, text, classification }
}

export function makeFeedbackKey(item) {
  const classification = item.classification ?? classifyFeedbackText(item.text ?? eventToFeedbackText(item.event))
  const base = [classification.platform, classification.featureArea, classification.type].join('|')
  if (classification.featureArea !== 'unknown' && !classification.labels?.includes('needs:thread-context')) return base
  const eventId = item.event?.id ? String(item.event.id).slice(0, 12) : ''
  const textKey = String(item.text ?? eventToFeedbackText(item.event) ?? '').replace(/\s+/g, ' ').slice(0, 48)
  return [base, eventId || textKey || 'unknown'].join('|')
}

export function groupFeedbackItems(items = []) {
  const groups = new Map()
  for (const item of items) {
    const normalized = item.classification ? item : classifyFeedbackEvent(item.event ?? item)
    const key = makeFeedbackKey(normalized)
    const group = groups.get(key) ?? { key, count: 0, classification: normalized.classification, items: [] }
    group.count += 1
    group.items.push(normalized)
    const order = { p0: 0, p1: 1, p2: 2, p3: 3 }
    if (order[normalized.classification.severity] < order[group.classification.severity]) {
      group.classification = normalized.classification
    }
    groups.set(key, group)
  }
  return [...groups.values()].sort((a, b) => b.count - a.count)
}

export function buildIssueDraft(group, options = {}) {
  const projectName = options.projectName ?? 'ぬるぬる'
  const c = group.classification ?? { type: 'other', severity: 'p3', platform: 'unknown', featureArea: 'unknown', labels: [] }
  const first = group.items?.[0]
  const text = first?.text ?? eventToFeedbackText(first?.event) ?? ''
  const labels = unique(['source:nostr', ...(c.labels ?? []), ...(options.labels ?? [])])
  const titlePrefix = c.type === 'feature' ? '要望' : c.type === 'design' ? 'デザイン' : c.type === 'copy' ? 'コピー' : c.type === 'performance' ? '性能' : 'フィードバック'
  const title = '[' + titlePrefix + '] ' + c.platform + '/' + c.featureArea + ': ' + (text.replace(/\s+/g, ' ').slice(0, 48) || projectName)
  const sources = (group.items ?? []).slice(0, 10).map((item, index) => {
    const event = item.event ?? {}
    const relay = item.relay ? ' relay=' + item.relay : ''
    const id = event.id ? 'nostr:' + event.id : 'item-' + (index + 1)
    return '- ' + id + relay
  }).join('\n')
  const quotes = (group.items ?? []).slice(0, 5).map((item) => '> ' + String(item.text ?? '').replace(/\n/g, '\n> ').slice(0, 700)).join('\n\n')

  const body = '## Summary\n\n' +
    'Nostr feedback for **' + projectName + '** was grouped automatically by nurunuru-mcp. Please verify the report before implementing.\n\n' +
    '## Classification\n\n' +
    '- Type: ' + c.type + '\n' +
    '- Severity: ' + c.severity + '\n' +
    '- Platform: ' + c.platform + '\n' +
    '- Area: ' + c.featureArea + '\n' +
    '- Similar reports: ' + (group.count ?? group.items?.length ?? 1) + '\n' +
    '- Confidence: ' + (c.confidence ?? 'unknown') + '\n' +
    '- Suggested labels: ' + labels.join(', ') + '\n\n' +
    '## User words\n\n' + (quotes || '> (no text)') + '\n\n' +
    '## Sources\n\n' + (sources || '- No source metadata') + '\n\n' +
    '## Reproduction hypothesis\n\n' +
    '1. Open the affected ' + projectName + ' surface.\n' +
    '2. Follow the user-reported action.\n' +
    '3. Check whether the reported symptom appears.\n\n' +
    '## Acceptance criteria\n\n' +
    '- The user-reported symptom is fixed or intentionally explained.\n' +
    '- No private keys, tokens, DMs, or sensitive user data are logged.\n' +
    '- Existing platform guardrails and design/copy rules remain intact.\n' +
    '- If UI changes are needed, Android/iOS parity and Japanese copy are reviewed.\n\n' +
    '## Human review checklist\n\n' +
    '- [ ] The source post is legitimate feedback, not casual conversation or spam.\n' +
    '- [ ] Duplicate issues were checked before implementation.\n' +
    '- [ ] Severity and platform labels are correct.\n' +
    '- [ ] Product/design intent is preserved.\n'

  return { title, body, labels }
}

function parseRelayMessage(data) {
  try {
    const message = JSON.parse(String(data))
    if (!Array.isArray(message)) return null
    return message
  } catch {
    return null
  }
}

export async function queryRelay(relayUrl, filter, options = {}) {
  const url = normalizeRelayUrl(relayUrl)
  if (!url) throw new Error('invalid relay url: ' + relayUrl)
  if (typeof WebSocket === 'undefined') {
    throw new Error('global WebSocket is unavailable; run with Node.js 20+ or a runtime that provides WebSocket')
  }

  const timeoutMs = Math.max(500, Number(options.timeoutMs ?? DEFAULT_TIMEOUT_MS))
  const subId = 'nurunuru-mcp-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 8)
  const events = []
  const notices = []
  let eose = false

  return await new Promise((resolve) => {
    const startedAt = Date.now()
    const ws = new WebSocket(url)
    let settled = false
    const finish = (status, error = null) => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      try { if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(['CLOSE', subId])) } catch {}
      try { ws.close() } catch {}
      resolve({ relay: url, status, error: error ? String(error.message ?? error) : null, eose, notices, events, elapsedMs: Date.now() - startedAt })
    }
    const timer = setTimeout(() => finish('timeout'), timeoutMs)

    ws.addEventListener('open', () => {
      try { ws.send(JSON.stringify(['REQ', subId, filter])) } catch (error) { finish('send_error', error) }
    })
    ws.addEventListener('message', (evt) => {
      const message = parseRelayMessage(evt.data)
      if (!message) return
      const [type, id, payload] = message
      if (type === 'EVENT' && id === subId && payload && typeof payload === 'object') {
        events.push({ ...payload, relay: url })
      } else if (type === 'EOSE' && id === subId) {
        eose = true
        finish('eose')
      } else if (type === 'NOTICE') {
        notices.push(String(id ?? payload ?? ''))
      }
    })
    ws.addEventListener('error', (evt) => finish('error', evt.error ?? 'websocket error'))
    ws.addEventListener('close', () => finish(eose ? 'closed_after_eose' : 'closed'))
  })
}

export async function nip50Search(input = {}) {
  const filter = buildNip50Filter(input)
  const relays = unique(asArray(input.relays).length ? asArray(input.relays).map(normalizeRelayUrl) : DEFAULT_SEARCH_RELAYS)
  const relayResults = await Promise.all(relays.map((relay) => queryRelay(relay, filter, { timeoutMs: input.timeoutMs })))
  const byId = new Map()
  for (const result of relayResults) {
    for (const event of result.events) {
      if (!event.id) continue
      const existing = byId.get(event.id)
      if (!existing) byId.set(event.id, { ...event, seenOn: [result.relay] })
      else existing.seenOn = unique([...(existing.seenOn ?? []), result.relay])
    }
  }
  const events = [...byId.values()].sort((a, b) => (b.created_at ?? 0) - (a.created_at ?? 0)).slice(0, filter.limit)
  return { filter, relays, relayResults: relayResults.map(({ events, ...rest }) => ({ ...rest, eventCount: events.length })), events }
}

export async function collectFeedback(input = {}) {
  const queries = unique(asArray(input.queries).length ? asArray(input.queries).map(String) : DEFAULT_FEEDBACK_QUERIES)
  const sinceHours = Number(input.sinceHours ?? 72)
  const since = input.since ?? (Number.isFinite(sinceHours) && sinceHours > 0 ? Math.floor(Date.now() / 1000 - sinceHours * 3600) : undefined)
  const perQueryLimit = normalizeLimit(input.perQueryLimit ?? input.limit ?? 20)
  const results = []

  for (const query of queries.slice(0, 12)) {
    const result = await nip50Search({ ...input, query, since, limit: perQueryLimit })
    results.push(result)
  }

  const byId = new Map()
  for (const result of results) {
    for (const event of result.events) {
      if (!event.id || byId.has(event.id)) continue
      const classified = classifyFeedbackEvent(event, input)
      const includeOther = Boolean(input.includeOther)
      if (includeOther || classified.classification.type !== 'other') {
        byId.set(event.id, classified)
      }
    }
  }

  const items = [...byId.values()].sort((a, b) => (b.event?.created_at ?? 0) - (a.event?.created_at ?? 0))
  const groups = groupFeedbackItems(items)
  const issueDrafts = groups.slice(0, Number(input.maxDrafts ?? 10)).map((group) => buildIssueDraft(group, input))
  return { queries, since, itemCount: items.length, items, groups, issueDrafts, relayResults: results.flatMap((r) => r.relayResults) }
}

export const defaults = { relays: DEFAULT_SEARCH_RELAYS, feedbackQueries: DEFAULT_FEEDBACK_QUERIES, kinds: DEFAULT_KINDS }
