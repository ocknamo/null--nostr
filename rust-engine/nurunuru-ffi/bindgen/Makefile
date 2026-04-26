# Makefile — nurunuru-ffi binding generation & cross-compilation targets
#
# Usage:
#   make swift          — generate Swift bindings (macOS host required)
#   make kotlin         — generate Kotlin/Android bindings
#   make ios-device     — compile static lib for iOS device (aarch64)
#   make ios-sim        — compile static lib for iOS Simulator (arm64 + x86_64)
#   make xcframework    — build XCFramework and sync generated Swift package source
#   make android-arm64  — compile .so for Android ARM64
#   make android-x86_64 — compile .so for Android x86_64 (emulator)
#   make android-all    — compile all Android ABI targets
#   make clean          — remove all generated output

# Makefile lives in .../nurunuru-ffi/bindgen/Makefile
# CRATE_DIR: .../nurunuru-ffi (parent of bindgen)
# WORKSPACE_DIR: .../rust-engine (cargo target dir lives here)
CRATE_DIR := $(shell cd "$(dir $(realpath $(firstword $(MAKEFILE_LIST))))/.." && pwd)
WORKSPACE_DIR := $(shell cd "$(CRATE_DIR)/.." && pwd)
BINDGEN_DIR := $(CRATE_DIR)/bindgen
IOS_DIR := $(CRATE_DIR)/ios
SWIFT_PACKAGE_SOURCES_DIR := $(IOS_DIR)/Sources/NuruNuru

.PHONY: swift kotlin ios-device ios-sim xcframework android-arm64 android-x86_64 android-all clean

# ─── Swift / iOS ──────────────────────────────────────────────────

swift:
	@bash $(BINDGEN_DIR)/gen_swift.sh

ios-device:
	@echo "==> Building for iOS device (aarch64-apple-ios, staticlib only)..."
	cd $(CRATE_DIR) && cargo rustc --release --lib --target aarch64-apple-ios --crate-type staticlib

ios-sim-arm64:
	@echo "==> Building for iOS Simulator ARM64 (aarch64-apple-ios-sim, staticlib only)..."
	cd $(CRATE_DIR) && cargo rustc --release --lib --target aarch64-apple-ios-sim --crate-type staticlib

ios-sim-x86:
	@echo "==> Building for iOS Simulator x86_64 (x86_64-apple-ios, staticlib only)..."
	cd $(CRATE_DIR) && cargo rustc --release --lib --target x86_64-apple-ios --crate-type staticlib

ios-sim: ios-sim-arm64 ios-sim-x86
	@echo "==> Creating fat library for iOS Simulator..."
	mkdir -p $(WORKSPACE_DIR)/target/ios-sim-fat/release
	lipo -create \
		$(WORKSPACE_DIR)/target/aarch64-apple-ios-sim/release/libuniffi_nurunuru.a \
		$(WORKSPACE_DIR)/target/x86_64-apple-ios/release/libuniffi_nurunuru.a \
		-output $(WORKSPACE_DIR)/target/ios-sim-fat/release/libuniffi_nurunuru.a
	@echo "==> Fat simulator library ready."

xcframework: ios-device ios-sim swift
	@echo "==> Creating XCFramework..."
	rm -rf $(IOS_DIR)/NuruNuruFFI.xcframework
	xcodebuild -create-xcframework \
		-library $(WORKSPACE_DIR)/target/aarch64-apple-ios/release/libuniffi_nurunuru.a \
		-headers $(BINDGEN_DIR)/swift-out \
		-library $(WORKSPACE_DIR)/target/ios-sim-fat/release/libuniffi_nurunuru.a \
		-headers $(BINDGEN_DIR)/swift-out \
		-output $(IOS_DIR)/NuruNuruFFI.xcframework
	@# Add module.modulemap alongside nurunuruFFI.modulemap in every XCFramework slice.
	@# Xcode's explicit-module build scanner auto-discovers only "module.modulemap";
	@# without it the nurunuruFFI Clang module is invisible and canImport(nurunuruFFI)
	@# returns false, causing RustBuffer / checksum "not in scope" compile errors.
	@for slice in $$(ls $(IOS_DIR)/NuruNuruFFI.xcframework | grep -v Info.plist); do \
		cp $(IOS_DIR)/NuruNuruFFI.xcframework/$$slice/Headers/nurunuruFFI.modulemap \
		   $(IOS_DIR)/NuruNuruFFI.xcframework/$$slice/Headers/module.modulemap; \
	done
	@echo "==> Added module.modulemap to all XCFramework slices"
	@mkdir -p $(SWIFT_PACKAGE_SOURCES_DIR)
	@cp $(BINDGEN_DIR)/swift-out/nurunuru.swift $(SWIFT_PACKAGE_SOURCES_DIR)/nurunuru_ffi.swift
	@echo "==> XCFramework written to ios/NuruNuruFFI.xcframework"
	@echo "==> Synced generated Swift bindings to ios/Sources/NuruNuru/nurunuru_ffi.swift"

# ─── Kotlin / Android ─────────────────────────────────────────────

kotlin:
	@bash $(BINDGEN_DIR)/gen_kotlin.sh

android-arm64:
	@echo "==> Building for Android ARM64 (aarch64-linux-android)..."
	cd $(CRATE_DIR) && cargo build --release --target aarch64-linux-android
	mkdir -p $(CRATE_DIR)/android/libs/arm64-v8a
	cp $(CRATE_DIR)/target/aarch64-linux-android/release/libuniffi_nurunuru.so \
	   $(CRATE_DIR)/android/libs/arm64-v8a/

android-x86_64:
	@echo "==> Building for Android x86_64 (x86_64-linux-android)..."
	cd $(CRATE_DIR) && cargo build --release --target x86_64-linux-android
	mkdir -p $(CRATE_DIR)/android/libs/x86_64
	cp $(CRATE_DIR)/target/x86_64-linux-android/release/libuniffi_nurunuru.so \
	   $(CRATE_DIR)/android/libs/x86_64/

android-all: android-arm64 android-x86_64
	@echo "==> All Android targets built. .so files are in android/libs/."

# ─── Clean ────────────────────────────────────────────────────────

clean:
	rm -rf $(BINDGEN_DIR)/swift-out $(BINDGEN_DIR)/kotlin-out
	rm -rf $(IOS_DIR)/NuruNuruFFI.xcframework
	@echo "Cleaned generated binding output. Run 'cargo clean' separately to remove compiled artifacts."