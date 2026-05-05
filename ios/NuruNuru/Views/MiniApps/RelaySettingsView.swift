import SwiftUI
import CoreLocation

// MARK: - Relay Settings View (NIP-65 Kind 10002)

/// NIP-65 リレーリスト管理ミニアプリ。
/// 地域選択・GPS自動検出・最寄りリレー推薦を含む。
/// Android `SettingsScreen.kt` の `RelaySettingsViewContent` に対応。
struct RelaySettingsView: View {

    let repository:   NostrRepository
    let prefs:        AppPreferences
    let pubkeyHex:    String
    var connectionVM: ConnectionViewModel? = nil

    @Environment(\.nuruTheme) private var theme

    @State private var currentRelays:    [Nip65Relay] = []
    @State private var nearestRelays:    [RelayInfoWithDistance] = []
    @State private var selectedRegionId: String? = nil
    @State private var userGeohash:      String? = nil
    @State private var mainRelayState:   String  = "wss://yabu.me"
    @State private var detectingLocation = false
    @State private var isSaving          = false
    @State private var isLoading         = true
    @State private var saveSuccess       = false
    @State private var saveError:        String? = nil
    @State private var showError         = false
    @State private var showAdd           = false
    @State private var newRelay          = ""
    @State private var showRegionPicker  = false
    @State private var advancedExpanded  = false
    @State private var manualRelayUrl    = ""
    @State private var newRelayRead      = true
    @State private var newRelayWrite     = true
    /// Per-relay connection states (polled periodically)
    @State private var relayStates:      [String: NostrClient.ConnectionState] = [:]
    @State private var mlsKeyPackageRelays: [String] = []
    @State private var mlsInboxRelays:      [String] = []
    @State private var manualKeyPackageRelayUrl = ""
    @State private var manualInboxRelayUrl      = ""

    @StateObject private var locationHelper = LocationHelper()

