import SwiftUI
import UniformTypeIdentifiers

// MARK: - Private helpers

private let kindLabels: [Int: String] = [
    0:     "プロフィール",
    1:     "テキスト投稿",
    3:     "フォローリスト",
    5:     "削除",
    6:     "リポスト",
    7:     "リアクション",
    10000: "ミュートリスト",
    10002: "リレーリスト",
    30023: "長文記事"
]

private func kindLabel(_ kind: Int) -> String {
    kindLabels[kind] ?? "kind: \(kind)"
}

private func eventStats(_ events: [NostrEvent]) -> [(kind: Int, count: Int)] {
    var stats: [Int: Int] = [:]
    for e in events { stats[e.kind, default: 0] += 1 }
    return stats.sorted { $0.value > $1.value }.map { (kind: $0.key, count: $0.value) }
}

// MARK: - EventBackupView

/// バックアップ mini-app — export / import user's Nostr events.
/// Mirrors Android EventBackupSettings.kt.
struct EventBackupView: View {

    let repository: NostrRepository
    let pubkeyHex:  String

    @Environment(\.nuruTheme) private var theme

    // Tab
    @State private var activeTab: Int = 0  // 0 = エクスポート, 1 = インポート

    // Export state
    @State private var exporting             = false
    @State private var exportProgressFetched = 0
    @State private var exportProgressBatch   = 0
    @State private var exportedEvents: [NostrEvent] = []
    @State private var exportError: String?  = nil
    @State private var showShare             = false
    @State private var exportURL: URL?       = nil

    // Import state
    @State private var showFilePicker            = false
    @State private var parsedEvents: [NostrEvent] = []
    @State private var importing                 = false
    @State private var importProgressCurrent     = 0
    @State private var importProgressTotal       = 0
    @State private var importProgressSuccess     = 0
    @State private var importProgressFailed      = 0
    @State private var importResult: ImportResult? = nil
    @State private var importError: String?      = nil

