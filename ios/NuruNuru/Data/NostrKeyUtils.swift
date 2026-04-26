import Foundation
import CryptoKit
import P256K

/// Nostr key operations — key generation, NIP-19 encode/decode, event hashing and signing.
/// Mirrors Android NostrKeyUtils.kt.
///
/// Crypto layer: 21-DOT-DEV/swift-secp256k1 (P256K module) for secp256k1 Schnorr operations.
/// NIP-19 bech32 encoding implemented inline.
enum NostrKeyUtils {

    // MARK: - Key Generation

    /// Generate a new random secp256k1 keypair.
    /// Returns (privateKeyBytes: 32-byte raw key, publicKeyBytes: 32-byte x-only key).
    static func generateKeys() throws -> (privateKeyBytes: [UInt8], publicKeyBytes: [UInt8]) {
        let privateKey = try P256K.Schnorr.PrivateKey()
        let privBytes  = [UInt8](privateKey.dataRepresentation)  // 32 bytes
        let pubBytes   = privateKey.xonly.bytes                   // 32 bytes
        return (privBytes, pubBytes)
    }

    // MARK: - Key Parsing

    /// Parse a private key from nsec bech32 or hex string.
    /// Returns raw 32-byte private key bytes or nil.
    static func parsePrivateKey(_ input: String) -> [UInt8]? {
        let stripped = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.hasPrefix("nsec1") {
            return NIP19.decodeNsec(stripped)
        }
        if stripped.count == 64, let bytes = hexToBytes(stripped) {
            return bytes
        }
        return nil
    }

    /// Parse a public key from npub bech32 or hex string.
    /// Returns raw 32-byte x-only public key or nil.
    static func parsePublicKey(_ input: String) -> [UInt8]? {
        let stripped = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.hasPrefix("npub1") {
            return NIP19.decodeNpub(stripped)
        }
        if stripped.count == 64, let bytes = hexToBytes(stripped) {
            return bytes
        }
        return nil
    }

    // MARK: - Public Key Derivation

    /// Derive x-only public key (32 bytes) from raw 32-byte private key.
    static func derivePublicKey(from privateKeyBytes: [UInt8]) throws -> [UInt8] {
        let privateKey = try P256K.Schnorr.PrivateKey(dataRepresentation: Data(privateKeyBytes))
        return privateKey.xonly.bytes  // 32 bytes
    }

    // MARK: - NIP-19 Encoding / Decoding

    static func encodeNsec(_ privateKeyBytes: [UInt8]) -> String? {
        NIP19.encodeNsec(privateKeyBytes)
    }

    static func encodeNpub(_ publicKeyBytes: [UInt8]) -> String? {
        NIP19.encodeNpub(publicKeyBytes)
    }

    /// Shorten a public key hex for display (npub1xxxxx...).
    static func shortenPubkey(_ pubkeyHex: String, chars: Int = 8) -> String {
        guard let pubBytes = hexToBytes(pubkeyHex),
              let npub = NIP19.encodeNpub(pubBytes) else {
            return String(pubkeyHex.prefix(chars))
        }
        return String(npub.prefix(5 + chars))  // "npub1" prefix + chars
    }

    // MARK: - Hex Helpers

    static func bytesToHex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func hexToBytes(_ hex: String) -> [UInt8]? {
        guard hex.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            bytes.append(byte)
            index = nextIndex
        }
        return bytes
    }
}

// MARK: - NIP-19 Bech32 Encoding (BIP-173)

/// Bech32 codec for NIP-19 identifiers (nsec, npub, note, etc.).
/// Implements BIP-173 bech32 (not bech32m) as required by NIP-19.
private enum Bech32 {