    var body: some View {
        ScrollView {
            VStack(spacing: NuruSpacing.space4) {
                // Main settings card
                mainSettingsCard

                // Nearest relays
                if !nearestRelays.isEmpty {
                    nearestRelaysCard
                }

                // Saved relays
                if !currentRelays.isEmpty {
                    savedRelaysCard
                }

                // Save button
                saveButton

                // Advanced settings
                advancedSettingsCard
            }
            .padding(NuruSpacing.space4)
        }
        .background(theme.bgPrimary)
        .task { await loadInitialState() }
        .task(id: "relay-poll") {
            // 5秒間隔で接続状態をリアルタイム更新（Android の色付きドットと同等）
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                relayStates = await repository.perRelayStates()
            }
        }
        .alert("保存エラー", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "リレーリストの保存に失敗しました")
        }
    }

    // MARK: - Main Settings Card

    private var mainSettingsCard: some View {
        VStack(alignment: .leading, spacing: NuruSpacing.space4) {
            Text("リレー設定")
                .font(NuruFont.titleMedium())
                .fontWeight(.bold)
                .foregroundStyle(theme.textPrimary)

            // Current status
            currentStatusBanner

            // Region selector
            regionSelector

            // GPS button
            gpsButton
        }
        .padding(NuruSpacing.space4)
        .background(
            RoundedRectangle(cornerRadius: NuruSpacing.radiusXl)
                .fill(theme.bgSecondary)
        )
    }

    private var currentStatusBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("現在の設定")
                .font(.system(size: 10))
                .foregroundStyle(theme.textTertiary)

            let regionName: String = {
                if let id = selectedRegionId,
                   let region = RelayDiscovery.regionCoordinates.first(where: { $0.id == id }) {
                    return region.name
                } else if userGeohash != nil {
                    return "GPS検出"
                }
                return "未設定"
            }()

            Text(regionName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.textPrimary)

            Text("おすすめリレー: \(mainRelayState.replacingOccurrences(of: "wss://", with: ""))")
                .font(.system(size: 10))
                .foregroundStyle(theme.textTertiary)
                .padding(.top, 2)
        }
        .padding(NuruSpacing.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: NuruSpacing.radiusLg)
                .fill(NuruColors.lineGreen.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: NuruSpacing.radiusLg)
                        .stroke(NuruColors.lineGreen, lineWidth: 1)
                )
        )
    }

    private var regionSelector: some View {
        VStack(alignment: .leading, spacing: NuruSpacing.space3) {
            Text("地域を選択")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.textSecondary)

            Menu {
                ForEach(RelayDiscovery.groupedRegions, id: \.0) { group, regions in
                    Section(group) {
                        ForEach(regions) { region in
                            Button(region.name) {
                                handleSelectRegion(region.id)
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    let selectedName: String = {
                        if let id = selectedRegionId,
                           let region = RelayDiscovery.regionCoordinates.first(where: { $0.id == id }) {
                            return region.name
                        }
                        return "地域を選択..."
                    }()
                    Text(selectedName)
                        .font(.system(size: 14))
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textTertiary)
                }
                .padding(NuruSpacing.space3)
                .background(
                    RoundedRectangle(cornerRadius: NuruSpacing.radiusLg)
                        .stroke(theme.borderColor, lineWidth: 1)
                )
            }
        }
    }

    private var gpsButton: some View {
        Button {
            requestLocation()
        } label: {
            HStack(spacing: NuruSpacing.space2) {
                if detectingLocation {
                    ProgressView()
                        .controlSize(.small)
                    Text("位置情報を取得中...")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                } else {
                    Image(systemName: "location")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.textSecondary)
                    Text("GPSで自動検出")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: NuruSpacing.radiusLg)
                    .fill(theme.bgTertiary)
            )
        }
        .buttonStyle(.plain)
        .disabled(detectingLocation)
    }

    // MARK: - Nearest Relays Card

    private var nearestRelaysCard: some View {
        VStack(alignment: .leading, spacing: NuruSpacing.space3) {
            Text("最寄りのリレー")
                .font(.system(size: 10))
                .foregroundStyle(theme.textTertiary)

            ForEach(Array(nearestRelays.prefix(5))) { relay in
                let isInNip65 = currentRelays.contains(where: { $0.url == relay.info.url })
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(relay.info.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.textPrimary)
                        Text("\(relay.info.region) · \(RelayDiscovery.formatDistance(relay.distance))")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.textTertiary)
                    }
                    Spacer()
                    Button {
                        toggleRelayInList(relay)
                    } label: {
                        Image(systemName: isInNip65 ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(isInNip65 ? NuruColors.lineGreen : theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, NuruSpacing.space3)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: NuruSpacing.radiusLg)
                        .fill(theme.bgTertiary)
                )
            }
        }
        .padding(NuruSpacing.space4)
        .background(
            RoundedRectangle(cornerRadius: NuruSpacing.radiusXl)
                .fill(theme.bgSecondary)
        )
    }

    // MARK: - Saved Relays Card

    private var savedRelaysCard: some View {
        VStack(alignment: .leading, spacing: NuruSpacing.space3) {
            Text("保存済みリレー")
                .font(.system(size: 10))
                .foregroundStyle(theme.textTertiary)

            ForEach(currentRelays) { relay in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: NuruSpacing.space2) {
                            Circle()
                                .fill(relayDotColor(relay.url))
                                .frame(width: 8, height: 8)
                            Text(relay.url.replacingOccurrences(of: "wss://", with: ""))
                                .font(.system(size: 12))
                                .foregroundStyle(theme.textPrimary)
                                .lineLimit(1)
                        }
                        HStack(spacing: 4) {
                            if relay.permission == .read || relay.permission == .readWrite {
                                permissionBadge("read", color: NuruColors.lineGreen)
                            }
                            if relay.permission == .write || relay.permission == .readWrite {
                                permissionBadge("write", color: Color(hex: "#9C27B0"))
                            }
                        }
                    }
                    Spacer()
                    Button {
                        currentRelays.removeAll { $0.url == relay.url }
                        prefs.nip65Relays = currentRelays
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, NuruSpacing.space3)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: NuruSpacing.radiusLg)
                        .fill(theme.bgTertiary)
                )
            }
        }
        .padding(NuruSpacing.space4)
        .background(
            RoundedRectangle(cornerRadius: NuruSpacing.radiusXl)
                .fill(theme.bgSecondary)
        )
    }

    private func permissionBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.15))
            )
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button {
            Task { await saveRelayList() }
        } label: {
            HStack {
                Spacer()
                if isSaving {
                    ProgressView().tint(.white)
                } else if saveSuccess {
                    Label("保存しました", systemImage: "checkmark.circle.fill")
                        .fontWeight(.bold)
                } else {
                    Text("リレーリストを保存 (Kind 10002)")
                        .fontWeight(.bold)
                }
                Spacer()
            }
            .padding(.vertical, NuruSpacing.space3)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: NuruSpacing.radiusLg)
                    .fill(currentRelays.isEmpty || isSaving
                          ? NuruColors.lineGreen.opacity(0.4)
                          : NuruColors.lineGreen)
            )
        }
        .buttonStyle(.plain)
        .disabled(currentRelays.isEmpty || isSaving)
    }

    // MARK: - Advanced Settings Card (mirrors Android 高度な設定)

    @State private var loadingNip65 = false

    private var advancedSettingsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Expand/collapse header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { advancedExpanded.toggle() }
            } label: {
                HStack {
                    Text("高度な設定")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Image(systemName: advancedExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textTertiary)
                }
                .padding(NuruSpacing.space4)
            }
            .buttonStyle(.plain)

            if advancedExpanded {
                VStack(alignment: .leading, spacing: NuruSpacing.space4) {
                    // NIP-65 explanation
                    nip65Explanation

                    // Load NIP-65 relay list button
                    loadNip65Button

                    // MLS / Marmot / WhiteNoise relay lists
                    mlsRelaySettings

                    // Per-relay read/write toggles
                    if !currentRelays.isEmpty {
                        relayDetailSettings
                    }

                    // Manual relay add
                    manualRelayAdd
                }
                .padding(.horizontal, NuruSpacing.space4)
                .padding(.bottom, NuruSpacing.space4)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: NuruSpacing.radiusXl)
                .fill(theme.bgSecondary)
        )
    }

    private var nip65Explanation: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("アウトボックスモデル (NIP-65)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.textPrimary)
            Text("read: 受信用リレー。他のユーザーがあなた宛のメンションをここに送信します。\nwrite: 送信用リレー。あなたの投稿がここに発行されます。")
                .font(.system(size: 11))
                .foregroundStyle(theme.textSecondary)
        }
        .padding(NuruSpacing.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: NuruSpacing.radiusLg)
                .fill(theme.bgTertiary)
        )
    }

    private var loadNip65Button: some View {
        Button {
            loadingNip65 = true
            Task {
                let relays = await repository.fetchRelayList(pubkey: pubkeyHex)
                if !relays.isEmpty {
                    let newList = Array(relays.prefix(10))
                    currentRelays = newList
                    prefs.nip65Relays = newList
                }
                loadingNip65 = false
            }
        } label: {
            HStack(spacing: NuruSpacing.space2) {
                if loadingNip65 {
                    ProgressView().controlSize(.small)
                }
                Text("自分のリレーリストを読み込む")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: NuruSpacing.radiusLg)
                    .fill(theme.bgTertiary)
            )
        }
        .buttonStyle(.plain)
        .disabled(loadingNip65)
    }


    private var mlsRelaySettings: some View {
        VStack(alignment: .leading, spacing: NuruSpacing.space3) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MLS / WhiteNoise リレー")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                Text("KeyPackage relays は招待用KeyPackage(30443/443/10051)を置く場所、Marmot Inbox relays はWelcome/MLS受信用(10050)です。トーク画面はMarmot MLS専用で、NIP-17メッセージは表示しません。")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(NuruSpacing.space3)
            .background(RoundedRectangle(cornerRadius: NuruSpacing.radiusLg).fill(theme.bgTertiary))

            relayListEditor(
                title: "Key Package Relays (kind:10051)",
                relays: $mlsKeyPackageRelays,
                manualUrl: $manualKeyPackageRelayUrl,
                defaultRelays: [
                    "wss://relay.damus.io",
                    "wss://relay.primal.net",
                    "wss://nos.lol",
                    "wss://relay.nostr.wirednet.jp",
                    "wss://yabu.me",
                    "wss://r.kojira.io"
                ],
                onSave: { prefs.mlsKeyPackageRelays = mlsKeyPackageRelays }
            )

            relayListEditor(
                title: "Marmot Inbox Relays (kind:10050)",
                relays: $mlsInboxRelays,
                manualUrl: $manualInboxRelayUrl,
                defaultRelays: ["wss://yabu.me", "wss://r.kojira.io"],
                onSave: { prefs.mlsInboxRelays = mlsInboxRelays }
            )
        }
    }

    private func relayListEditor(
        title: String,
        relays: Binding<[String]>,
        manualUrl: Binding<String>,
        defaultRelays: [String],
        onSave: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: NuruSpacing.space2) {
            HStack {
                Text(title)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textTertiary)
                Spacer()
                Button("標準") {
                    relays.wrappedValue = defaultRelays
                    onSave()
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NuruColors.lineGreen)
            }

            ForEach(relays.wrappedValue, id: \.self) { relay in
                HStack {
                    Circle()
                        .fill(relayDotColor(relay))
                        .frame(width: 8, height: 8)
                    Text(relay.replacingOccurrences(of: "wss://", with: ""))
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        relays.wrappedValue.removeAll { $0 == relay }
                        onSave()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, NuruSpacing.space3)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: NuruSpacing.radiusLg).fill(theme.bgTertiary))
            }

            HStack {
                TextField("wss://relay.example.com", text: manualUrl)
                    .font(.system(size: 12))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(NuruSpacing.space3)
                    .background(RoundedRectangle(cornerRadius: NuruSpacing.radiusLg).stroke(theme.borderColor, lineWidth: 1))
                Button("追加") {
                    let url = manualUrl.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard url.hasPrefix("wss://") || url.hasPrefix("ws://") else { return }
                    var list = [url] + relays.wrappedValue.filter { $0 != url }
                    if list.count > 10 { list = Array(list.prefix(10)) }
                    relays.wrappedValue = list
                    manualUrl.wrappedValue = ""
                    onSave()
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, NuruSpacing.space3)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: NuruSpacing.radiusLg).fill(NuruColors.lineGreen))
            }
        }
    }

    private var relayDetailSettings: some View {
        VStack(alignment: .leading, spacing: NuruSpacing.space2) {
            Text("リレー詳細設定")
                .font(.system(size: 10))
                .foregroundStyle(theme.textTertiary)

            ForEach(Array(currentRelays.enumerated()), id: \.element.url) { index, relay in
                VStack(alignment: .leading, spacing: 6) {
                    Text(relay.url.replacingOccurrences(of: "wss://", with: ""))
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 0) {
                        Toggle("read", isOn: Binding(
                            get: { relay.permission == .read || relay.permission == .readWrite },
                            set: { newVal in
                                var updated = currentRelays
                                let wasWrite = relay.permission == .write || relay.permission == .readWrite
                                let newPerm: RelayPermission = newVal
                                    ? (wasWrite ? .readWrite : .read)
                                    : (wasWrite ? .write : .read)
                                updated[index] = Nip65Relay(url: relay.url, permission: newPerm)
                                currentRelays = updated
                                prefs.nip65Relays = updated
                            }
                        ))
                        .toggleStyle(SwitchToggleStyle(tint: NuruColors.lineGreen))
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)

                        Spacer().frame(width: 20)

                        Toggle("write", isOn: Binding(
                            get: { relay.permission == .write || relay.permission == .readWrite },
                            set: { newVal in
                                var updated = currentRelays
                                let wasRead = relay.permission == .read || relay.permission == .readWrite
                                let newPerm: RelayPermission = newVal
                                    ? (wasRead ? .readWrite : .write)
                                    : (wasRead ? .read : .write)
                                updated[index] = Nip65Relay(url: relay.url, permission: newPerm)
                                currentRelays = updated
                                prefs.nip65Relays = updated
                            }
                        ))
                        .toggleStyle(SwitchToggleStyle(tint: NuruColors.lineGreen))
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)

                        Spacer()

                        Button {
                            currentRelays.removeAll { $0.url == relay.url }
                            prefs.nip65Relays = currentRelays
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 14))
                                .foregroundStyle(theme.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 32, height: 32)
                    }
                }
                .padding(.horizontal, NuruSpacing.space3)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: NuruSpacing.radiusLg)
                        .fill(theme.bgTertiary)
                )
            }
        }
    }

    private var manualRelayAdd: some View {
        VStack(alignment: .leading, spacing: NuruSpacing.space2) {
            Text("リレーを追加")
                .font(.system(size: 10))
                .foregroundStyle(theme.textTertiary)

            TextField("wss://relay.example.com", text: $manualRelayUrl)
                .font(.system(size: 12))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(NuruSpacing.space3)
                .background(
                    RoundedRectangle(cornerRadius: NuruSpacing.radiusLg)
                        .stroke(theme.borderColor, lineWidth: 1)
                )

            HStack {
                Toggle("read", isOn: $newRelayRead)
                    .toggleStyle(SwitchToggleStyle(tint: NuruColors.lineGreen))
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)

                Spacer().frame(width: 12)

                Toggle("write", isOn: $newRelayWrite)
                    .toggleStyle(SwitchToggleStyle(tint: NuruColors.lineGreen))
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)

                Spacer()

                Button {
                    let url = manualRelayUrl.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard (url.hasPrefix("wss://") || url.hasPrefix("ws://")),
                          (newRelayRead || newRelayWrite) else { return }
                    let perm: RelayPermission = (newRelayRead && newRelayWrite) ? .readWrite
                        : newRelayRead ? .read : .write
                    let newRelay = Nip65Relay(url: url, permission: perm)
                    var newList = [newRelay] + currentRelays.filter { $0.url != url }
                    if newList.count > 10 { newList = Array(newList.prefix(10)) }
                    currentRelays = newList
                    prefs.nip65Relays = newList
                    manualRelayUrl = ""
                } label: {
                    Text("追加")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, NuruSpacing.space3)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: NuruSpacing.radiusLg)
                                .fill(NuruColors.lineGreen)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    private func handleSelectRegion(_ regionId: String) {
        guard let region = RelayDiscovery.regionCoordinates.first(where: { $0.id == regionId }) else { return }

        let config: Nip65Config
        if regionId == "global" {
            let globalRelays = RelayDiscovery.gpsRelayDatabase
                .filter { $0.priority == 1 }
                .prefix(10)
                .map { RelayInfoWithDistance(info: $0, distance: 0) }
            config = Nip65Config(
                inbox: Array(globalRelays.prefix(4)),
                outbox: Array(globalRelays.prefix(5)),
                discover: RelayDiscovery.directoryRelays,
                combined: globalRelays.prefix(5).map { Nip65Relay(url: $0.info.url, permission: .readWrite) }
            )
        } else {
            config = RelayDiscovery.generateRelayListByLocation(userLat: region.lat, userLon: region.lon)
        }

        prefs.selectedRegionId = regionId
        prefs.userLat = region.lat
        prefs.userLon = region.lon
        prefs.userGeohash = regionId == "global" ? "global" : RelayDiscovery.encodeGeohash(lat: region.lat, lon: region.lon)
        prefs.nip65Relays = config.combined
        let newMain = config.combined.first(where: { $0.permission == .readWrite })?.url
            ?? config.combined.first?.url ?? "wss://yabu.me"
        prefs.mainRelay = newMain
        // Sync selectedRelays so connect() uses the new relay list
        prefs.selectedRelays = config.combined
            .filter { $0.permission == .write || $0.permission == .readWrite }
            .map(\.url)

        selectedRegionId = regionId
        userGeohash = prefs.userGeohash
        currentRelays = config.combined
        mainRelayState = newMain
        nearestRelays = Array(config.outbox)
    }

    private func requestLocation() {
        detectingLocation = true
        locationHelper.requestLocation { [self] result in
            detectingLocation = false
            switch result {
            case .success(let location):
                let lat = location.coordinate.latitude
                let lon = location.coordinate.longitude
                let geohash = RelayDiscovery.encodeGeohash(lat: lat, lon: lon)
                let config = RelayDiscovery.generateRelayListByLocation(userLat: lat, userLon: lon)

                prefs.userLat = lat
                prefs.userLon = lon
                prefs.userGeohash = geohash
                prefs.selectedRegionId = nil
                prefs.nip65Relays = config.combined
                let newMain = config.combined.first(where: { $0.permission == .readWrite })?.url
                    ?? config.combined.first?.url ?? "wss://yabu.me"
                prefs.mainRelay = newMain
                prefs.selectedRelays = config.combined.filter { $0.permission == .write || $0.permission == .readWrite }.map(\.url)

                userGeohash = geohash
                selectedRegionId = nil
                currentRelays = config.combined
                mainRelayState = newMain
                nearestRelays = Array(config.outbox)

            case .failure:
                break
            }
        }
    }

    private func toggleRelayInList(_ relay: RelayInfoWithDistance) {
        if let idx = currentRelays.firstIndex(where: { $0.url == relay.info.url }) {
            currentRelays.remove(at: idx)
        } else {
            let newRelay = Nip65Relay(url: relay.info.url, permission: .readWrite)
            currentRelays.insert(newRelay, at: 0)
            if currentRelays.count > 5 {
                currentRelays = Array(currentRelays.prefix(5))
            }
        }
        prefs.nip65Relays = currentRelays
    }

    private func loadInitialState() async {
        isLoading = true
        defer { isLoading = false }

        selectedRegionId = prefs.selectedRegionId
        userGeohash = prefs.userGeohash
        mainRelayState = prefs.mainRelay

        mlsKeyPackageRelays = prefs.mlsKeyPackageRelays.isEmpty ? [
            "wss://relay.damus.io", "wss://relay.primal.net", "wss://nos.lol",
            "wss://relay.nostr.wirednet.jp", "wss://yabu.me", "wss://r.kojira.io"
        ] : prefs.mlsKeyPackageRelays
        mlsInboxRelays = prefs.mlsInboxRelays.isEmpty ? ["wss://yabu.me", "wss://r.kojira.io"] : prefs.mlsInboxRelays

        // Load NIP-65 relays
        let stored = prefs.nip65Relays
        if stored.isEmpty {
            let fetched = await repository.fetchRelayList(pubkey: pubkeyHex)
            if fetched.isEmpty {
                currentRelays = prefs.selectedRelays.map { Nip65Relay(url: $0, permission: .readWrite) }
            } else {
                currentRelays = fetched
            }
        } else {
            currentRelays = stored
        }

        // Compute nearest relays
        if let id = selectedRegionId,
           let region = RelayDiscovery.regionCoordinates.first(where: { $0.id == id }) {
            let config = id == "global"
                ? Nip65Config(
                    inbox: [], outbox: RelayDiscovery.gpsRelayDatabase.filter { $0.priority == 1 }.prefix(10).map { RelayInfoWithDistance(info: $0, distance: 0) },
                    discover: [], combined: [])
                : RelayDiscovery.generateRelayListByLocation(userLat: region.lat, userLon: region.lon)
            nearestRelays = Array(config.outbox)
        } else if prefs.userLat != 0 {
            let config = RelayDiscovery.generateRelayListByLocation(userLat: prefs.userLat, userLon: prefs.userLon)
            nearestRelays = Array(config.outbox)
        }

        // Fetch per-relay connection states
        relayStates = await repository.perRelayStates()
    }

    private func saveRelayList() async {
        isSaving    = true
        saveSuccess = false
        defer { isSaving = false }

        do {
            try await repository.updateRelayList(relays: currentRelays)

            // Sync write/readWrite relays to AppPreferences
            let writeUrls = currentRelays
                .filter { $0.permission == .write || $0.permission == .readWrite }
                .map(\.url)
            if !writeUrls.isEmpty {
                prefs.selectedRelays = writeUrls
                prefs.mainRelay = writeUrls[0]
                mainRelayState = writeUrls[0]
            }
            prefs.mlsKeyPackageRelays = mlsKeyPackageRelays
            prefs.mlsInboxRelays = mlsInboxRelays

            saveSuccess = true
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            saveSuccess = false
        } catch {
            saveError = error.localizedDescription
            showError = true
        }
    }

    // MARK: - Connection Status

    private func relayDotColor(_ url: String) -> Color {
        // Use per-relay connection state if available
        if let state = relayStates[url] {
            switch state {
            case .connected:    return NuruColors.lineGreen
            case .connecting:   return Color(red: 0.98, green: 0.67, blue: 0.0)
            case .disconnected: return Color(white: 0.4)
            case .failed:       return Color.red
            }
        }
        // Fallback: gray (not connected / unknown)
        return Color(white: 0.4)
    }
}