    var body: some View {
        ScrollView {
            VStack(spacing: NuruSpacing.space4) {

                // ── Tab Selector ──────────────────────────────────────────
                Picker("", selection: $activeTab) {
                    Text("エクスポート").tag(0)
                    Text("インポート").tag(1)
                }
                .pickerStyle(.segmented)

                if activeTab == 0 {
                    exportTab
                } else {
                    importTab
                }
            }
            .padding(NuruSpacing.space4)
        }
        .background(theme.bgPrimary)
        // Share sheet
        .sheet(isPresented: $showShare) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
        // File importer for import tab
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.json, .text],
            allowsMultipleSelection: false
        ) { result in
            Task { await handleFileImport(result) }
        }
    }

    // MARK: - Export Tab

    @ViewBuilder
    private var exportTab: some View {
        VStack(spacing: NuruSpacing.space4) {

            Text("すべてのイベントをJSON Lines形式でバックアップできます。")
                .font(NuruFont.bodySmall())
                .foregroundStyle(theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // "取得" button — visible only when no events yet and not fetching
            if exportedEvents.isEmpty && !exporting {
                Button { Task { await doFetch() } } label: {
                    Label("イベントを取得", systemImage: "arrow.down.circle")
                        .font(NuruFont.buttonMedium())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(NuruColors.lineGreen)
                        .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusFull))
                }
            }

            // Fetch progress
            if exporting {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(NuruColors.lineGreen)
                        .frame(width: 20, height: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("イベントを取得中...")
                            .font(NuruFont.bodyMedium())
                            .foregroundStyle(theme.textPrimary)
                        Text("\(exportProgressFetched)件取得 (バッチ \(exportProgressBatch))")
                            .font(NuruFont.bodySmall())
                            .foregroundStyle(theme.textSecondary)
                    }
                    Spacer()
                }
                .padding(NuruSpacing.space4)
                .background(theme.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusLg))
            }

            // Export error
            if let err = exportError {
                Text(err)
                    .font(NuruFont.bodySmall())
                    .foregroundStyle(NuruColors.colorError)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(NuruSpacing.space3)
                    .background(NuruColors.colorError.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
            }

            // Stats card + save buttons — visible after successful fetch
            if !exportedEvents.isEmpty {
                VStack(spacing: NuruSpacing.space3) {

                    // Stats card
                    VStack(alignment: .leading, spacing: NuruSpacing.space2) {
                        Text("\(exportedEvents.count)件のイベント")
                            .font(NuruFont.bodyMedium())
                            .fontWeight(.bold)
                            .foregroundStyle(theme.textPrimary)
                            .padding(.bottom, NuruSpacing.space2)

                        let stats = eventStats(exportedEvents)
                        ForEach(stats.prefix(8), id: \.kind) { item in
                            HStack {
                                Text(kindLabel(item.kind))
                                    .font(NuruFont.bodySmall())
                                    .foregroundStyle(theme.textSecondary)
                                Spacer()
                                Text("\(item.count)")
                                    .font(NuruFont.bodySmall())
                                    .foregroundStyle(theme.textSecondary)
                            }
                        }
                        if stats.count > 8 {
                            Text("...他 \(stats.count - 8) 種類")
                                .font(NuruFont.bodySmall())
                                .foregroundStyle(theme.textSecondary)
                                .padding(.top, 2)
                        }

                        let protectedCount = exportedEvents.filter { $0.isProtected }.count
                        if protectedCount > 0 {
                            Text("\(protectedCount)件の保護イベント (NIP-70) を含む")
                                .font(NuruFont.bodySmall())
                                .foregroundStyle(theme.textSecondary)
                                .padding(.top, NuruSpacing.space2)
                        }
                    }
                    .padding(NuruSpacing.space4)
                    .frame(maxWidth: .infinity)
                    .background(theme.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusLg))

                    // Save (Share) button
                    Button { Task { await doSave() } } label: {
                        Label("JSONファイルを保存", systemImage: "arrow.down.to.line")
                            .font(NuruFont.buttonMedium())
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(NuruColors.lineGreen)
                            .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusFull))
                    }

                    // Re-fetch button
                    Button {
                        exportedEvents = []
                        exportError    = nil
                    } label: {
                        Text("再取得")
                            .font(NuruFont.bodyMedium())
                            .foregroundStyle(theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                }
            }
        }
    }

    // MARK: - Import Tab

    @ViewBuilder
    private var importTab: some View {
        VStack(spacing: NuruSpacing.space4) {

            Text("JSONまたはJSON Linesファイルからイベントをインポートできます。自分のイベントのみがリレーに送信されます。")
                .font(NuruFont.bodySmall())
                .foregroundStyle(theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // File picker drop zone
            if parsedEvents.isEmpty && !importing {
                Button { showFilePicker = true } label: {
                    VStack(spacing: NuruSpacing.space3) {
                        Image(systemName: "doc.badge.arrow.up")
                            .font(.system(size: 32))
                            .foregroundStyle(theme.textSecondary)
                        Text("タップしてファイルを選択")
                            .font(NuruFont.bodyMedium())
                            .foregroundStyle(theme.textSecondary)
                        Text("JSON / JSON Lines形式")
                            .font(NuruFont.bodySmall())
                            .foregroundStyle(theme.textSecondary.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .background(theme.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusLg))
                    .overlay(
                        RoundedRectangle(cornerRadius: NuruSpacing.radiusLg)
                            .strokeBorder(theme.textSecondary.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            // Import error
            if let err = importError {
                Text(err)
                    .font(NuruFont.bodySmall())
                    .foregroundStyle(NuruColors.colorError)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(NuruSpacing.space3)
                    .background(NuruColors.colorError.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
            }

            // Parsed events preview + import action
            if !parsedEvents.isEmpty && importResult == nil {
                VStack(spacing: NuruSpacing.space3) {

                    // Stats card
                    VStack(alignment: .leading, spacing: NuruSpacing.space2) {
                        Text("\(parsedEvents.count)件のイベント")
                            .font(NuruFont.bodyMedium())
                            .fontWeight(.bold)
                            .foregroundStyle(theme.textPrimary)
                            .padding(.bottom, NuruSpacing.space2)

                        let stats = eventStats(parsedEvents)
                        ForEach(stats.prefix(6), id: \.kind) { item in
                            HStack {
                                Text(kindLabel(item.kind))
                                    .font(NuruFont.bodySmall())
                                    .foregroundStyle(theme.textSecondary)
                                Spacer()
                                Text("\(item.count)")
                                    .font(NuruFont.bodySmall())
                                    .foregroundStyle(theme.textSecondary)
                            }
                        }

                        // Other users' events warning
                        let otherCount = parsedEvents.filter { $0.pubkey != pubkeyHex }.count
                        if otherCount > 0 {
                            Text("\(otherCount)件は他のユーザーのイベントです（インポート時にスキップされます）")
                                .font(NuruFont.bodySmall())
                                .foregroundStyle(Color(red: 0.52, green: 0.39, blue: 0.02))
                                .padding(NuruSpacing.space2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.yellow.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusSm))
                                .padding(.top, NuruSpacing.space2)
                        }

                        let protectedCount = parsedEvents.filter { $0.isProtected }.count
                        if protectedCount > 0 {
                            Text("\(protectedCount)件の保護イベント (NIP-70)")
                                .font(NuruFont.bodySmall())
                                .foregroundStyle(theme.textSecondary)
                                .padding(.top, NuruSpacing.space2)
                        }
                    }
                    .padding(NuruSpacing.space4)
                    .frame(maxWidth: .infinity)
                    .background(theme.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusLg))

                    // Progress bar while importing
                    if importing {
                        VStack(alignment: .leading, spacing: NuruSpacing.space2) {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .tint(NuruColors.lineGreen)
                                    .frame(width: 20, height: 20)
                                Text("インポート中...")
                                    .font(NuruFont.bodyMedium())
                                    .foregroundStyle(theme.textPrimary)
                            }
                            .padding(.bottom, NuruSpacing.space2)

                            ProgressView(
                                value: Double(importProgressCurrent),
                                total: Double(max(importProgressTotal, 1))
                            )
                            .tint(NuruColors.lineGreen)

                            Text("\(importProgressCurrent) / \(importProgressTotal) (\(importProgressSuccess)件成功)")
                                .font(NuruFont.bodySmall())
                                .foregroundStyle(theme.textSecondary)
                                .padding(.top, NuruSpacing.space1)
                        }
                        .padding(NuruSpacing.space4)
                        .background(theme.bgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusLg))

                    } else {
                        // Import + Clear buttons
                        HStack(spacing: NuruSpacing.space3) {
                            Button { Task { await doImport() } } label: {
                                Text("インポート開始")
                                    .font(NuruFont.buttonMedium())
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                                    .background(NuruColors.lineGreen)
                                    .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusFull))
                            }
                            Button {
                                parsedEvents = []
                                importError  = nil
                            } label: {
                                Text("消去")
                                    .font(NuruFont.buttonMedium())
                                    .foregroundStyle(theme.textSecondary)
                                    .frame(width: 80)
                                    .frame(height: 48)
                                    .background(theme.bgSecondary)
                                    .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusFull))
                            }
                        }
                    }
                }
            }

            // Import result card
            if let result = importResult {
                VStack(alignment: .leading, spacing: NuruSpacing.space4) {
                    Text("インポート完了")
                        .font(NuruFont.bodyMedium())
                        .fontWeight(.bold)
                        .foregroundStyle(theme.textPrimary)

                    HStack(spacing: NuruSpacing.space3) {
                        ImportResultCard(
                            value: "\(result.success)",
                            label: "成功",
                            color: Color(red: 0.29, green: 0.68, blue: 0.31)
                        )
                        ImportResultCard(
                            value: "\(result.failed)",
                            label: "失敗",
                            color: Color(red: 0.96, green: 0.26, blue: 0.21)
                        )
                        ImportResultCard(
                            value: "\(result.skipped)",
                            label: "スキップ",
                            color: Color(red: 0.46, green: 0.46, blue: 0.46)
                        )
                    }

                    if result.skipped > 0 {
                        Text("保護イベント（NIP-70）または他のユーザーのイベントはスキップされました")
                            .font(NuruFont.bodySmall())
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                .padding(NuruSpacing.space4)
                .frame(maxWidth: .infinity)
                .background(theme.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusLg))

                Button {
                    parsedEvents = []
                    importResult = nil
                    importError  = nil
                } label: {
                    Text("別のファイルをインポート")
                        .font(NuruFont.buttonMedium())
                        .foregroundStyle(theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(theme.bgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusFull))
                }
            }
        }
    }

    // MARK: - Actions

    /// `fetchAllUserEvents` でページネーション取得し進捗を表示する。
    @MainActor
    private func doFetch() async {
        exporting             = true
        exportError           = nil
        exportProgressFetched = 0
        exportProgressBatch   = 0
        exportedEvents        = []

        let events = await repository.fetchAllUserEvents(pubkey: pubkeyHex) { fetched, batch in
            // onProgress は同期クロージャ — MainActor へディスパッチして UI 更新
            Task { @MainActor in
                self.exportProgressFetched = fetched
                self.exportProgressBatch   = batch
            }
        }

        exportedEvents = events
        if events.isEmpty {
            exportError = "エクスポートするイベントがありません"
        }
        exporting = false
    }

    /// 取得済みイベントを JSON Lines ファイルに書き出して ShareSheet を開く。
    @MainActor
    private func doSave() async {
        guard !exportedEvents.isEmpty else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            // JSON Lines: 1行1イベント
            let lines = try exportedEvents.map {
                try String(data: encoder.encode($0), encoding: .utf8) ?? ""
            }
            let jsonl   = lines.joined(separator: "\n")
            let dateStr = Int(Date().timeIntervalSince1970)
            let tmpURL  = FileManager.default.temporaryDirectory
                .appendingPathComponent("nostr-backup-\(pubkeyHex.prefix(8))-\(dateStr).jsonl")
            try jsonl.write(to: tmpURL, atomically: true, encoding: .utf8)
            exportURL = tmpURL
            showShare = true
        } catch {
            exportError = "ファイルの作成に失敗しました: \(error.localizedDescription)"
        }
    }

    /// fileImporter コールバック — 選択ファイルを読み込んで `parsedEvents` に格納する。
    private func handleFileImport(_ result: Result<[URL], Error>) async {
        switch result {
        case .failure(let err):
            await MainActor.run {
                importError = "ファイルの読み込みに失敗しました: \(err.localizedDescription)"
            }
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                _ = url.startAccessingSecurityScopedResource()
                defer { url.stopAccessingSecurityScopedResource() }

                let content = try String(contentsOf: url, encoding: .utf8)
                let events  = parseEventsFromString(content)
                await MainActor.run {
                    parsedEvents = events
                    importError  = events.isEmpty ? "有効なイベントが見つかりませんでした" : nil
                    importResult = nil
                }
            } catch {
                await MainActor.run {
                    importError  = "ファイルの読み込みに失敗しました: \(error.localizedDescription)"
                    parsedEvents = []
                }
            }
        }
    }

    /// JSON Lines（1行1イベント）または JSON 配列のどちらでも受け付けるパーサー。
    private func parseEventsFromString(_ content: String) -> [NostrEvent] {
        let decoder = JSONDecoder()

        // 1. JSON Lines として試みる
        let lines = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var events: [NostrEvent] = []
        for line in lines {
            if let data  = line.data(using: .utf8),
               let event = try? decoder.decode(NostrEvent.self, from: data) {
                events.append(event)
            }
        }
        if !events.isEmpty { return events }

        // 2. JSON 配列にフォールバック（Android JSON エクスポートとの互換性）
        if let data = content.data(using: .utf8),
           let arr  = try? decoder.decode([NostrEvent].self, from: data) {
            return arr
        }

        return []
    }

    /// `importEventsToRelays` を呼び出してプログレスを表示し結果を格納する。
    @MainActor
    private func doImport() async {
        guard !parsedEvents.isEmpty else { return }

        importing             = true
        importError           = nil
        importResult          = nil
        importProgressCurrent = 0
        importProgressTotal   = parsedEvents.count
        importProgressSuccess = 0
        importProgressFailed  = 0

        let result = await repository.importEventsToRelays(events: parsedEvents) { current, total, success, failed in
            Task { @MainActor in
                self.importProgressCurrent = current
                self.importProgressTotal   = total
                self.importProgressSuccess = success
                self.importProgressFailed  = failed
            }
        }

        importResult = result
        importing    = false
    }
}

// MARK: - ImportResultCard

private struct ImportResultCard: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - UIActivityViewController wrapper

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
