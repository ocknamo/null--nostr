# Goose Recipes and Desktop Loading

## Summary

ぬるぬるの Goose recipes は、feedback loop automation と release/autofix 運用を Goose Desktop / scheduler から再利用するための YAML prompt templates です。プロジェクトローカルの `.goose/recipes/` に置き、Goose Desktop では対象 workspace を開いた状態で読み込ませます。

2026-05-28 の復旧確認では、recipe YAML は削除されておらず `.goose/recipes/` に残っていました。Goose Desktop のレシピ一覧から一時的に消えていた原因は、Desktop 側の未再スキャン状態とみられます。Goose Desktop を完全終了して再起動すると、レシピ一覧に再表示されました。

## Current behavior

現在確認済みのプロジェクト recipe は以下です。

| Recipe | Purpose |
|---|---|
| `.goose/recipes/nurunuru-daily-feedback.yaml` | Nostr feedback を NIP-50 / nurunuru-mcp で収集し、GitHub Issue draft 化する日次 triage。 |
| `.goose/recipes/nurunuru-autofix-candidates.yaml` | `autofix:candidate` 相当の低リスク issue を修正 PR draft へ進めるための recipe。 |
| `.goose/recipes/nurunuru-release.yaml` | release 前確認、build/test、human approval 境界を扱う release recipe。 |

復旧時に確認したこと:

- 上記 3 recipe は `.goose/recipes/` に存在し、YAML 構造も同系統でした。
- Goose Desktop の recent dirs には `/Users/miharashouhei/null--nostr` が含まれていました。
- `~/.goose/recipes/` は存在せず、`~/.config/goose/recipes/` は空でした。
- `~/Library/Application Support/Goose/recipes/` は存在しませんでした。
- `~/Library/Application Support/Goose/recipe_hashes/` は存在し、hash file がありました。
- Goose Desktop の `/recipes/*` API endpoint は存在するものの、認証 token なしでは 401 でした。
- macOS Trash (`~/.Trash/`) は空で、`goose` / `recipe` / `nurunuru` / `*.yaml` / `*.yml` に一致する削除済み recipe backup は見つかりませんでした。

## Platform notes

### Goose Desktop

Goose Desktop で recipe が見えない場合の復旧手順:

1. workspace が `null--nostr` になっていることを確認する。
2. `.goose/recipes/*.yaml` が存在することを確認する。
3. YAML の基本構造 (`version`, `title`, `description`, `prompt`) を確認する。
4. Goose Desktop を完全終了する。
5. Goose Desktop を再起動し、recipe panel を再確認する。

今回の事象では **手順 4-5 の再起動で読み込まれました**。新規作成・復元直後の recipe は、Desktop 側が即時 watcher で拾わない場合があるため、まず再起動を試します。

### Scheduler / MCP operation

feedback loop recipes は `scripts/mcp/nurunuru-mcp.mjs` と組み合わせて使います。Goose scheduler で実運用する場合は、GitHub MCP または `gh` CLI の認証、Nostr feedback collection の query、human approval 境界を確認してから schedule します。

## Source references

- `.goose/recipes/nurunuru-daily-feedback.yaml`
- `.goose/recipes/nurunuru-autofix-candidates.yaml`
- `.goose/recipes/nurunuru-release.yaml`
- `scripts/mcp/nurunuru-mcp.mjs`
- `scripts/mcp/nurunuru-feedback.mjs`
- `docs/wiki/operations/feedback-loop.md`

## Related pages

- [[feedback-loop]]
- [[../nips/nip-50]]
- [[../strategy/themaday-2026-05-25]]

## Open questions

- Goose Desktop の recipe scan は起動時のみなのか、workspace 切替時・手動 scan endpoint 経由でも UI に反映できるのかは未確認です。
- `/recipes/*` API の auth token 取得方法と、Desktop UI と同じ scan 結果を CLI から安全に確認する方法は未確認です。
- project-local `.goose/recipes/` と global recipe directory の優先順位・merge 仕様は未確認です。
