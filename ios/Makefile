# NuruNuru iOS — ターミナル専用ビルド/シミュレータ操作
# Usage: make <target>

SCHEME       := NuruNuru
PROJECT      := NuruNuru.xcodeproj
BUNDLE_ID    := io.nurunuru.app
SIM_NAME     := iPhone 17
DEST         := platform=iOS Simulator,name=$(SIM_NAME)
BUILD_DIR    := $(CURDIR)/.build
XCODEGEN     := /tmp/xcodegen_extracted/xcodegen/bin/xcodegen
SKIP_PLUGINS := -skipPackagePluginValidation

# シミュレータ UUID を動的取得
SIM_UDID     := $(shell xcrun simctl list devices available -j \
                  | python3 -c "import sys,json; \
                    devs=[d for v in json.load(sys.stdin)['devices'].values() for d in v \
                    if d.get('name')=='$(SIM_NAME)' and d.get('isAvailable')]; \
                    print(devs[0]['udid'] if devs else '')" 2>/dev/null)

.PHONY: help gen build test run boot install launch log clean kill reset

help: ## このヘルプを表示
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*##"}{printf "  \033[36m%-12s\033[0m %s\n",$$1,$$2}'

# ── プロジェクト生成 ──────────────────────────────────────
gen: ## XcodeGen で xcodeproj を再生成
	$(XCODEGEN) generate --spec project.yml

# ── ビルド ────────────────────────────────────────────────
build: ## Debug ビルド（シミュレータ向け）
	xcodebuild \
	  -project $(PROJECT) \
	  -scheme $(SCHEME) \
	  -destination '$(DEST)' \
	  -configuration Debug \
	  -derivedDataPath $(BUILD_DIR) \
	  $(SKIP_PLUGINS) \
	  build 2>&1 | tee /tmp/xcode-build.log | grep -E "error:|warning:|Build succeeded|Build FAILED|▸"

build-release: ## Release ビルド（シミュレータ向け）
	xcodebuild \
	  -project $(PROJECT) \
	  -scheme $(SCHEME) \
	  -destination '$(DEST)' \
	  -configuration Release \
	  -derivedDataPath $(BUILD_DIR) \
	  $(SKIP_PLUGINS) \
	  build 2>&1 | tee /tmp/xcode-build.log | grep -E "error:|warning:|Build succeeded|Build FAILED|▸"

build-raw: ## フィルタなしの生ログでビルド
	xcodebuild \
	  -project $(PROJECT) \
	  -scheme $(SCHEME) \
	  -destination '$(DEST)' \
	  -derivedDataPath $(BUILD_DIR) \
	  $(SKIP_PLUGINS) \
	  build

# ── テスト ────────────────────────────────────────────────
test: ## 全テスト実行
	xcodebuild \
	  -project $(PROJECT) \
	  -scheme $(SCHEME) \
	  -destination '$(DEST)' \
	  -derivedDataPath $(BUILD_DIR) \
	  $(SKIP_PLUGINS) \
	  test 2>&1 | grep -E "Test (Case|Suite|session)|passed|failed|error:"

# ── シミュレータ操作 ──────────────────────────────────────
boot: ## シミュレータを起動（バックグラウンド）
	@echo "Booting $(SIM_NAME) ($(SIM_UDID))..."
	xcrun simctl boot "$(SIM_UDID)" 2>/dev/null || echo "Already booted"
	open -a Simulator

shutdown: ## シミュレータをシャットダウン
	xcrun simctl shutdown "$(SIM_UDID)"

install: ## ビルド済み .app をシミュレータにインストール
	@APP_PATH=$$(find $(BUILD_DIR)/Build/Products -name "$(SCHEME).app" -maxdepth 5 | head -1); \
	  echo "Installing: $$APP_PATH"; \
	  xcrun simctl install "$(SIM_UDID)" "$$APP_PATH"

launch: ## アプリを起動（フォアグラウンドでコンソールログ表示）
	xcrun simctl launch --console "$(SIM_UDID)" $(BUNDLE_ID)

run: boot install launch ## boot → install → launch を一発実行

# ── ビルド→インストール→起動（全部まとめて） ────────────
deploy: ## build + run を連続実行
	@$(MAKE) build && $(MAKE) run

# ── ログ監視 ──────────────────────────────────────────────
log: ## アプリのログをリアルタイム監視
	xcrun simctl spawn "$(SIM_UDID)" log stream \
	  --predicate 'subsystem == "$(BUNDLE_ID)" OR processImagePath CONTAINS "NuruNuru"' \
	  --style compact

log-all: ## シミュレータの全ログ（フィルタなし）
	xcrun simctl spawn "$(SIM_UDID)" log stream --style compact

log-errors: ## エラー/フォルトのみ
	xcrun simctl spawn "$(SIM_UDID)" log stream \
	  --predicate 'subsystem == "$(BUNDLE_ID)"' \
	  --style compact --level error

# ── スクリーンショット/動画 ──────────────────────────────
screenshot: ## スクリーンショットを ~/Desktop に保存
	xcrun simctl io "$(SIM_UDID)" screenshot ~/Desktop/nurunuru-$$(date +%Y%m%d-%H%M%S).png
	@echo "Saved to ~/Desktop"

record: ## 画面録画開始 (Ctrl+C で停止)
	xcrun simctl io "$(SIM_UDID)" recordVideo ~/Desktop/nurunuru-$$(date +%Y%m%d-%H%M%S).mp4

# ── デバッグユーティリティ ────────────────────────────────
status: ## シミュレータ状態確認
	@echo "=== Available Simulators ==="
	xcrun simctl list devices available | grep -E "iPhone 17|iPad"
	@echo ""
	@echo "=== Build Log (last 30 lines) ==="
	@tail -30 /tmp/xcode-build.log 2>/dev/null || echo "(no build log yet)"

push-notif: ## テスト通知を送信 (payload.json が必要)
	xcrun simctl push "$(SIM_UDID)" $(BUNDLE_ID) payload.json

privacy-reset: ## プライバシー権限をリセット
	xcrun simctl privacy "$(SIM_UDID)" reset all $(BUNDLE_ID)

# ── クリーンアップ ────────────────────────────────────────
clean: ## DerivedData 削除
	rm -rf $(BUILD_DIR)
	@echo "Cleaned $(BUILD_DIR)"

clean-all: clean ## DerivedData + シミュレータキャッシュ削除
	xcrun simctl delete unavailable
	@echo "Deleted unavailable simulators"

reset: ## アプリのデータをリセット（再インストール）
	xcrun simctl uninstall "$(SIM_UDID)" $(BUNDLE_ID)
	@echo "Uninstalled $(BUNDLE_ID)"

ffi-xcframework:
	cd ../rust-engine/nurunuru-ffi/bindgen && make xcframework

ffi-package-check:
	cd ../rust-engine/nurunuru-ffi/ios && swift package describe
