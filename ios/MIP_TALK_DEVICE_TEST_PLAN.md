# iOS Talk MIP-00/01/02/03 実機テスト手順（NuruNuru）

このドキュメントは、iOS 実機で Talk 機能（MIP-00, 01, 02, 03）を検証し、
起動ログ・診断ログを収集して不具合解析に使うための手順です。

---

## 0. 前提

- macOS + Xcode（Command Line Tools 含む）
- 実機 iPhone が USB 接続済み・信頼済み・ロック解除済み
- Apple Developer 設定（署名）済み
- リポジトリルートで作業

既定値（必要に応じて変更）:
- Bundle ID: `io.nurunuru.app`
- 実機 UDID: `00008101-000D148A0E82001E`
- Script: `ios/scripts/ios-cli.sh`

---

## 1. 実機ビルド・インストール・起動

```bash
cd ios
bash scripts/ios-cli.sh device-run 00008101-000D148A0E82001E
```

期待結果:
- Build success
- Install success
- Launch success
- `proc` 相当の出力で `NuruNuru` プロセスが見える

補助確認:
```bash
bash scripts/ios-cli.sh proc 00008101-000D148A0E82001E
```

---

## 2. 起動時ログ（コンソール）採取

```bash
cd ios
bash scripts/ios-cli.sh logs-device 00008101-000D148A0E82001E
```

- アプリを起動し直しつつ、`--console` 出力を確認
- 停止は `Ctrl + C`

注記:
- 環境によっては CoreDevice の警告（Code=1002）が出ても、
  build/install/launch が成功していれば致命ではないケースがあります。

---

## 3. 診断ログ（zip/json/log）採取

```bash
cd ios
bash scripts/ios-cli.sh diagnose-device 00008101-000D148A0E82001E
```

出力先:
- `ios/build-cli/devicectl-diagnose-<timestamp>.zip`
- `ios/build-cli/devicectl-diagnose-<timestamp>.json`
- `ios/build-cli/devicectl-diagnose-<timestamp>.log`

補足:
- `devicectl diagnose` は `--devices` 指定が正
- 収集内容は端末状態・接続状態で変動

---

## 4. MIPシナリオテスト（実機UI操作）

以下を 1 セッションで順に実施し、各ステップで画面結果とログを記録。

### MIP-00: 基本トークフロー

1. Talk タブを開く
2. 既存スレッド/グループ一覧が表示される
3. スレッドを開いてメッセージを送信
4. 自端末で送信済み表示を確認

確認ポイント:
- 画面フリーズなし
- 送信後にUIが更新される
- 戻る/再入場で履歴が保持される

### MIP-01: グループ作成・参加導線

1. Talk で新規グループ作成
2. 招待/参加導線を実行
3. 参加後にグループが一覧へ反映される

確認ポイント:
- 作成直後の遷移が自然
- グループメタ情報（名前・メンバー）表示崩れなし

### MIP-02: メッセージ整合性・状態遷移

1. 同一グループで複数メッセージ送受信
2. 再起動後に履歴再取得
3. ネットワーク一時断→復帰を試験

確認ポイント:
- 重複表示や欠落がない
- 既読/未読や内部状態（loading/error）が破綻しない

### MIP-03: 例外系

1. 不正/欠損イベントを想定したケース（受信失敗・復号失敗）
2. アプリが落ちず、ユーザー向けに失敗を吸収できるか確認

確認ポイント:
- クラッシュしない
- 失敗時も他スレッド操作へ影響しない

---

## 5. 障害発生時の切り分けテンプレ

1. 再現手順を 1 行ずつ固定（時刻付き）
2. 直後に `logs-device` を採取
3. `diagnose-device` を採取
4. 可能なら再起動後の再現有無を確認

報告テンプレ:
- 端末: iPhone / iOS version
- Build: Debug/Release, commit hash
- 発生時刻: HH:MM:SS
- 操作手順: 1..N
- 期待結果 / 実結果
- 添付: console log, diagnose zip/json/log

---

## 6. 合格基準（今回）

- 実機 install/launch 成功
- Talk MIP-00~03 の主要シナリオを連続実行してクラッシュなし
- 失敗ケースで復帰可能
- ログ採取導線（console + diagnose）が再現可能

---

## 7. よく使うコマンドまとめ

```bash
# 実機 build/install/launch
cd ios && bash scripts/ios-cli.sh device-run <UDID>

# 起動後プロセス確認
cd ios && bash scripts/ios-cli.sh proc <UDID>

# コンソール出力確認（Ctrl+Cで停止）
cd ios && bash scripts/ios-cli.sh logs-device <UDID>

# 診断ログ収集
cd ios && bash scripts/ios-cli.sh diagnose-device <UDID>
```
