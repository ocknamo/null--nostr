import SwiftUI

/// Chronostr スケジュール調整 — 候補日を提案して参加者が投票する。
/// Kind 31928 (スケジュール) + Kind 31925 (RSVP 投票)。
/// Mirrors Android SchedulerApp.kt.
struct SchedulerView: View {

    let repository:  NostrRepository
    let pubkeyHex:   String

    @Environment(\.nuruTheme) private var theme
    @State private var events:     [CalendarEvent] = []
    @State private var isLoading:  Bool            = true
    @State private var showCreate: Bool            = false
    @State private var selected:   CalendarEvent?  = nil

    var body: some View {
        ZStack {
            if isLoading {
                ProgressView().tint(NuruColors.lineGreen)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if events.isEmpty {
                VStack(spacing: NuruSpacing.space3) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 40))
                        .foregroundStyle(theme.textTertiary)
                    Text("スケジュールがありません")
                        .font(NuruFont.bodyMedium())
                        .foregroundStyle(theme.textTertiary)
                    Text("＋ボタンで新規作成してください")
                        .font(NuruFont.bodySmall())
                        .foregroundStyle(theme.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: NuruSpacing.space3) {
                        ForEach(events) { ev in
                            CalendarEventCard(event: ev) { selected = ev }
                        }
                    }
                    .padding(NuruSpacing.space4)
                }
            }
        }
        .background(theme.bgPrimary)
        .safeAreaInset(edge: .bottom) {
            Button { showCreate = true } label: {
                Label("新規作成", systemImage: "plus")
                    .font(NuruFont.bodyMedium())
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(NuruColors.lineGreen)
                    .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
            }
            .buttonStyle(.plain)
            .padding(NuruSpacing.space4)
            .background(theme.bgPrimary)
        }
        .task { await loadEvents() }
        .sheet(isPresented: $showCreate) {
            CreateCalendarSheet(repository: repository, pubkeyHex: pubkeyHex) {
                showCreate = false
                Task { await loadEvents() }
            }
            .presentationDetents([.large])
        }
        .sheet(item: $selected) { ev in
            CalendarDetailSheet(event: ev, repository: repository, pubkeyHex: pubkeyHex) {
                selected = nil
                Task { await loadEvents() }
            }
            .presentationDetents([.large])
        }
    }

    private func loadEvents() async {
        isLoading = true
        events = await repository.fetchCalendarEvents(pubkey: pubkeyHex)
        isLoading = false
    }
}

// MARK: - Calendar Event Card

private struct CalendarEventCard: View {
    let event: CalendarEvent
    let onTap: () -> Void
    @Environment(\.nuruTheme) private var theme

    private var maxVotes: Int { event.candidates.map(\.votes.count).max() ?? 0 }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: NuruSpacing.space2) {
                // Title
                Text(event.title)
                    .font(NuruFont.bodyMedium())
                    .fontWeight(.bold)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)

                // Candidate dates with vote counts
                if !event.candidates.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(event.candidates.prefix(4).enumerated()), id: \.offset) { _, c in
                            candidateRow(c)
                        }
                        if event.candidates.count > 4 {
                            Text("他 \(event.candidates.count - 4) 件…")
                                .font(.system(size: 11))
                                .foregroundStyle(theme.textTertiary)
                        }
                    }
                    .padding(NuruSpacing.space2)
                    .background(theme.bgTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusSm))
                }

                Text(event.createdAt.relativeTimeString)
                    .font(NuruFont.labelSmall())
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(NuruSpacing.space3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
        }
        .buttonStyle(.plain)
    }

    private func candidateRow(_ c: DateCandidate) -> some View {
        let isTop = maxVotes > 0 && c.votes.count == maxVotes
        return HStack(spacing: 6) {
            Text(c.date + (c.time.map { " \($0)" } ?? ""))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textPrimary)
            if isTop {
                Text("最多")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(NuruColors.lineGreen)
                    .clipShape(Capsule())
            }
            Spacer()
            if !c.votes.isEmpty {
                HStack(spacing: 2) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(NuruColors.lineGreen)
                    Text("\(c.votes.count)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NuruColors.lineGreen)
                    Text("人")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textTertiary)
                }
            }
        }
    }
}

