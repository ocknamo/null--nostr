import SwiftUI

/// ミュートリスト mini-app — manage muted users (public and private) and keywords.
/// Mirrors Android MuteList.kt — NIP-44 private/public mute distinction.
struct MuteListView: View {

    let repository: NostrRepository
    let pubkeyHex:  String

    @Environment(\.nuruTheme) private var theme
    @State private var publicMutes:    [String] = []
    @State private var privateMutes:   [String] = []
    @State private var mutedKeywords:  [String] = []
    @State private var profiles:       [String: UserProfile] = [:]
    @State private var isLoading:      Bool     = true
    @State private var showAddSheet:   Bool     = false
    @State private var addAsPrivate:   Bool     = true
    @State private var showAddKeyword: Bool     = false
    @State private var newPubkey:      String   = ""
    @State private var newKeyword:     String   = ""

    var body: some View {
        Group {
            if isLoading {
                VStack { Spacer(); ProgressView().tint(NuruColors.lineGreen); Spacer() }
                    .frame(maxWidth: .infinity)
            } else {
                List {
                    // MARK: Private Mutes (NIP-44 encrypted)
                    Section {
                        ForEach(privateMutes, id: \.self) { pubkey in
                            muteRow(pubkey: pubkey, isPrivate: true)
                        }
                        addButton(label: "非公開でユーザーを追加", isPrivate: true)
                    } header: {
                        Label("非公開ミュート (NIP-44 暗号化)", systemImage: "lock.fill")
                    }

                    // MARK: Public Mutes
                    Section {
                        ForEach(publicMutes, id: \.self) { pubkey in
                            muteRow(pubkey: pubkey, isPrivate: false)
                        }
                        addButton(label: "公開でユーザーを追加", isPrivate: false)
                    } header: {
                        Label("公開ミュート", systemImage: "eye.slash")
                    }

                    // MARK: Keywords
                    Section {
                        ForEach(mutedKeywords, id: \.self) { keyword in
                            HStack {
                                Image(systemName: "textformat")
                                    .foregroundStyle(theme.textTertiary)
                                Text(keyword)
                                    .font(NuruFont.bodyMedium())
                                    .foregroundStyle(theme.textPrimary)
                            }
                            .listRowBackground(theme.bgSecondary)
                            .swipeActions {
                                Button(role: .destructive) {
                                    mutedKeywords.removeAll { $0 == keyword }
                                    Task { await saveKeywords() }
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                            }
                        }
                        Button {
                            showAddKeyword = true
                        } label: {
                            Label("キーワードを追加", systemImage: "plus")
                                .font(NuruFont.bodyMedium())
                                .foregroundStyle(NuruColors.lineGreen)
                        }
                        .listRowBackground(theme.bgSecondary)
                    } header: {
                        Text("ミュートキーワード")
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(theme.bgPrimary)
            }
        }
        .background(theme.bgPrimary)
        .task { await loadMuteList() }
        // Add pubkey alert
        .alert(addAsPrivate ? "非公開でユーザーをミュート" : "公開でユーザーをミュート",
               isPresented: $showAddSheet) {
            TextField("npub1... または hex", text: $newPubkey)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("追加") {
                let k = newPubkey.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !k.isEmpty else { newPubkey = ""; return }
                let normalized = normalizePubkeyInput(k)
                guard !normalized.isEmpty else { newPubkey = ""; return }
                if addAsPrivate {
                    guard !privateMutes.contains(normalized) else { newPubkey = ""; return }
                    privateMutes.append(normalized)
                } else {
                    guard !publicMutes.contains(normalized) else { newPubkey = ""; return }
                    publicMutes.append(normalized)
                }
                Task {
                    await saveMuteList()
                    await loadMuteList()
                }
                newPubkey = ""
            }
            Button("キャンセル", role: .cancel) { newPubkey = "" }
        }
        // Add keyword alert
        .alert("キーワードをミュート", isPresented: $showAddKeyword) {
            TextField("キーワードを入力", text: $newKeyword)
            Button("追加") {
                let k = newKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
                if !k.isEmpty, !mutedKeywords.contains(k) {
                    mutedKeywords.append(k)
                    Task { await saveKeywords() }
                }
                newKeyword = ""
            }
            Button("キャンセル", role: .cancel) { newKeyword = "" }
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private func muteRow(pubkey: String, isPrivate: Bool) -> some View {
        HStack {
            Image(systemName: isPrivate ? "lock.person.fill" : "person.fill")
                .foregroundStyle(isPrivate ? NuruColors.lineGreen : theme.textTertiary)
            Text(profiles[pubkey]?.displayedName ?? (String(pubkey.prefix(12)) + "…"))
                .font(NuruFont.bodySmall())
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
            Spacer()
            if isPrivate {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .listRowBackground(theme.bgSecondary)
        .swipeActions {
            Button(role: .destructive) {
                if isPrivate {
                    privateMutes.removeAll { $0 == pubkey }
                } else {
                    publicMutes.removeAll { $0 == pubkey }
                }
                Task { await saveMuteList() }
            } label: {
                Label("削除", systemImage: "trash")
            }
            // 公開⇔非公開切り替え
            Button {
                if isPrivate {
                    privateMutes.removeAll { $0 == pubkey }
                    if !publicMutes.contains(pubkey) { publicMutes.append(pubkey) }
                } else {
                    publicMutes.removeAll { $0 == pubkey }
                    if !privateMutes.contains(pubkey) { privateMutes.append(pubkey) }
                }
                Task { await saveMuteList() }
            } label: {
                Label(isPrivate ? "公開に変更" : "非公開に変更",
                      systemImage: isPrivate ? "eye" : "lock")
            }
            .tint(NuruColors.lineGreen)
        }
    }

    @ViewBuilder
    private func addButton(label: String, isPrivate: Bool) -> some View {
        Button {
            addAsPrivate = isPrivate
            showAddSheet = true
        } label: {
            Label(label, systemImage: "plus")
                .font(NuruFont.bodyMedium())
                .foregroundStyle(NuruColors.lineGreen)
        }
        .listRowBackground(theme.bgSecondary)
    }

    // MARK: - Data

    private func loadMuteList() async {
        isLoading = true
        let result = await repository.fetchMuteList(pubkeyHex: pubkeyHex)
        publicMutes  = result.publicMutes
        privateMutes = result.privateMutes

        // ミュート対象のプロフィール表示名を解決
        let all = Array(Set(publicMutes + privateMutes))
        if !all.isEmpty {
            let fetched = await repository.fetchProfiles(pubkeys: all)
            profiles = Dictionary(uniqueKeysWithValues: fetched.map { ($0.pubkey, $0) })
        } else {
            profiles = [:]
        }

        // Load keywords from existing public mute list (word tags)
        let filter = NostrFilter(authors: [pubkeyHex], kinds: [NostrKind.muteList], limit: 1)
        let events = await repository.fetchEvents(filters: [filter], timeoutSeconds: 5)
        if let latest = events.max(by: { $0.createdAt < $1.createdAt }) {
            mutedKeywords = latest.tags.filter { $0.first == "word" }.compactMap { $0.dropFirst().first }
        }
        isLoading = false
    }

    private func saveMuteList() async {
        try? await repository.updateMuteList(publicMutes: publicMutes, privateMutes: privateMutes)
    }

    private func saveKeywords() async {
        // updateMuteList(keywords:) に委譲して private mutes の NIP-44 暗号化を維持する。
        // 以前の実装は publishEvent を直接呼んでいたため private mutes が上書き消去されていた。
        try? await repository.updateMuteList(
            publicMutes:  publicMutes,
            privateMutes: privateMutes,
            keywords:     mutedKeywords
        )
    }

    private func normalizePubkeyInput(_ raw: String) -> String {
        if raw.hasPrefix("npub1") || raw.hasPrefix("nprofile1") {
            if let decoded = NostrBech32.decode(raw) {
                return decoded.hex
            }
        }
        return raw.lowercased()
    }
}
