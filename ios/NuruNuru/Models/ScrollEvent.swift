import Foundation

// MARK: - ScrollParam

/// NIP-A5 Scroll のパラメータ定義。
/// `["param", name, description, type, required]` タグから生成される。
/// Android: ScrollParam data class に対応。
struct ScrollParam: Identifiable, Equatable {
    let id: String           // name をIDとして使用
    let name: String
    let description: String
    let type: String         // "pubkey" | "string" | "number" など
    let required: Bool

    init(name: String, description: String, type: String, required: Bool) {
        self.id          = name
        self.name        = name
        self.description = description
        self.type        = type
        self.required    = required
    }
}

// MARK: - ScrollEvent

/// NIP-A5 Kind 1227 Scroll イベント。
/// WASM base64 と param 定義を持ち、WebView 上で実行されるミニアプリ。
/// Android: ScrollEvent data class に対応。
struct ScrollEvent: Identifiable, Equatable {
    let id: String           // event.id
    let pubkey: String
    let title: String
    let description: String
    let wasmBase64: String   // event.content
    let params: [ScrollParam]
    let createdAt: Int64

    // MARK: - Init from NostrEvent

    /// Kind 1227 の `NostrEvent` から `ScrollEvent` を生成する。
    /// Kind が 1227 でなければ `nil` を返す（失敗安全）。
    init?(nostrEvent event: NostrEvent) {
        guard event.kind == 1227 else { return nil }

        self.id          = event.id
        self.pubkey      = event.pubkey
        self.createdAt   = event.createdAt
        self.wasmBase64  = event.content

        // title タグから取得
        self.title = event.getTagValue("title") ?? "無題のスクロール"

        // description タグから取得 (なければ空文字)
        self.description = event.getTagValue("description") ?? ""

        // param タグをパース: ["param", name, description, type, required]
        self.params = event.tags.compactMap { tag -> ScrollParam? in
            guard tag.count >= 2, tag[0] == "param" else { return nil }
            let name        = tag[safe: 1] ?? ""
            let desc        = tag[safe: 2] ?? ""
            let type        = tag[safe: 3] ?? "string"
            let requiredStr = tag[safe: 4] ?? "false"
            guard !name.isEmpty else { return nil }
            return ScrollParam(
                name:        name,
                description: desc,
                type:        type,
                required:    requiredStr.lowercased() == "true"
            )
        }
    }
}