// MARK: - LocationHelper

/// `CLLocationManager` wrapper that survives SwiftUI view redraws.
/// Must be `@StateObject` so the CLLocationManager + delegate stay alive
/// across the entire authorization → location flow.
private final class LocationHelper: NSObject, ObservableObject, CLLocationManagerDelegate {

    private lazy var manager: CLLocationManager = {
        let m = CLLocationManager()
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyHundredMeters
        return m
    }()

    private var completion: ((Result<CLLocation, Error>) -> Void)?
    private var didRespond = false

    func requestLocation(completion: @escaping (Result<CLLocation, Error>) -> Void) {
        self.completion = completion
        self.didRespond = false

        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            completion(.failure(NSError(domain: "location", code: -1,
                                        userInfo: [NSLocalizedDescriptionKey: "位置情報の権限が必要です"])))
        }
    }

    // Called after requestWhenInUseAuthorization()
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard completion != nil else { return }
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        } else if status == .denied || status == .restricted {
            guard !didRespond else { return }
            didRespond = true
            completion?(.failure(NSError(domain: "location", code: -2,
                                         userInfo: [NSLocalizedDescriptionKey: "位置情報の権限が拒否されました"])))
            completion = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !didRespond, let location = locations.last else { return }
        didRespond = true
        completion?(.success(location))
        completion = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard !didRespond else { return }
        didRespond = true
        completion?(.failure(error))
        completion = nil
    }
}