    static let charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
    static let generator: [UInt32] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]

    static func polymod(_ values: [UInt8]) -> UInt32 {
        var chk: UInt32 = 1
        for v in values {
            let top = chk >> 25
            chk = (chk & 0x1ffffff) << 5 ^ UInt32(v)
            for i in 0..<5 where (top >> i) & 1 == 1 {
                chk ^= generator[i]
            }
        }
        return chk
    }

    static func hrpExpand(_ hrp: String) -> [UInt8] {
        let bytes = [UInt8](hrp.utf8)
        return bytes.map { $0 >> 5 } + [0] + bytes.map { $0 & 31 }
    }

    static func createChecksum(hrp: String, data: [UInt8]) -> [UInt8] {
        let values = hrpExpand(hrp) + data + [0, 0, 0, 0, 0, 0]
        let p = polymod(values) ^ 1
        return (0..<6).map { UInt8((p >> (5 * (5 - $0))) & 31) }
    }

    static func verifyChecksum(hrp: String, data: [UInt8]) -> Bool {
        polymod(hrpExpand(hrp) + data) == 1
    }

    static func encode(hrp: String, data: [UInt8]) -> String {
        let checksum = createChecksum(hrp: hrp, data: data)
        let combined = data + checksum
        let chars = combined.map { c -> Character in
            charset[charset.index(charset.startIndex, offsetBy: Int(c))]
        }
        return hrp + "1" + String(chars)
    }

    static func decode(_ bechString: String) -> (hrp: String, data: [UInt8])? {
        let str = bechString.lowercased()
        guard let sepIdx = str.lastIndex(of: "1") else { return nil }
        let hrp = String(str[str.startIndex..<sepIdx])
        let dataStr = String(str[str.index(after: sepIdx)...])
        guard !hrp.isEmpty, dataStr.count >= 6 else { return nil }

        var data = [UInt8]()
        for ch in dataStr {
            guard let idx = charset.firstIndex(of: ch) else { return nil }
            data.append(UInt8(charset.distance(from: charset.startIndex, to: idx)))
        }

        guard verifyChecksum(hrp: hrp, data: data) else { return nil }
        return (hrp, Array(data.dropLast(6)))
    }

    /// Convert between bit-group sizes. 8→5 for encoding, 5→8 for decoding.
    static func convertBits(data: [UInt8], fromBits: Int, toBits: Int, pad: Bool) -> [UInt8]? {
        var acc = 0, bits = 0
        var result = [UInt8]()
        let maxv = (1 << toBits) - 1

        for value in data {
            guard (Int(value) >> fromBits) == 0 else { return nil }
            acc = (acc << fromBits) | Int(value)
            bits += fromBits
            while bits >= toBits {
                bits -= toBits
                result.append(UInt8((acc >> bits) & maxv))
            }
        }
        if pad {
            if bits > 0 { result.append(UInt8((acc << (toBits - bits)) & maxv)) }
        } else if bits >= fromBits || ((acc << (toBits - bits)) & maxv) != 0 {
            return nil
        }
        return result
    }
}

/// NIP-19 identifier encoding — nsec, npub.
enum NIP19 {

    static func encodeNsec(_ privateKeyBytes: [UInt8]) -> String? {
        guard privateKeyBytes.count == 32 else { return nil }
        guard let fiveBit = Bech32.convertBits(data: privateKeyBytes, fromBits: 8, toBits: 5, pad: true) else { return nil }
        return Bech32.encode(hrp: "nsec", data: fiveBit)
    }

    static func encodeNpub(_ publicKeyBytes: [UInt8]) -> String? {
        guard publicKeyBytes.count == 32 else { return nil }
        guard let fiveBit = Bech32.convertBits(data: publicKeyBytes, fromBits: 8, toBits: 5, pad: true) else { return nil }
        return Bech32.encode(hrp: "npub", data: fiveBit)
    }

    static func decodeNsec(_ nsec: String) -> [UInt8]? {
        guard let (hrp, data) = Bech32.decode(nsec), hrp == "nsec" else { return nil }
        guard let bytes = Bech32.convertBits(data: data, fromBits: 5, toBits: 8, pad: false) else { return nil }
        return bytes.count == 32 ? bytes : nil
    }

    static func decodeNpub(_ npub: String) -> [UInt8]? {
        guard let (hrp, data) = Bech32.decode(npub), hrp == "npub" else { return nil }
        guard let bytes = Bech32.convertBits(data: data, fromBits: 5, toBits: 8, pad: false) else { return nil }
        return bytes.count == 32 ? bytes : nil
    }

    /// イベント ID (32-byte hex) を NIP-19 `note1` 形式にエンコードする。
    static func encodeNote1(_ eventIdHex: String) -> String? {
        guard let bytes = NostrKeyUtils.hexToBytes(eventIdHex), bytes.count == 32 else { return nil }
        guard let fiveBit = Bech32.convertBits(data: bytes, fromBits: 8, toBits: 5, pad: true) else { return nil }
        return Bech32.encode(hrp: "note", data: fiveBit)
    }

