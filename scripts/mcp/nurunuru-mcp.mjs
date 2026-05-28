#!/usr/bin/env node
import {
  buildIssueDraft,
  classifyFeedbackEvent,
  classifyFeedbackText,
  collectFeedback,
  defaults,
  groupFeedbackItems,
  nip50Search,
} from './nurunuru-feedback.mjs'

const SERVER_INFO = { name: 'nurunuru-mcp', version: '0.1.0' }

const tools = [
  {
    name: 'nip50_search',
    description: 'Search Nostr events through NIP-50 search relays such as search.nos.today. Defaults to kind 1 notes.',
    inputSchema: {
      type: 'object',
      properties: {
        query: { type: 'string', description: 'NIP-50 search query text.' },
        relays: { type: 'array', items: { type: 'string' }, description: 'Search relay URLs. Defaults to wss://search.nos.today.' },
        kinds: { type: 'array', items: { type: 'number' }, description: 'Nostr event kinds. Defaults to [1].' },
        limit: { type: 'number', description: 'Maximum events returned, capped at 100.' },
        since: { type: 'number', description: 'Unix timestamp lower bound.' },
        until: { type: 'number', description: 'Unix timestamp upper bound.' },
        authors: { type: 'array', items: { type: 'string' } },
        tags: { type: 'object', description: 'Tag filters such as {t:[nurunuru]}.' },
        timeoutMs: { type: 'number', description: 'Per-relay timeout in milliseconds.' },
      },
      required: ['query'],
    },
  },
  {
    name: 'collect_feedback',
    description: 'Search project keywords, classify likely bug/request/design feedback, group duplicates, and draft GitHub issue text.',
    inputSchema: {
      type: 'object',
      properties: {
        queries: { type: 'array', items: { type: 'string' }, description: 'Project/search terms. Defaults to ぬるぬる, nurunuru, null--nostr, nullnostr.' },
        relays: { type: 'array', items: { type: 'string' } },
        sinceHours: { type: 'number', description: 'Lookback window. Defaults to 72 hours.' },
        perQueryLimit: { type: 'number' },
        includeOther: { type: 'boolean', description: 'Include posts that do not look like feedback.' },
        projectName: { type: 'string', description: 'Name used in issue drafts.' },
        maxDrafts: { type: 'number', description: 'Maximum issue drafts returned.' },
        timeoutMs: { type: 'number' },
      },
    },
  },
  {
    name: 'classify_feedback',
    description: 'Classify text or event-like objects into bug/feature/design/copy/performance feedback labels.',
    inputSchema: { type: 'object', properties: { items: { type: 'array', items: {} }, defaultPlatform: { type: 'string' } }, required: ['items'] },
  },
  {
    name: 'draft_github_issue',
    description: 'Build GitHub issue title/body/labels from classified feedback items or a pre-grouped feedback object.',
    inputSchema: { type: 'object', properties: { items: { type: 'array', items: {} }, group: { type: 'object' }, projectName: { type: 'string' }, labels: { type: 'array', items: { type: 'string' } } } },
  },
  { name: 'defaults', description: 'Return default relays, event kinds, and feedback search queries.', inputSchema: { type: 'object', properties: {} } },
]

function jsonContent(value) { return [{ type: 'text', text: JSON.stringify(value, null, 2) }] }

async function callTool(name, args = {}) {
  switch (name) {
    case 'nip50_search': return jsonContent(await nip50Search(args))
    case 'collect_feedback': return jsonContent(await collectFeedback(args))
    case 'classify_feedback': {
      const items = Array.isArray(args.items) ? args.items : []
      return jsonContent({ items: items.map((item) => typeof item === 'string' ? { text: item, classification: classifyFeedbackText(item, args) } : classifyFeedbackEvent(item, args)) })
    }
    case 'draft_github_issue': {
      if (args.group) return jsonContent(buildIssueDraft(args.group, args))
      const items = (Array.isArray(args.items) ? args.items : []).map((item) => {
        if (item?.classification) return item
        return typeof item === 'string' ? { text: item, classification: classifyFeedbackText(item, args) } : classifyFeedbackEvent(item, args)
      })
      const [group] = groupFeedbackItems(items)
      return jsonContent(group ? buildIssueDraft(group, args) : { title: '', body: '', labels: [] })
    }
    case 'defaults': return jsonContent(defaults)
    default: throw new Error('unknown tool: ' + name)
  }
}

