#!/usr/bin/env node
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const scriptDir = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(scriptDir, '..')
const wikiDir = path.join(root, 'docs/wiki')
let failures = 0
const warnings = []

function walk(dir) {
  const out = []
  for (const name of readdirSync(dir)) {
    const p = path.join(dir, name)
    const st = statSync(p)
    if (st.isDirectory()) out.push(...walk(p))
    else if (name.endsWith('.md')) out.push(p)
  }
  return out
}

function relWiki(p) {
  return path.relative(wikiDir, p).replace(/\\/g, '/')
}

function fail(msg) { failures++; console.error(`FAIL ${msg}`) }
function warn(msg) { warnings.push(msg); console.warn(`WARN ${msg}`) }

if (!existsSync(wikiDir)) fail('docs/wiki does not exist')
const files = existsSync(wikiDir) ? walk(wikiDir) : []
const rels = new Set(files.map(relWiki))
const index = existsSync(path.join(wikiDir, 'index.md')) ? readFileSync(path.join(wikiDir, 'index.md'), 'utf8') : ''

for (const f of files) {
  const rel = relWiki(f)
  const text = readFileSync(f, 'utf8')
  if (rel !== 'index.md' && rel !== 'log.md' && !index.includes(rel.replace(/\.md$/, '')) && !index.includes(rel)) {
    warn(`${rel} may be missing from docs/wiki/index.md`)
  }
  if (!/^#\s+/m.test(text)) fail(`${rel} missing H1 title`)
  if (rel !== 'log.md' && !/## Source references/m.test(text)) warn(`${rel} missing '## Source references'`)

  const linkRe = /\[\[([^\]|#]+)(?:#[^\]|]+)?(?:\|[^\]]+)?\]\]/g
  let m
  while ((m = linkRe.exec(text))) {
    const target = m[1]
    if (/^https?:/.test(target)) continue
    const baseDir = path.dirname(rel)
    const candidates = []
    const normalized = target.endsWith('.md') ? target : `${target}.md`
    candidates.push(path.normalize(path.join(baseDir, normalized)).replace(/\\/g, '/'))
    candidates.push(path.normalize(normalized).replace(/\\/g, '/'))
    if (!candidates.some(c => rels.has(c))) warn(`${rel} has unresolved wikilink [[${target}]]`)
  }
}

// Basic markdown links in AGENTS.md
const agentsPath = path.join(root, 'AGENTS.md')
if (existsSync(agentsPath)) {
  const agents = readFileSync(agentsPath, 'utf8')
  const mdLinkRe = /\[[^\]]+\]\(([^)]+)\)/g
  let m
  while ((m = mdLinkRe.exec(agents))) {
    const href = m[1]
    if (/^(https?:|mailto:|#)/.test(href)) continue
    const clean = href.replace(/^\.\//, '').split('#')[0]
    if (clean && !existsSync(path.join(root, clean))) fail(`AGENTS.md link target missing: ${href}`)
  }
}

const logPath = path.join(wikiDir, 'log.md')
if (existsSync(logPath)) {
  const log = readFileSync(logPath, 'utf8')
  for (const line of log.split(/\r?\n/)) {
    if (line.startsWith('## ') && !/^## \[\d{4}-\d{2}-\d{2}\] [a-z-]+ \| .+/.test(line)) {
      fail(`log.md malformed entry header: ${line}`)
    }
  }
}

console.log(`wiki-lint: ${failures} failure(s), ${warnings.length} warning(s)`)
process.exit(failures ? 1 : 0)