    /// NIP-19 `note1` をデコードしてイベント ID hex を返す。
    static func decodeNote1(_ note: String) -> String? {
        guard let (hrp, data) = Bech32.decode(note), hrp == "note" else { return nil }
        guard let bytes = Bech32.convertBits(data: data, fromBits: 5, toBits: 8, pad: false),
              bytes.count == 32 else { return nil }
        return NostrKeyUtils.bytesToHex(bytes)
    }

    /// NIP-19 `nevent1` をデコードしてイベント ID hex を返す。
    /// TLV 形式: type(1) + length(1) + data(N), type 0 = event id (32 bytes)
    static func decodeNevent1(_ nevent: String) -> String? {
        guard let (hrp, data) = Bech32.decode(nevent), hrp == "nevent" else { return nil }
        guard let bytes = Bech32.convertBits(data: data, fromBits: 5, toBits: 8, pad: false) else { return nil }
        // Parse TLV: find type 0 (event id)
        var i = 0
        while i + 1 < bytes.count {
            let type = bytes[i]
            let len  = Int(bytes[i + 1])
            i += 2
            guard i + len <= bytes.count else { break }
            if type == 0 && len == 32 {
                return NostrKeyUtils.bytesToHex(Array(bytes[i..<(i + len)]))
            }
            i += len
        }
        return nil
    }
}

/// note1.../nevent1.../npub1.../nprofile1... デコードヘルパー。
/// EmbeddedNostrCard（Android EmbeddedNostrContent に対応）など View 層から使用。
enum NostrBech32 {

    /// デコード結果の型。Android NostrKeyUtils.parseNostrLink に対応。
    enum LinkType { case note, nevent, npub, nprofile }

    struct ParsedLink {
        let type: LinkType
        let hex:  String   // event ID hex or pubkey hex
    }

    /// bech32 文字列をパースし、タイプと hex を返す。
    static func decode(_ bech32: String) -> ParsedLink? {
        if bech32.hasPrefix("note1"),
           let hex = NIP19.decodeNote1(bech32) {
            return ParsedLink(type: .note, hex: hex)
        }
        if bech32.hasPrefix("nevent1"),
           let hex = NIP19.decodeNevent1(bech32) {
            return ParsedLink(type: .nevent, hex: hex)
        }
        if bech32.hasPrefix("npub1"),
           let bytes = NIP19.decodeNpub(bech32) {
            return ParsedLink(type: .npub, hex: NostrKeyUtils.bytesToHex(bytes))
        }
        if bech32.hasPrefix("nprofile1") {
            // nprofile TLV: type 0 = pubkey (32 bytes)
            guard let (hrp, data) = Bech32.decode(bech32), hrp == "nprofile",
                  let bytes = Bech32.convertBits(data: data, fromBits: 5, toBits: 8, pad: false) else { return nil }
            var i = 0
            while i + 1 < bytes.count {
                let t = bytes[i]; let len = Int(bytes[i + 1]); i += 2
                guard i + len <= bytes.count else { break }
                if t == 0 && len == 32 {
                    return ParsedLink(type: .nprofile, hex: NostrKeyUtils.bytesToHex(Array(bytes[i..<(i+len)])))
                }
                i += len
            }
            return nil
        }
        return nil
    }

    /// NIP-19 naddr1 を kind:pubkey:d 形式へデコードする。
    static func decodeNaddrToA(_ naddr: String) -> String? {
        guard let (hrp, data) = Bech32.decode(naddr), hrp == "naddr",
              let bytes = Bech32.convertBits(data: data, fromBits: 5, toBits: 8, pad: false) else { return nil }

        var i = 0
        var identifier: String?
        var authorHex: String?
        var kind: Int?

        while i + 1 < bytes.count {
            let t = bytes[i]
            let len = Int(bytes[i + 1])
            i += 2
            guard i + len <= bytes.count else { break }
            let v = Array(bytes[i..<(i + len)])
            switch t {
            case 0:
                identifier = String(data: Data(v), encoding: .utf8)
            case 2:
                if v.count == 32 { authorHex = NostrKeyUtils.bytesToHex(v) }
            case 3:
                if v.count == 4 {
                    kind = (Int(v[0]) << 24) | (Int(v[1]) << 16) | (Int(v[2]) << 8) | Int(v[3])
                }
            default:
                break
            }
            i += len
        }

        guard let d = identifier, let author = authorHex, let k = kind else { return nil }
        return "\(k):\(author):\(d)"
    }

