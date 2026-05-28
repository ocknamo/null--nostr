# Feedback Loop Automation

## Summary

ぬるぬるの feedback loop automation は、Nostr の投稿を NIP-50 search relay で収集し、goose / MCP で分類・重複排除・GitHub Issue draft 化する運用基盤です。目的は「完全無人リリース」ではなく、ユーザーの声を逃さず、低リスク修正を速く PR 化し、最終の美意識・安全性・リリース判断を人間が握ることです。

## Current behavior

- scripts/mcp/nurunuru-mcp.mjs は stdio MCP server として動作する。
- nip50_search tool は NIP-50 search filter を wss://search.nos.today へ送り、kind 1 note を検索する。
- collect_feedback tool は ぬるぬる / #ぬるぬるはじめました / nullnull Android / nullnull iOS / nullnull / via nullnull variants を既定 query として検索し、bug / feature / design / copy / performance を分類する。
- via nullnull 系 query は JSON content 内の via が search relay に index されていれば検索できます。via が relay/client tag のみで index されない場合は直接検索できない可能性がありますが、取得済み event の client / via tag と JSON metadata は分類時に読みます。
- classify_feedback tool はテキストや event-like object を severity / platform / area labels に変換する。
- draft_github_issue tool は分類済み feedback group から GitHub Issue の title/body/labels を生成する。
- package.json scripts: npm run mcp:nurunuru / npm run feedback:search / npm run feedback:collect。

## Platform notes

### Goose scheduler

.goose/recipes/nurunuru-daily-feedback.yaml は goose scheduler から定期実行するための prompt template です。実運用では goose 側で nurunuru-mcp と GitHub MCP または gh CLI を有効化します。

Goose Desktop の recipe panel から project-local recipe が見えない場合は、`.goose/recipes/*.yaml` の存在と workspace を確認したうえで Desktop を完全再起動します。2026-05-28 の復旧確認では、recipe files は削除されておらず、macOS Trash にも backup はなく、Goose Desktop 再起動後に一覧へ再表示されました。詳細は [[goose-recipes]] を参照。

1. collect_feedback で Nostr 投稿を収集。
2. 既存 GitHub Issues と重複確認。
3. 新規または既存 Issue に draft を作成/追記。
4. autofix:candidate を付けられる低リスク Issue のみ PR agent に渡す。

### Boundaries

- 自動 Issue 作成と PR draft 作成は推奨。
- 自動 merge / production release は原則禁止。人間が Design Crit、秘密鍵/署名、配布判断を確認する。
- 元投稿の原文は Issue に残し、AI 要約だけでユーザーの温度を消さない。
- 秘密鍵、DM、個人情報、token は Issue body / logs に保存しない。

## Source references

- scripts/mcp/nurunuru-mcp.mjs
- scripts/mcp/nurunuru-feedback.mjs
- src/__tests__/mcp/nurunuru-feedback.test.ts
- .goose/recipes/nurunuru-daily-feedback.yaml
- .goose/recipes/nurunuru-autofix-candidates.yaml
- package.json

## Related pages

- [[../features/search]]
- [[../nips/nip-50]]
- [[../culture/design-crit]]
- [[../culture/copy-style]]
- [[goose-recipes]]
- [[../strategy/themaday-2026-05-25]]

## Open questions

- search.nos.today の NIP-50 query grammar / ranking / retention は外部サービス依存のため、relay outage 時の fallback search relay list を増やす必要がある。
- GitHub Issue の実作成は GitHub MCP または gh CLI の認証状態に依存する。
- Store reviews / Play Vitals / App Store Connect analytics ingestion は次 phase で別 MCP tool として統合する。