// MARK: - Create Calendar Sheet

private struct CreateCalendarSheet: View {
    let repository: NostrRepository
    let pubkeyHex:  String
    let onDone:     () -> Void

    @Environment(\.nuruTheme) private var theme
    @State private var title:      String          = ""
    @State private var dateInput:  String          = ""
    @State private var timeInput:  String          = ""
    @State private var candidates: [DateCandidate] = []
    @State private var isPosting:  Bool            = false

    var body: some View {
        VStack(spacing: 0) {
            SheetNavBar(title: "スケジュール作成", onDismiss: onDone) {
                Button("作成") { Task { await post() } }
                    .font(NuruFont.bodyMedium())
                    .fontWeight(.semibold)
                    .foregroundStyle(canPost ? NuruColors.lineGreen : theme.textTertiary)
                    .disabled(!canPost)
            }
            Divider().background(theme.borderColor)

            ScrollView {
                VStack(alignment: .leading, spacing: NuruSpacing.space4) {

                    // タイトル
                    fieldSection("タイトル") {
                        TextField("例: 飲み会の日程調整", text: $title)
                            .font(NuruFont.bodyMedium())
                            .foregroundStyle(theme.textPrimary)
                    }

                    // 候補日追加
                    fieldSection("候補日追加 (\(candidates.count)件)") {
                        HStack(spacing: 8) {
                            TextField("YYYY-MM-DD", text: $dateInput)
                                .font(NuruFont.bodyMedium())
                                .foregroundStyle(theme.textPrimary)
                                .autocorrectionDisabled()
                            TextField("HH:MM (任意)", text: $timeInput)
                                .font(NuruFont.bodyMedium())
                                .foregroundStyle(theme.textPrimary)
                                .autocorrectionDisabled()
                                .frame(maxWidth: 90)
                            Button {
                                let d = dateInput.trimmingCharacters(in: .whitespaces)
                                guard !d.isEmpty, !candidates.contains(where: { $0.date == d }) else { return }
                                let t = timeInput.trimmingCharacters(in: .whitespaces)
                                candidates.append(DateCandidate(date: d, time: t.isEmpty ? nil : t, votes: []))
                                dateInput = ""
                                timeInput = ""
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(NuruColors.lineGreen)
                                    .font(.system(size: 22))
                            }
                            .buttonStyle(.plain)
                        }

                        if !candidates.isEmpty {
                            Divider().background(theme.borderColor).padding(.vertical, 4)
                            ForEach(Array(candidates.enumerated()), id: \.offset) { idx, c in
                                HStack {
                                    Text(c.date + (c.time.map { " \($0)" } ?? ""))
                                        .font(NuruFont.bodySmall())
                                        .foregroundStyle(theme.textPrimary)
                                    Spacer()
                                    Button { candidates.remove(at: idx) } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(Color.red.opacity(0.7))
                                            .font(.system(size: 18))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(NuruSpacing.space4)
            }
        }
        .background(theme.bgPrimary)
        .overlay {
            if isPosting {
                Color.black.opacity(0.2).ignoresSafeArea()
                ProgressView().tint(NuruColors.lineGreen)
            }
        }
    }

    private var canPost: Bool { !title.isEmpty && !candidates.isEmpty && !isPosting }

    private func fieldSection<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: NuruSpacing.space2) {
            Text(label)
                .font(NuruFont.bodySmall())
                .foregroundStyle(theme.textSecondary)
            VStack(alignment: .leading, spacing: NuruSpacing.space2) {
                content()
            }
            .padding(NuruSpacing.space3)
            .background(theme.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
        }
    }

    private func post() async {
        isPosting = true
        await repository.createCalendarEvent(title: title, candidates: candidates)
        isPosting = false
        onDone()
    }
}

// MARK: - Calendar Detail Sheet

private struct CalendarDetailSheet: View {
    let event:      CalendarEvent
    let repository: NostrRepository
    let pubkeyHex:  String
    let onDone:     () -> Void

    @Environment(\.nuruTheme) private var theme
    @State private var selected:  Set<String> = []
    @State private var isSending: Bool        = false
    @State private var sent:      Bool        = false

    private var maxVotes: Int { event.candidates.map(\.votes.count).max() ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            SheetNavBar(title: event.title, onDismiss: onDone) {
                Color.clear.frame(width: 60)
            }
            Divider().background(theme.borderColor)

            ScrollView {
                VStack(alignment: .leading, spacing: NuruSpacing.space4) {

                    // 候補日リスト + 投票 UI
                    VStack(alignment: .leading, spacing: NuruSpacing.space2) {
                        Text("参加可能な日を選択してください")
                            .font(NuruFont.bodySmall())
                            .foregroundStyle(theme.textSecondary)

                        ForEach(Array(event.candidates.enumerated()), id: \.offset) { _, c in
                            candidateRow(c)
                        }
                    }

                    // 回答ボタン
                    Button {
                        Task { await respond() }
                    } label: {
                        Group {
                            if isSending {
                                ProgressView().tint(.white)
                            } else {
                                Text(sent ? "回答済み ✓" : "回答する（\(selected.count)件選択中）")
                            }
                        }
                        .font(NuruFont.bodyMedium())
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            sent ? Color.green :
                            selected.isEmpty ? NuruColors.lineGreen.opacity(0.4) :
                            NuruColors.lineGreen
                        )
                        .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSending || sent || selected.isEmpty)
                }
                .padding(NuruSpacing.space4)
            }
        }
        .background(theme.bgPrimary)
    }

    private func candidateRow(_ c: DateCandidate) -> some View {
        let checked = selected.contains(c.date)
        let isTop   = maxVotes > 0 && c.votes.count == maxVotes

        return Button {
            if checked { selected.remove(c.date) }
            else        { selected.insert(c.date) }
        } label: {
            HStack(spacing: NuruSpacing.space2) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(checked ? NuruColors.lineGreen : theme.textTertiary)
                    .font(.system(size: 20))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(c.date)
                            .font(NuruFont.bodyMedium())
                            .foregroundStyle(theme.textPrimary)
                        if let t = c.time {
                            Text(t)
                                .font(NuruFont.bodySmall())
                                .foregroundStyle(theme.textSecondary)
                        }
                        if isTop {
                            Text("最多")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(NuruColors.lineGreen)
                                .clipShape(Capsule())
                        }
                    }

                    // 投票バー
                    if maxVotes > 0 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(theme.bgTertiary)
                                    .frame(height: 4)
                                Capsule()
                                    .fill(isTop ? NuruColors.lineGreen : NuruColors.lineGreen.opacity(0.35))
                                    .frame(
                                        width: max(4, geo.size.width * CGFloat(c.votes.count) / CGFloat(maxVotes)),
                                        height: 4
                                    )
                            }
                        }
                        .frame(height: 4)
                    }
                }

                Spacer()

                // 票数バッジ
                HStack(spacing: 2) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(c.votes.isEmpty ? theme.textTertiary : NuruColors.lineGreen)
                    Text("\(c.votes.count)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(c.votes.isEmpty ? theme.textTertiary : NuruColors.lineGreen)
                }
            }
            .padding(NuruSpacing.space3)
            .background(checked ? NuruColors.lineGreen.opacity(0.07) : theme.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
            .overlay(
                RoundedRectangle(cornerRadius: NuruSpacing.radiusMd)
                    .stroke(checked ? NuruColors.lineGreen.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func respond() async {
        isSending = true
        await repository.voteCalendarEvent(
            creatorPubkey: event.creator,
            dTag:          event.dTag,
            acceptedDates: Array(selected).sorted()
        )
        isSending = false
        withAnimation { sent = true }
    }
}
