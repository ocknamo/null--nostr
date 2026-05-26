# ぬるぬる 1.5.3

## Timeline reliability

- Android のフォロー / グローバル / リレー別タイムラインで、空の6時間ウィンドウに当たっても数ウィンドウ先まで探索するようにしました。
- 投稿が少ないフォロー先やリレーでも、過去投稿の無限スクロールが途中で止まりにくくなりました。
- 既存の network-first タイムライン、bounded pagination、raw-first 表示、後追い enrichment を維持しています。

## Privacy

- 公開メタデータやリリースノートに本名・メールアドレスなどの個人情報を含めていません。

## Artifacts

- Android APK: nurunuru-1.5.3-arm64-v8a.apk
- Google Play AAB: nurunuru-1.5.3-google-play.aab
- App Store Connect IPA: NuruNuru.ipa
