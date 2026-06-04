## Summary

<!-- 変更の概要を1〜3行で書いてください -->

## Type

- [ ] L1 docs / typo / link / wiki lint
- [ ] L2 dependency update / small compatibility follow-up
- [ ] L3 bug fix / parity / a11y
- [ ] L4 new UI / feature / NIP support (Design Crit may be required)
- [ ] Other:

## Affected areas

- [ ] Web
- [ ] Android
- [ ] iOS
- [ ] Rust / FFI
- [ ] docs/wiki
- [ ] Build / CI / tooling
- [ ] Security / key / signing / passkey

## NuruNuru principles

<!-- docs/wiki/culture/principles.md の五箇条のうち、この変更が支える / 関連する条文を1つ以上書いてください -->

例: 第四条「一貫性は新機能より重い」: Android と iOS の表示差分を既存仕様に合わせた。

## Verification done

<!-- 実行したコマンド、手動確認、端末、OS、relay 状態など -->

- [ ] `npm run test`
- [ ] `npm run build`
- [ ] `npm run wiki:lint`
- [ ] `npm run tokens:check`
- [ ] Android build / manual check
- [ ] iOS build / manual check
- [ ] Other:

## Not verified

<!-- 検証していないことを正直に書いてください。未検証を隠さないことを歓迎します。 -->

## Security / privacy checklist

- [ ] This PR does not expose private keys, nsec, seed, passkey material, or signatures in logs / UI / `window.*`.
- [ ] This PR does not store private keys in UserDefaults, localStorage plaintext, logs, or unencrypted files.
- [ ] If this touches key / signing / passkey / encryption code, I included upstream release notes or migration notes.
- [ ] If this is a security-sensitive report, details were not posted publicly.

## Wiki / docs

- [ ] No wiki update needed.
- [ ] Updated relevant `docs/wiki/` page(s).
- [ ] Updated `docs/wiki/index.md` if a page was added / renamed / significantly changed.
- [ ] Updated `docs/wiki/log.md` for meaningful architecture / feature / NIP / security / parity changes.

## LLM-assisted contribution

- [ ] No LLM was used.
- [ ] LLM was used and reviewed by a human responsible for this PR.
- [ ] `Co-authored-by:` or PR text discloses LLM assistance where appropriate.

## Related Issue / ADR / Wiki

<!-- Issue, ADR, wiki page, or discussion link -->
