import SwiftUI

// MARK: - Profile Header

/// バナー + 重なるカード + アバター + フォロー/メッセージボタン + メタ情報.
/// Mirrors Android ProfileHeader composable.
struct ProfileHeader: View {
    let profile:          UserProfile?
    let pubkey:           String
    let isOwnProfile:     Bool
    let isFollowing:      Bool
    let isNip05Verified:  Bool
    let followCount:      Int
    let badgeUrls:        [String]           // fallback; ignored when repository is set
    var repository:       NostrRepository?   = nil   // enables BadgeDisplay auto-fetch
    var onEditClick:      () -> Void       = {}
    var onQRClick:        (() -> Void)?    = nil     // QR code — mirrors Android onQRClick
    var onFollowClick:    () -> Void       = {}
    var onMessageClick:   (() -> Void)?    = nil
    var onFollowListClick: () -> Void      = {}

    @Environment(\.nuruTheme) private var theme
    @State private var showBirthdayOverlay = false
    @State private var showCopiedFeedback  = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                // Banner
                bannerView
                    .frame(height: 112)

                // Card overlapping banner
                profileCard
                    .padding(.horizontal, NuruSpacing.space4)
                    .offset(y: -56)
                    .padding(.bottom, -56)
            }

            // Avatar (overlaps banner/card boundary)
            // size: 80pt (= Android 80dp)
            AvatarView(
                url:  profile?.picture,
                name: profile?.displayedName ?? "?",
                size: NuruSpacing.avatarXl
            )
            .background(Circle().fill(theme.bgPrimary).frame(width: 88, height: 88))
            .frame(width: 88, height: 88)
            .padding(.leading, 32)
            .offset(y: 24)   // mirrors Android: offset(y = 24.dp) — avatar bridges banner/card boundary
        }
        .task(id: profile?.birthday) {
            await checkBirthday()
        }
        .overlay {
            if showBirthdayOverlay {
                BirthdayAnimationOverlay(name: profile?.displayedName ?? "")
                    .onTapGesture { showBirthdayOverlay = false }
            }
        }
    }

    /// Shortened npub for display (e.g. "npub1abc…xyz").
    /// Falls back to hex shortened if bech32 encoding fails.
    private var npubDisplayString: String {
        NostrKeyUtils.shortenPubkey(pubkey, chars: 8)
    }

    // MARK: Banner

    private var bannerView: some View {
        ZStack {
            NuruColors.lineGreen
            if let url = profile?.banner, !url.isEmpty, let imageUrl = URL(string: url) {
                // CachedAsyncImage を使用してバナー画像をディスクキャッシュ
                // Android の Coil キャッシュに対応 — 毎回ネットワークから読み込まない
                CachedAsyncImage(url: imageUrl) {
                    // ローディング中はバナー背景色（lineGreen）を表示
                    Color.clear
                }
                .frame(maxWidth: .infinity, minHeight: 112, maxHeight: 112)
                .contentShape(Rectangle())
                .clipped()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 112)
    }

    // MARK: Card

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: NuruSpacing.space3) {
            // Top row: spacer for avatar + name/buttons
            HStack(alignment: .top) {
                Spacer().frame(width: 92)   // avatar width 80 + 12 gap

                VStack(alignment: .leading, spacing: 2) {
                    // Name + edit/follow buttons
                    HStack(spacing: NuruSpacing.space2) {
                        Text(profile?.displayedName ?? pubkey.shortenedPubkey)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if isOwnProfile {
                            // Mirrors Android: QR icon + edit icon in Row (Arrangement.spacedBy(6.dp))
                            // Size 20pt + 32pt tap target to match Android 24dp icon + touch area
                            HStack(spacing: 4) {
                                if let qrAction = onQRClick {
                                    Button(action: qrAction) {
                                        Image(systemName: NuruIcons.qrCode)
                                            .font(.system(size: 22))
                                            .foregroundStyle(theme.textTertiary)
                                            .frame(width: 32, height: 32)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                                Button(action: onEditClick) {
                                    Image(systemName: NuruIcons.edit)
                                        .font(.system(size: 22))
                                        .foregroundStyle(theme.textTertiary)
                                        .frame(width: 32, height: 32)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        } else {
                            HStack(spacing: 6) {
                                if let msg = onMessageClick {
                                    Button(action: msg) {
                                        Image(systemName: NuruIcons.talk(filled: false))
                                            .font(.system(size: 16))
                                            .foregroundStyle(theme.textPrimary)
                                            .frame(width: 34, height: 34)
                                            .background(theme.bgPrimary)
                                            .clipShape(Capsule())
                                            .overlay(Capsule().stroke(theme.borderColor, lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                                Button(action: onFollowClick) {
                                    Text(isFollowing ? "解除" : "フォロー")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(isFollowing ? theme.textPrimary : .white)
                                        .frame(height: 34)
                                        .padding(.horizontal, 12)
                                        .background(isFollowing ? Color.clear : NuruColors.lineGreen)
                                        .clipShape(Capsule())
                                        .overlay(
                                            Capsule().stroke(isFollowing ? theme.borderColor : Color.clear, lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // NIP-05 — mirrors Android: formatNip05Domain shows only domain after '@'
                    // font size 16sp matches Android NIP-05 row
                    if let nip05 = profile?.nip05, !nip05.isEmpty {
                        HStack(spacing: 3) {
                            if isNip05Verified {
                                // Mirrors Android NuruIcons.Verified: filled green circle + white checkmark
                                VerifiedIcon()
                                    .frame(width: 16, height: 16)
                            }
                            Text(formatNip05Domain(nip05))
                                .font(.system(size: 16))
                                .foregroundStyle(isNip05Verified ? NuruColors.lineGreen : theme.textTertiary)
                                .lineLimit(1)
                        }
                        .padding(.top, 2)
                    }

                    // Pubkey (copy npub on tap) — mirrors Android npub copy button
                    HStack(spacing: 4) {
                        Text(npubDisplayString)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(theme.textTertiary)
                        Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundStyle(showCopiedFeedback ? NuruColors.lineGreen : theme.textTertiary)
                            .animation(.easeInOut(duration: 0.15), value: showCopiedFeedback)
                    }
                    .onTapGesture {
                        // Copy full npub (or hex fallback) to clipboard
                        if let bytes = NostrKeyUtils.hexToBytes(pubkey),
                           let npub  = NostrKeyUtils.encodeNpub(bytes) {
                            UIPasteboard.general.string = npub
                        } else {
                            UIPasteboard.general.string = pubkey
                        }
                        showCopiedFeedback = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            showCopiedFeedback = false
                        }
                    }
                }
            }
            .padding(.top, NuruSpacing.space2)

            // About
            if let about = profile?.about, !about.isEmpty {
                ProfileAbout(about: about)
            }

            // Badges — mirrors Android order: shown AFTER about, BEFORE meta info.
            // BadgeDisplay uses initialBadges, skipping network fetch when available.
            if let repo = repository {
                BadgeDisplay(pubkey: pubkey, repository: repo, initialBadges: badgeUrls)
            } else if !badgeUrls.isEmpty {
                HStack(spacing: 4) {
                    ForEach(badgeUrls.prefix(3), id: \.self) { url in
                        AsyncImage(url: URL(string: url)) { phase in
                            if case .success(let img) = phase {
                                img.resizable().scaledToFit()
                            }
                        }
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                .padding(.top, NuruSpacing.space3)
            }

            // Meta info — mirrors Android order: after badges
            VStack(alignment: .leading, spacing: NuruSpacing.space2) {
                if let lud16 = profile?.lud16, !lud16.isEmpty {
                    // Mirrors Android: Bitcoin (₿) icon for Lightning address field
                    MetaInfoItem(icon: "", text: lud16, customIconView: AnyView(BitcoinIcon()))
                }
                if let website = profile?.website, !website.isEmpty {
                    MetaInfoItem(icon: NuruIcons.website, text: website, color: NuruColors.lineGreen)
                        .onTapGesture {
                            if let u = URL(string: website) { UIApplication.shared.open(u) }
                        }
                }
                if let birthday = profile?.birthday, !birthday.isEmpty {
                    birthdayRow(birthday)
                }
            }

            // Follow count
            HStack(spacing: 6) {
                Image(systemName: "person.2")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.textSecondary)
                Text("\(followCount)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                Text("フォロー中")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.textSecondary)
            }
            .onTapGesture { onFollowListClick() }
        }
        .padding(NuruSpacing.space4)
        .background(theme.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusLg))
        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
    }

    @ViewBuilder
    private func birthdayRow(_ birthday: String) -> some View {
        HStack(spacing: NuruSpacing.space2) {
            MetaInfoItem(icon: NuruIcons.cake, text: birthday)
            if isBirthdayToday(birthday) {
                Text("今日は誕生日！")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(red: 0.91, green: 0.12, blue: 0.39))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color(red: 1, green: 0.92, blue: 0.93))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func isBirthdayToday(_ birthday: String) -> Bool {
        let parts = birthday.split(separator: "-").map(String.init)
        let cal   = Calendar.current
        let now   = Date()
        let month = cal.component(.month, from: now)
        let day   = cal.component(.day,   from: now)
        if parts.count == 3 {
            return Int(parts[1]) == month && Int(parts[2]) == day
        } else if parts.count == 2 {
            return Int(parts[0]) == month && Int(parts[1]) == day
        }
        return false
    }

    private func checkBirthday() async {
        if let birthday = profile?.birthday, isBirthdayToday(birthday) {
            showBirthdayOverlay = true
            try? await Task.sleep(for: .seconds(5))
            showBirthdayOverlay = false
        }
    }
}

// MARK: - Profile Tabs

/// 投稿 / いいね タブ切り替え — lineGreen underline indicator.
/// Mirrors Android ProfileTabs composable.
struct ProfileTabs: View {
    let activeTab:     Int
    let onTabSelected: (Int) -> Void
    let postCount:     Int
    let likeCount:     Int

    @Environment(\.nuruTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                tabButton(0, label: "投稿 (\(postCount))")
                tabButton(1, label: "いいね (\(likeCount))")
                Spacer()
            }
            .padding(.horizontal, NuruSpacing.space3)
            Divider().background(theme.borderColor)
        }
        .background(theme.bgPrimary)
    }

    @ViewBuilder
    private func tabButton(_ index: Int, label: String) -> some View {
        let selected = activeTab == index
        VStack(spacing: 0) {
            // Height 40pt, active text = textPrimary, inactive = textSecondary
            // Mirrors Android ProfileTabs: active underline is lineGreen, text is textPrimary
            Text(label)
                .font(.system(size: 14, weight: selected ? .bold : .regular))
                .foregroundStyle(selected ? NuruColors.lineGreen : theme.textSecondary)
                .frame(height: 40)
                .animation(.easeInOut(duration: 0.15), value: selected)

            Rectangle()
                .fill(selected ? NuruColors.lineGreen : Color.clear)
                .frame(height: 2)
                .cornerRadius(1)
                .animation(.easeInOut(duration: 0.15), value: selected)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTabSelected(index) }
    }
}

// MARK: - Profile About

/// Bio text with clickable URLs/nostr links highlighted in lineGreen.
struct ProfileAbout: View {
    let about: String
    @Environment(\.nuruTheme) private var theme

    var body: some View {
        Text(attributedAbout)
            .font(NuruFont.bodySmall())
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributedAbout: AttributedString {
        var result   = AttributedString(about)
        let pattern  = #"(https?://[^\s]+|nostr:[a-z0-9]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        let ns       = about as NSString
        for match in regex.matches(in: about, range: NSRange(location: 0, length: ns.length)).reversed() {
            let range  = match.range
            let value  = ns.substring(with: range)
            let short  = value.count > 40 ? String(value.prefix(40)) + "…" : value
            if let swRange = Range(range, in: about),
               let attrRange = Range(swRange, in: result) {
                result.replaceSubrange(attrRange, with: {
                    var s = AttributedString(short)
                    s.foregroundColor = NuruColors.lineGreen
                    return s
                }())
            }
        }
        return result
    }
}

// MARK: - Meta Info Item

/// Icon + text row for profile meta data (lud16, website, birthday).
/// `customIconView` が渡された場合はそちらを優先（Bitcoin アイコン等）。
struct MetaInfoItem: View {
    let icon:  String
    let text:  String
    var color: Color? = nil
    var customIconView: AnyView? = nil

    @Environment(\.nuruTheme) private var theme

    var body: some View {
        HStack(spacing: NuruSpacing.space2) {
            if let custom = customIconView {
                custom
                    .frame(width: 14, height: 14)
                    .foregroundStyle(theme.textTertiary)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.textTertiary)
            }
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(color ?? theme.textTertiary)
                .lineLimit(1)
        }
    }
}

// MARK: - Birthday Animation Overlay

/// 🎂 誕生日アニメーション — confetti falling + greeting card.
/// Mirrors Android BirthdayAnimationOverlay composable.
struct BirthdayAnimationOverlay: View {
    let name: String

    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.88, green: 0.75, blue: 0.91).opacity(0.8),
                    Color(red: 0.99, green: 0.89, blue: 0.93).opacity(0.8),
                    Color(red: 0.88, green: 0.96, blue: 1.0).opacity(0.8)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            // Confetti
            ForEach(0..<20, id: \.self) { i in
                ConfettiParticle(index: i)
            }

            // Greeting card
            VStack(spacing: NuruSpacing.space4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 200, height: 200)
                    Text("🎂")
                        .font(.system(size: 100))
                }

                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        Text("🎂")
                        Text("Happy Birthday!")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.black)
                        Text("🎂")
                    }
                    Text(name)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.gray)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusLg))
                .shadow(radius: 8)
            }
        }
    }
}

private struct ConfettiParticle: View {
    let index: Int
    @State private var yOffset: CGFloat = -50

    private let symbols = ["*", "+", "★", "✦", "◆", "●", "♦"]
    private let colors: [Color] = [.pink, .cyan, .yellow, .red, .purple, .orange, .mint]

    var body: some View {
        Text(symbols[index % symbols.count])
            .font(.system(size: 24))
            .foregroundStyle(colors[index % colors.count])
            .opacity(0.6)
            .offset(x: CGFloat((index * 50) % 400) - 200, y: yOffset)
            .onAppear {
                withAnimation(
                    .linear(duration: Double.random(in: 2.5...4.0))
                    .repeatForever(autoreverses: false)
                    .delay(Double(index) * 0.1)
                ) {
                    yOffset = UIScreen.main.bounds.height + 50
                }
            }
    }
}

// MARK: - Helpers

private func formatNip05(_ nip05: String) -> String {
    nip05.hasPrefix("_@") ? String(nip05.dropFirst(2)) : nip05
}

/// Mirrors Android formatNip05Domain: returns only the domain part after the last '@'.
/// e.g. "_@nullnull.app" → "nullnull.app", "user@domain.com" → "domain.com"
private func formatNip05Domain(_ nip05: String) -> String {
    if let atIdx = nip05.lastIndex(of: "@") {
        let domain = nip05[nip05.index(after: atIdx)...]
        return String(domain)
    }
    return nip05
}
