import SwiftUI

// MARK: - Cache Type Configuration (mirrors Android CacheSettings CACHE_TYPES)

private struct CacheTypeConfig: Identifiable {
    let id: String
    let name: String
    let kinds: String
    let defaultTtlMs: Int
}

private let ttlPresets: [(label: String, ms: Int)] = [
    ("1時間",  3_600_000),
    ("6時間",  21_600_000),
    ("12時間", 43_200_000),
    ("1日",    86_400_000),
    ("3日",    259_200_000),
    ("7日",    604_800_000),
    ("30日",   2_592_000_000),
]

private let cacheTypes: [CacheTypeConfig] = [
    CacheTypeConfig(id: "profile",      name: "プロフィール",         kinds: "kind 0",             defaultTtlMs: 86_400_000),
    CacheTypeConfig(id: "timeline",     name: "タイムライン",         kinds: "kind 1, 30023",      defaultTtlMs: 86_400_000),
    CacheTypeConfig(id: "followlist",   name: "フォローリスト",       kinds: "kind 3",             defaultTtlMs: 86_400_000),
    CacheTypeConfig(id: "mutelist",     name: "ミュートリスト",       kinds: "kind 10000",         defaultTtlMs: 86_400_000),
    CacheTypeConfig(id: "notification", name: "通知",                 kinds: "kind 6, 7, 8, 9735", defaultTtlMs: 86_400_000),
    CacheTypeConfig(id: "emoji",        name: "絵文字",               kinds: "kind 10030",         defaultTtlMs: 86_400_000),
    CacheTypeConfig(id: "relay",        name: "リレーリスト",         kinds: "kind 10002",         defaultTtlMs: 86_400_000),
    CacheTypeConfig(id: "badge",        name: "プロフィールバッジ",   kinds: "kind 8, 30009",      defaultTtlMs: 86_400_000),
    CacheTypeConfig(id: "mls_groups",   name: "トーク（グループ）",   kinds: "kind 443 / 444",     defaultTtlMs: 2_592_000_000),
    CacheTypeConfig(id: "mls_messages", name: "トーク（メッセージ）", kinds: "kind 445",           defaultTtlMs: 2_592_000_000),
]

private func formatTtl(_ ms: Int) -> String {
    if let preset = ttlPresets.first(where: { $0.ms == ms }) { return preset.label }
    switch ms {
    case ..<3_600_000:    return "\(ms / 60_000)分"
    case ..<86_400_000:   return "\(ms / 3_600_000)時間"
    default:              return "\(ms / 86_400_000)日"
    }
}

private func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

// MARK: - CacheSettingsView (mirrors Android CacheSettings.kt)

/// キャッシュ設定 mini-app — cache stats, per-type toggle/TTL, clear controls.
/// Mirrors Android CacheSettings.kt with nostrdb size display.
struct CacheSettingsView: View {

    let repository: NostrRepository
    let prefs: AppPreferences
    var onMlsCacheCleared: () -> Void = {}

    @Environment(\.nuruTheme) private var theme
    @State private var stats: NostrCache.CacheStats = .init(entryCount: 0, memoryProfileCount: 0, memoryTimelineCount: 0)
    @State private var ndbSize: Int64 = 0
    @State private var appCacheSize: Int64 = 0
    @State private var clearing = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // MARK: - Stats Card
                statsCard

