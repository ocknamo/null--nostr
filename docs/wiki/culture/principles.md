# NuruNuru Charter v0.1 — 北極星と五箇条

## Summary

ぬるぬる (null--nostr) の文化的憲章 v0.1。北極星 (long-term mission) と五箇条 (immediate discipline) の二層で構成する。新機能・新 NIP・新プラットフォーム判断の最終的な拠り所はソースコードと [[../ui/design-tokens|design tokens]] であり、本ページは「設計判断の優先順位」を言語化したものとして扱う。

## 北極星 (North Star)

> **ぬるぬるは、10年後の主権的コミュニケーションを、日本語の日常として先に実装する。**

ここで言う「主権的コミュニケーション」は単なるチャットを意味しない。長期的には [[four-freedoms|4軸の自由 (言論・プライバシー・経済・配布)]] を内包し、それらを **「祖父母にも使える日本語の日常体験」** に翻訳することを指す。技術 (Nostr / Bitcoin / MLS / mini-apps) は基盤に隠し、表層は LINE のような所作レベルの統合を目指す。

## 五箇条 (Five Principles)

意思決定で対立が起きたとき、若い番号の条文が優先する。

```text
一、 日常を壊さない。
    Nostr の概念より、読む・書く・反応する体験を優先する。

二、 日本語を第一級市民にする。
    翻訳された海外アプリに見せない。行間・約物・絵文字文化を尊ぶ。

三、 複雑さは裏側に隠す。
    リレー・署名・NIP・鍵は、必要な時だけ顔を出す。

四、 一貫性は新機能より重い。
    Web / Android / iOS が割れるくらいなら、機能追加を遅らせる。

五、 かわいさと、秘密鍵への厳格さを、同時に持つ。
    人にやさしく、署名と鍵には冷酷であれ。
```

## 五箇条の使い方

- すべての UI PR は「五箇条のどれに該当するか」を1行で書く ([[../decisions/adr-0007-design-crit-ritual|ADR-0007]] 参照)。
- 新規 ADR は `Why this fits NuruNuru` セクションで五箇条との整合を必ず述べる。
- 五箇条同士が対立したときは、原則として若い番号を優先する。例外を選んだ場合は ADR を残す。

## 解説

### 第一条「日常を壊さない」

ぬるぬるは Nostr 教育アプリではない。リレー・公開鍵・NIP 番号といった概念はソフトウェア内部の都合であり、ユーザーが毎日触る理由ではない。「Nostr のここがすごい」を見せたくなる衝動を、最初に殺す条文。

### 第二条「日本語を第一級市民にする」

日本語のコピー・行間・約物 (句読点や括弧)・絵文字文化・LINE Seed JP などの組版品質は、海外 Nostr クライアントが最も弱い領域。ここを譲ると参戦する意味がない。詳細は [[copy-style]]。

### 第三条「複雑さは裏側に隠す」

Nostr / MLS / NIP-46 / Lightning / mini-apps、いずれも内部的には複雑だが、表層は「投稿する」「送る」「もらう」程度の語彙で完結させる。複雑さを表に出すのは「ユーザーがその複雑さを理解した上で初めて安全に判断できる」場面 (秘密鍵の取り扱いなど) に限る。

### 第四条「一貫性は新機能より重い」

Web / Android / iOS のパリティは [[../platforms/parity-matrix|parity matrix]] と [[../ui/android-ios-sync|android-ios-sync]] で管理する。1プラットフォームだけ先行する判断は、原則として ADR が必要。

### 第五条「かわいさと、秘密鍵への厳格さを、同時に持つ」

UI は親しみやすく、しかし鍵管理は妥協しない。Keychain only / [[../platforms/ios|iOS]] / closure-only key store / NIP-46 bunker 等のセキュリティ規約は装飾性のために緩めない。

## Charter のバージョニング

- **v0.1 (現在)**: コミュニケーション中心の規律と、10年先のミッション宣言。
- **v1.0 (将来)**: [[four-freedoms|4軸の自由]] の最初の実装 (経済・配布) が動いた時点で昇格を検討。第六条以降の追加もここで議論する。

## Related pages

- [[not-doing]] — ぬるぬるが意図的にやらないこと
- [[design-crit]] — Weekly Nuru Design Crit の運用
- [[release-quality]] — 月曜リリース列車と Nuru Production System
- [[copy-style]] — 日本語コピー規約
- [[llm-onboarding]] — LLM コントリビュータ向け
- [[four-freedoms]] — 10年先の4軸自由ドクトリン
- [[../decisions/adr-0007-design-crit-ritual]] — Design Crit の制度化
- [[../decisions/adr-0008-four-freedoms-mission]] — 4軸自由を長期ミッションとして起票

## Source references

- `AGENTS.md`
- `design-tokens/constants.json`
- `docs/wiki/ui/android-ios-sync.md`
- `docs/wiki/platforms/parity-matrix.md`
- `ios/GUARDRAILS.md`
