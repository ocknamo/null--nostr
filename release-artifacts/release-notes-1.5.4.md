# ぬるぬる 1.5.4

## Highlights
- タイムラインの通常表示から NIP-71 ろくなな動画イベントを分離し、テキスト投稿・長文・リポスト中心の時系列表示を安定化しました。
- リポスト表示でリポスト元ユーザーとリポスト時刻を保持し、フォロータイムラインの文脈が分かりやすくなりました。
- 空または失敗した古いページ取得が 1 回発生しても、無限スクロールがすぐ止まらないよう改善しました。
- Android の投稿本文内 URL をタップで開けるようにしました。
- Android / iOS の通知復元と取得で表示対象タイプを whitelist し、想定外の通知種別を表示しないようにしました。
- パスキーログインとパスキー署名セッションの安定性を改善しました。

## Artifacts
- Android APK: release-artifacts/nurunuru-1.5.4-arm64-v8a.apk
- Google Play AAB: release-artifacts/nurunuru-1.5.4-google-play.aab

## Notes
- iOS App Store Connect 用の IPA / xcarchive はローカル生成のみです。GitHub Release には添付しません。