                // MARK: - Section Header
                VStack(alignment: .leading, spacing: 2) {
                    Text("キャッシュ設定")
                        .font(NuruFont.bodyMedium())
                        .foregroundStyle(theme.textPrimary)
                    Text("種類ごとにキャッシュの有効/無効と保持期間を設定できます。")
                        .font(NuruFont.labelSmall())
                        .foregroundStyle(theme.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)

                // MARK: - Per-type Rows
                ForEach(cacheTypes) { cfg in
                    CacheTypeRow(
                        cfg: cfg,
                        repository: repository,
                        prefs: prefs,
                        onMlsCacheCleared: onMlsCacheCleared,
                        refreshStats: refreshStats
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(theme.bgPrimary)
        .task {
            refreshStats()
            ndbSize = await Task.detached { NostrCache.nostrdbFileSize() }.value
            appCacheSize = await Task.detached { NostrCache.appCacheTotalSize() }.value
        }
    }

    // MARK: - Stats Card

    private var statsCard: some View {
        VStack(spacing: 8) {
            Text("現在のキャッシュ")
                .font(NuruFont.bodyMedium())
                .foregroundStyle(theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                statColumn(value: "\(stats.entryCount)", label: "アプリキャッシュ件数")
                Spacer()
                statColumn(value: "\(stats.memoryProfileCount)", label: "プロフィール(メモリ)")
                Spacer()
                // nostrdb (Rust FFI) が未統合の場合はアプリキャッシュサイズを表示
                let displaySize = ndbSize > 0 ? ndbSize : appCacheSize
                let displayLabel = ndbSize > 0 ? "nostrdb" : "キャッシュサイズ"
                statColumn(value: formatBytes(displaySize), label: displayLabel)
            }

            HStack(spacing: 8) {
                Button {
                    clearing = true
                    Task.detached { [repository] in
                        _ = repository.clearExpiredCache()
                        await MainActor.run { [self] in
                            refreshStats()
                            clearing = false
                        }
                    }
                } label: {
                    Text("期限切れを削除")
                        .font(NuruFont.labelSmall())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(clearing)

                Button {
                    clearing = true
                    Task { [repository] in
                        await repository.clearAllCache()
                        await MainActor.run { [self] in
                            refreshStats()
                            clearing = false
                            onMlsCacheCleared()
                        }
                    }
                } label: {
                    Text("全てクリア")
                        .font(NuruFont.labelSmall())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.94, green: 0.33, blue: 0.31)) // #EF5350
                .disabled(clearing)
            }
        }
        .padding(16)
        .background(theme.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(NuruFont.titleMedium())
                .foregroundStyle(NuruColors.lineGreen)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(theme.textTertiary)
        }
    }

    private func refreshStats() {
        stats = repository.getCacheStats()
    }
}

// MARK: - Per-Type Cache Row (mirrors Android CacheSettings items)

private struct CacheTypeRow: View {
    let cfg: CacheTypeConfig
    let repository: NostrRepository
    let prefs: AppPreferences
    var onMlsCacheCleared: () -> Void
    var refreshStats: () -> Void

    @Environment(\.nuruTheme) private var theme
    @State private var enabled: Bool = true
    @State private var selectedTtl: Int = 86_400_000
    @State private var count: Int = 0
    @State private var showTtlMenu = false

    var body: some View {
        VStack(spacing: 8) {
            // Top row: name + toggle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cfg.name)
                        .font(NuruFont.bodyMedium())
                        .foregroundStyle(theme.textPrimary)
                    Text(cfg.kinds)
                        .font(NuruFont.labelSmall())
                        .foregroundStyle(theme.textTertiary)
                }
                Spacer()
                Toggle("", isOn: $enabled)
                    .labelsHidden()
                    .tint(NuruColors.lineGreen)
                    .onChange(of: enabled) { _, newValue in
                        prefs.setCacheEnabled(cfg.id, newValue)
                        repository.applyCacheSettings()
                    }
            }

            // Bottom row: TTL + count + clear (visible only when enabled)
            if enabled {
                HStack {
                    // TTL selector
                    Menu {
                        ForEach(ttlPresets, id: \.ms) { preset in
                            Button {
                                selectedTtl = preset.ms
                                prefs.setCacheTtlMs(cfg.id, preset.ms)
                                repository.applyCacheSettings()
                            } label: {
                                HStack {
                                    Text(preset.label)
                                    if preset.ms == selectedTtl {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Text(formatTtl(selectedTtl))
                            .font(NuruFont.labelSmall())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(theme.textTertiary.opacity(0.4), lineWidth: 1)
                            )
                    }

                    Spacer()

                    // Count + clear button
                    HStack(spacing: 8) {
                        if count > 0 {
                            Text("\(count)件")
                                .font(NuruFont.labelSmall())
                                .foregroundStyle(theme.textTertiary)
                        }
                        Button {
                            Task {
                                await repository.clearCacheByType(cfg.id)
                                count = 0
                                refreshStats()
                                if cfg.id == "mls_groups" || cfg.id == "mls_messages" {
                                    onMlsCacheCleared()
                                }
                            }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 14))
                                .foregroundStyle(theme.textTertiary)
                        }
                        .frame(width: 32, height: 32)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(theme.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear {
            enabled = prefs.isCacheEnabled(cfg.id)
            selectedTtl = prefs.getCacheTtlMs(cfg.id, cfg.defaultTtlMs)
            count = repository.getCacheEntriesCount(cfg.id)
        }
    }
}