function makeResponse(id, result) { return { jsonrpc: '2.0', id, result } }
function makeError(id, code, message) { return { jsonrpc: '2.0', id, error: { code, message } } }

async function handleMessage(message) {
  if (!message || typeof message !== 'object') return null
  const { id, method, params } = message
  try {
    if (method === 'initialize') {
      return makeResponse(id, { protocolVersion: params?.protocolVersion ?? '2024-11-05', capabilities: { tools: {} }, serverInfo: SERVER_INFO })
    }
    if (method === 'notifications/initialized') return null
    if (method === 'tools/list') return makeResponse(id, { tools })
    if (method === 'tools/call') return makeResponse(id, { content: await callTool(params?.name, params?.arguments ?? {}) })
    if (method === 'ping') return makeResponse(id, {})
    if (id == null) return null
    return makeError(id, -32601, 'method not found: ' + method)
  } catch (error) {
    return makeError(id, -32000, String(error?.stack ?? error?.message ?? error))
  }
}

function writeMessage(message) {
  const json = JSON.stringify(message)
  process.stdout.write('Content-Length: ' + Buffer.byteLength(json, 'utf8') + '\r\n\r\n' + json)
}

async function runStdioServer() {
  let buffer = Buffer.alloc(0)
  process.stdin.on('data', async (chunk) => {
    buffer = Buffer.concat([buffer, chunk])
    while (true) {
      const headerEnd = buffer.indexOf('\r\n\r\n')
      if (headerEnd === -1) break
      const header = buffer.slice(0, headerEnd).toString('utf8')
      const match = /Content-Length:\s*(\d+)/i.exec(header)
      if (!match) { buffer = buffer.slice(headerEnd + 4); continue }
      const length = Number(match[1])
      const messageStart = headerEnd + 4
      const messageEnd = messageStart + length
      if (buffer.length < messageEnd) break
      const payload = buffer.slice(messageStart, messageEnd).toString('utf8')
      buffer = buffer.slice(messageEnd)
      let parsed
      try { parsed = JSON.parse(payload) } catch (error) { writeMessage(makeError(null, -32700, String(error.message ?? error))); continue }
      const response = await handleMessage(parsed)
      if (response) writeMessage(response)
    }
  })
}

function parseCliArgs(argv) {
  const args = {}
  const positionals = []
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i]
    if (!token.startsWith('--')) { positionals.push(token); continue }
    const key = token.slice(2)
    const next = argv[i + 1]
    if (next == null || next.startsWith('--')) args[key] = true
    else { args[key] = next; i += 1 }
  }
  args._ = positionals
  if (args.relays) args.relays = String(args.relays).split(',').map((s) => s.trim()).filter(Boolean)
  if (args.queries) args.queries = String(args.queries).split(',').map((s) => s.trim()).filter(Boolean)
  for (const key of ['limit', 'perQueryLimit', 'sinceHours', 'timeoutMs', 'maxDrafts']) {
    if (args[key] != null) args[key] = Number(args[key])
  }
  return args
}

async function runCli() {
  const command = process.argv[2]
  const args = parseCliArgs(process.argv.slice(3))
  if (command === 'search') {
    const query = args.query ?? args._.join(' ')
    console.log(JSON.stringify(await nip50Search({ ...args, query }), null, 2))
  } else if (command === 'collect') {
    console.log(JSON.stringify(await collectFeedback(args), null, 2))
  } else if (command === 'classify') {
    const text = args.text ?? args._.join(' ')
    console.log(JSON.stringify(classifyFeedbackText(text, args), null, 2))
  } else {
    await runStdioServer()
  }
}

runCli().catch((error) => { console.error(error); process.exit(1) })
