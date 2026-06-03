# Manual Cohort Observation — Week-1 復帰率の手動観察

## Summary

ADR-0014 により、6月 Phase 1 では製品内の local-first metrics 実装を見送る。代わりに、Week-1 復帰率を **manual cohort 観察**で追跡する。

このページは、毎週 5 人程度の新規 / 再登録ユーザーを対象に、オンボーディング・初投稿・反応確認・7日以内の復帰を手動で記録するための運用テンプレートである。

## Current behavior

現状、ぬるぬるは製品内 telemetry を追加していない。ThemaDAY / Design Crit / manual real-device QA を一次情報として扱う。

## North Star

> **Week-1 復帰率 = 新規登録後 7日以内に、2回目の起動 or 自分の投稿への反応を確認した人の割合**

これは DAU / WAU / 滞在時間ではなく、「ぬるぬるが日常に戻ってくる理由を作れているか」を見るための代理指標である。

## Weekly cohort size

| 項目 | 初期値 |
|---|---:|
| 観察人数 | 5人 / 週 |
| 観察期間 | 登録日 + 7日 |
| 記録場所 | ThemaDAY / QA note |
| 製品コード計測 | なし |
| 個人情報保存 | しない |

## 対象ユーザー

Phase 0 の ICP に合わせ、以下を優先する。

1. 日本の Nostr 既存ユーザー
2. プライバシー意識のある一般ユーザー

クリエイター / 開発者は Phase 1 以降または受動観察に置く。

## 記録してよいもの / してはいけないもの

### 記録してよい

- cohort 番号 (`W23-01` など)
- プラットフォーム (Web / Android / iOS)
- 登録完了の有無
- 初投稿完了の有無
- `#nostrはじめました` の有無
- 公式 / ぬるる / 他ユーザーからの反応を見たか
- 7日以内に戻ったか
- 迷った箇所の短いメモ

### 記録しない

- 秘密鍵 / nsec / token
- DM 内容
- 電話番号 / メール / 本名など個人情報
- 正確な位置情報
- ユーザーが公開していない private context

## Weekly scorecard template

以下を各週の ThemaDAY / QA note にコピーして使う。

### Summary

- Week:
- Observer hat:
- Cohort size:
- Platforms:

### Scorecard

| Metric | Count | Notes |
|---|---:|---|
| 新規登録観察人数 | 0 | |
| 登録完了 | 0 | |
| 初投稿完了 | 0 | |
| `#nostrはじめました` 投稿 | 0 | |
| 初投稿後に反応を見た | 0 | |
| Week-1 復帰 | 0 | |
| 共有リンクを使った | 0 | |
| ガードレール違反 | 0 | |

### Per-user observation

| ID | Platform | ICP | Registered | First post | Reaction seen | Returned W1 | Friction | Follow-up |
|---|---|---|---|---|---|---|---|---|
| WXX-01 | iOS | Nostr existing / privacy general | Y/N | Y/N | Y/N | Y/N | | |
| WXX-02 | Android | Nostr existing / privacy general | Y/N | Y/N | Y/N | Y/N | | |
| WXX-03 | Web | Nostr existing / privacy general | Y/N | Y/N | Y/N | Y/N | | |

## Operating rules

1. 毎週 5 人を上限にする。観察量を増やしても学習速度が上がるとは限らない。
2. 反応ループを必ず見る。登録完了だけで終わらせない。
3. 迷った箇所は UI / copy / trust / platform のどれかに分類する。
4. 失敗を隠さない。FAIL は次回 ThemaDAY の入力にする。
5. ガードレール違反が 1 件でもあれば、成長施策を止めて Design Crit に戻す。

## Platform notes

- Web / Android / iOS とも製品 telemetry を追加しない。
- iOS Keychain / Web secure-key closure / Android signer 境界に関わる情報は記録しない。
- スクリーンショットを残す場合は秘密鍵・DM・個人情報が写っていないことを確認する。

## Source references

- `docs/wiki/decisions/adr-0014-local-first-product-metrics.md`
- `docs/wiki/strategy/themaday-2026-06-03-marketing-growth.md`
- `docs/wiki/culture/not-doing.md`
- `docs/wiki/culture/release-quality.md`

## Related pages

- [[../strategy/themaday-2026-06-03-marketing-growth]]
- [[../decisions/adr-0014-local-first-product-metrics]]
- [[../culture/design-crit]]
- [[qa-template]]

## Open questions

- 最初の 5 人 cohort をどこから集めるか。
- 公式 npub / ぬるる npub からの反応を、誰がどの時間帯に行うか。
- Week-1 復帰の判定を「2回目の起動」だけで見るか、「反応確認」も同等に扱うか。
