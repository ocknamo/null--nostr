import SwiftUI

// MARK: - Preview Data Model

struct PreviewData {
    let url:         String
    let title:       String?
    let description: String?
    let image:       String?
    let siteName:    String?
    let favicon:     String?
}

// MARK: - Global OG Cache

private var ogCache: [String: PreviewData?] = [:]

// MARK: - URLPreview

/// OGP card — compact (horizontal) or full (vertical with hero image).
/// Mirrors Android URLPreview composable. Fetches metadata via microlink.io.
struct URLPreview: View {
    let url: String
    var compact: Bool = false

    @State private var data:      PreviewData? = nil
    @State private var isLoading: Bool         = false
    @Environment(\.nuruTheme) private var theme

    var body: some View {
        Group {
            if isLoading {
                URLPreviewSkeleton(compact: compact)
            } else if let data {
                URLPreviewCard(data: data, compact: compact)
            }
        }
        .task(id: url) {
            await fetchOG()
        }
    }

    private func fetchOG() async {
        // Return cached result immediately
        if ogCache.keys.contains(url) {
            data = ogCache[url] ?? nil
            return
        }
        guard isValidUrl(url), !isMediaUrl(url) else {
            ogCache[url] = nil
            return
        }
        isLoading = true
        defer { isLoading = false }

        let encoded = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url
        guard let apiURL = URL(string: "https://api.microlink.io?url=\(encoded)") else {
            ogCache[url] = nil
            return
        }
        do {
            let (bytes, _) = try await URLSession.shared.data(from: apiURL)
            let json = try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
            guard (json?["status"] as? String) == "success",
                  let d = json?["data"] as? [String: Any] else {
                ogCache[url] = nil; return
            }
            let imageUrl  = (d["image"] as? [String: Any])?["url"] as? String
            let faviconUrl = (d["logo"] as? [String: Any])?["url"] as? String
            let preview   = PreviewData(
                url:         url,
                title:       d["title"] as? String,
                description: d["description"] as? String,
                image:       imageUrl,
                siteName:    d["publisher"] as? String,
                favicon:     faviconUrl
            )
            ogCache[url] = preview.title != nil ? preview : nil
            data = ogCache[url] ?? nil
        } catch {
            ogCache[url] = nil
        }
    }

    private func isValidUrl(_ s: String) -> Bool {
        guard let u = URL(string: s), let scheme = u.scheme else { return false }
        return ["http", "https"].contains(scheme) && (u.host ?? "").isEmpty == false
    }

    private func isMediaUrl(_ s: String) -> Bool {
        let pattern = #".*\.(jpg|jpeg|png|gif|webp|svg|mp4|webm|mov)(\?.*)?$"#
        return s.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

// MARK: - Card

private struct URLPreviewCard: View {
    let data: PreviewData
    var compact: Bool = false

    @Environment(\.nuruTheme) private var theme

    private var displayDomain: String {
        URL(string: data.url).flatMap { $0.host?.replacingOccurrences(of: "www.", with: "") } ?? ""
    }

    var body: some View {
        Group {
            if compact {
                compactCard
            } else {
                fullCard
            }
        }
        .background(theme.bgSecondary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
        .overlay(
            RoundedRectangle(cornerRadius: NuruSpacing.radiusMd)
                .stroke(theme.borderColor.opacity(0.5), lineWidth: 0.5)
        )
        .padding(.vertical, NuruSpacing.space2)
        .onTapGesture {
            if let u = URL(string: data.url) { UIApplication.shared.open(u) }
        }
    }

    // Horizontal: thumbnail + title + domain
    private var compactCard: some View {
        HStack(spacing: NuruSpacing.space3) {
            thumbnailView(size: 64)

            VStack(alignment: .leading, spacing: 4) {
                if let title = data.title {
                    Text(title)
                        .font(NuruFont.bodyMedium())
                        .fontWeight(.bold)
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(2)
                }
                Text(displayDomain)
                    .font(NuruFont.labelSmall())
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(NuruSpacing.space2)
    }

    // Vertical: hero image + site + title + description
    private var fullCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let img = data.image {
                AsyncImage(url: URL(string: img)) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Color(white: 0.1)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipped()
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: NuruSpacing.radiusMd,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: NuruSpacing.radiusMd
                    )
                )
            }

            VStack(alignment: .leading, spacing: NuruSpacing.space1) {
                HStack(spacing: 6) {
                    if let favicon = data.favicon {
                        AsyncImage(url: URL(string: favicon)) { phase in
                            if case .success(let img) = phase {
                                img.resizable().scaledToFit().frame(width: 14, height: 14)
                            }
                        }
                    }
                    Text(data.siteName ?? displayDomain)
                        .font(NuruFont.labelSmall())
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }

                if let title = data.title {
                    Text(title)
                        .font(NuruFont.bodyMedium())
                        .fontWeight(.bold)
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(2)
                }

                if let desc = data.description {
                    Text(desc)
                        .font(NuruFont.bodySmall())
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(2)
                }
            }
            .padding(NuruSpacing.space3)
        }
    }

    @ViewBuilder
    private func thumbnailView(size: CGFloat) -> some View {
        if let img = data.image {
            AsyncImage(url: URL(string: img)) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else { Color(white: 0.15) }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusSm))
        } else if let fav = data.favicon {
            ZStack {
                RoundedRectangle(cornerRadius: NuruSpacing.radiusSm)
                    .fill(theme.bgTertiary)
                    .frame(width: size, height: size)
                AsyncImage(url: URL(string: fav)) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFit().frame(width: 24, height: 24)
                    }
                }
            }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: NuruSpacing.radiusSm)
                    .fill(theme.bgTertiary)
                    .frame(width: size, height: size)
                Image(systemName: "link")
                    .font(.system(size: 18))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }
}

// MARK: - Skeleton

private struct URLPreviewSkeleton: View {
    var compact: Bool = false

    var body: some View {
        if compact {
            HStack(spacing: NuruSpacing.space3) {
                Skeleton(cornerRadius: NuruSpacing.radiusSm).frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: NuruSpacing.space2) {
                    Skeleton().frame(maxWidth: 200).frame(height: 16)
                    Skeleton().frame(width: 80, height: 12)
                }
            }
            .padding(NuruSpacing.space2)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Skeleton(cornerRadius: 0).frame(maxWidth: .infinity).frame(height: 180)
                VStack(alignment: .leading, spacing: NuruSpacing.space2) {
                    Skeleton().frame(width: 100, height: 12)
                    Skeleton().frame(maxWidth: .infinity).frame(height: 16)
                    Skeleton().frame(maxWidth: 260).frame(height: 12)
                }
                .padding(NuruSpacing.space3)
            }
        }
    }
}