    /// 後方互換: イベント ID のみ取得。
    static func decodeEventId(_ bech32: String) -> String? {
        if bech32.hasPrefix("note1") {
            return NIP19.decodeNote1(bech32)
        } else if bech32.hasPrefix("nevent1") {
            return NIP19.decodeNevent1(bech32)
        }
        return nil
    }
}

// MARK: - Nostr Event Signing (NIP-01)

extension NostrKeyUtils {

    /// Compute NIP-01 event ID: SHA256 of the canonical JSON serialization.
    static func computeEventId(
        pubkeyHex: String,
        createdAt: Int64,
        kind: Int,
        tags: [[String]],
        content: String
    ) -> String? {
        guard let serialized = serializeForId(
            pubkeyHex: pubkeyHex, createdAt: createdAt,
            kind: kind, tags: tags, content: content
        ) else { return nil }

        let hash = SHA256.hash(data: serialized)
        return bytesToHex([UInt8](hash))
    }

    /// Sign an event ID (32 bytes as hex) with Schnorr — returns 64-byte signature hex.
    ///
    /// NIP-01: event ID は既にシリアライズの SHA256 ハッシュであるため、
    /// BIP-340 Schnorr 署名では event ID バイトを直接署名する（二重ハッシュしない）。
    static func signEventId(_ eventIdHex: String, privateKeyBytes: [UInt8]) throws -> String {
        guard var idBytes = hexToBytes(eventIdHex), idBytes.count == 32 else {
            throw SignError.invalidEventId
        }
        let privateKey = try P256K.Schnorr.PrivateKey(dataRepresentation: Data(privateKeyBytes))
        // event ID (32 bytes) を直接署名する — SHA256 で再ハッシュしない
        let sig = try privateKey.signature(message: &idBytes, auxiliaryRand: nil)
        return bytesToHex([UInt8](sig.dataRepresentation))
    }

    /// Build and sign a complete NostrEvent.
    static func buildAndSign(
        privateKeyBytes: [UInt8],
        publicKeyHex: String,
        kind: Int,
        tags: [[String]],
        content: String,
        createdAt: Int64 = Int64(Date().timeIntervalSince1970)
    ) throws -> NostrEvent {
        guard let eventId = computeEventId(
            pubkeyHex: publicKeyHex, createdAt: createdAt,
            kind: kind, tags: tags, content: content
        ) else {
            throw SignError.serializationFailed
        }

        let sig = try signEventId(eventId, privateKeyBytes: privateKeyBytes)

        return NostrEvent(
            id:        eventId,
            pubkey:    publicKeyHex,
            createdAt: createdAt,
            kind:      kind,
            tags:      tags,
            content:   content,
            sig:       sig
        )
    }

    // MARK: - Private

    private static func serializeForId(
        pubkeyHex: String,
        createdAt: Int64,
        kind: Int,
        tags: [[String]],
        content: String
    ) -> Data? {
        // NIP-01 serialization: [0, pubkey, created_at, kind, tags, content]
        let tagsJSON = tags
            .map { tag in "[" + tag.map { "\"\($0.jsonEscaped)\"" }.joined(separator: ",") + "]" }
            .joined(separator: ",")

        let json = "[0,\"\(pubkeyHex)\",\(createdAt),\(kind),[\(tagsJSON)],\"\(content.jsonEscaped)\"]"
        return json.data(using: .utf8)
    }

    enum SignError: LocalizedError {
        case invalidEventId
        case serializationFailed

        var errorDescription: String? {
            switch self {
            case .invalidEventId:      return "イベントIDの形式が正しくありません"
            case .serializationFailed: return "イベントのシリアライズに失敗しました"
            }
        }
    }
}

private extension String {
    /// Minimal JSON string escaping per NIP-01 spec.
    var jsonEscaped: String {
        var result = ""
        for ch in self {
            switch ch {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                let scalar = ch.unicodeScalars.first!.value
                if scalar < 0x20 {
                    result += String(format: "\\u%04x", scalar)
                } else {
                    result.append(ch)
                }
            }
        }
        return result
    }
}
