import Foundation

// MARK: - FFI Data Types (Swift mirrors of Rust FFI structs)

/// Mirrors Rust FfiMlsGroupInfo.
public struct FfiMlsGroupInfo {
    /// Nostr group id hex (Kind 445 `h` tag value).
    /// Do not expose or pass MDK/OpenMLS internal MLS group ids across the FFI/App boundary.
    public let groupIdHex:    String
    public let name:          String
    public let description:   String
    public let adminPubkeys:  [String]
    public let memberPubkeys: [String]
    public let relays:        [String]
    public let createdAt:     UInt64
    public let epoch:         UInt64
    /// MIP-01 v3 disappearing message duration in seconds.
    /// nil => disabled.
    public let disappearingMessageSecs: UInt64?
    public let isDm:          Bool

    public init(groupIdHex: String, name: String, description: String, adminPubkeys: [String], memberPubkeys: [String], relays: [String], createdAt: UInt64, epoch: UInt64, disappearingMessageSecs: UInt64? = nil, isDm: Bool) {
        self.groupIdHex = groupIdHex
        self.name = name
        self.description = description
        self.adminPubkeys = adminPubkeys
        self.memberPubkeys = memberPubkeys
        self.relays = relays
        self.createdAt = createdAt
        self.epoch = epoch
        self.disappearingMessageSecs = disappearingMessageSecs
        self.isDm = isDm
    }
}

/// Mirrors Rust FfiDecryptedMessage.
public struct FfiDecryptedMessage {
    public let senderPubkey: String
    public let content:      String
    public let timestamp:    UInt64
    /// Nostr group id hex (Kind 445 `h` tag value), not the internal MLS group id.
    public let groupIdHex:   String

    public init(senderPubkey: String, content: String, timestamp: UInt64, groupIdHex: String) {
        self.senderPubkey = senderPubkey
        self.content = content
        self.timestamp = timestamp
        self.groupIdHex = groupIdHex
    }
}

public enum FfiMlsProcessResult {
    case application(FfiDecryptedMessage)
    case stateUpdate(String)
}

/// Mirrors Rust FfiEncryptedMessageData (Kind-445 event payload).
public struct FfiEncryptedMessageData {
    public let content:         String
    public let tags:            [[String]]
    public let ephemeralPubkey: String

    public init(content: String, tags: [[String]], ephemeralPubkey: String) {
        self.content = content
        self.tags = tags
        self.ephemeralPubkey = ephemeralPubkey
    }
}

/// Mirrors Rust FfiWelcomeEventData (Marmot MIP-02).
public struct FfiWelcomeEventData {
    public let recipientPubkey:      String
    public let content:              String
    public let tags:                 [[String]]
    public let giftWrappedEventJson: String
    public let innerRumorJson:       String

    public init(
        recipientPubkey: String,
        content: String,
        tags: [[String]],
        giftWrappedEventJson: String = "",
        innerRumorJson: String = ""
    ) {
        self.recipientPubkey = recipientPubkey
        self.content = content
        self.tags = tags
        self.giftWrappedEventJson = giftWrappedEventJson
        self.innerRumorJson = innerRumorJson
    }
}

/// Mirrors Rust FfiAddMemberResult.
public struct FfiAddMemberResult {
    public let commitEventData:  FfiEncryptedMessageData
    public let welcomeEventData: FfiWelcomeEventData

    public init(commitEventData: FfiEncryptedMessageData, welcomeEventData: FfiWelcomeEventData) {
        self.commitEventData = commitEventData
        self.welcomeEventData = welcomeEventData
    }
}

/// Mirrors Rust FfiKeyPackageEventData (Marmot MIP-00).
public struct FfiKeyPackageEventData {
    public let kind:       UInt32
    public let content:    String
    public let tags:       [[String]]
    public let legacyTags: [[String]]
    public let dTag:       String
    public let hashRef:    [UInt8]

    public init(kind: UInt32 = 30443, content: String, tags: [[String]], legacyTags: [[String]] = [], dTag: String = "", hashRef: [UInt8] = []) {
        self.kind = kind
        self.content = content
        self.tags = tags
        self.legacyTags = legacyTags
        self.dTag = dTag
        self.hashRef = hashRef
    }
}

// MARK: - MLS-only FFI Bridge Protocol

/// MLS 暗号層のみの FFI ブリッジ。
/// Timeline / Profile / Publishing は pure Swift が担当。
///
/// Contract: every `groupIdHex` at this FFI/App boundary is the Nostr group id
/// hex (Kind 445 `h` tag value). MDK/OpenMLS internal MLS group ids must stay
/// inside Rust and must never be exposed to iOS callers.
protocol MlsFFIBridge: AnyObject, Sendable {

    // ── 初期化 ──
    func connect()
    func disconnect() throws

    // ── KeyPackage (Kind 30443, MIP-00) ──
    func mlsCreateKeyPackage() throws -> FfiKeyPackageEventData
    func mlsValidateKeyPackageEvent(eventJSON: String) throws
    func mlsDeleteConsumedKeyPackageFromEventJSON(eventJSON: String) throws
    func mlsDeleteConsumedKeyPackageByHashRef(hashRef: [UInt8]) throws
    /// Returns Nostr group id hex values that can be passed to `mlsCreateRecoveryCommit`.
    func mlsGroupsNeedingSelfUpdate(thresholdSecs: UInt64) throws -> [String]

    // ── グループ管理 ──
    func mlsCreateGroup(name: String, adminPubkeys: [String], relays: [String]) throws -> FfiMlsGroupInfo
    func mlsAddMember(groupIdHex: String, keyPackageEventJSON: String) throws -> FfiAddMemberResult
    func mlsRemoveMember(groupIdHex: String, memberPubkeyHex: String) throws -> FfiEncryptedMessageData
    func mlsLeaveGroup(groupIdHex: String) throws -> FfiEncryptedMessageData
    func mlsListGroups() throws -> [FfiMlsGroupInfo]
    func mlsGetGroupInfo(groupIdHex: String) throws -> FfiMlsGroupInfo

    // ── メッセージ送受信 (Kind 445) ──
    func mlsCreateMessage(groupIdHex: String, content: String) throws -> FfiEncryptedMessageData
    func mlsProcessMessage(groupIdHex: String, eventJSON: String) throws -> FfiDecryptedMessage
    func mlsProcessMessageResult(groupIdHex: String, eventJSON: String) throws -> FfiMlsProcessResult

    // ── Welcome (Kind 444 / 1059) ──
    func mlsProcessWelcome(welcomeEventJSON: String) throws -> FfiMlsGroupInfo

    // ── 履歴 + 状態管理 ──
    func mlsGetMessageHistory(groupIdHex: String, limit: UInt64) throws -> [FfiDecryptedMessage]
    func mlsMergePendingCommit(groupIdHex: String) throws
    func mlsCreateRecoveryCommit(groupIdHex: String) throws -> FfiEncryptedMessageData
    func mlsClearPendingCommit(groupIdHex: String) throws
}

// MARK: - Stub (fallback when XCFramework is not yet linked)

final class MlsFFIStub: MlsFFIBridge, @unchecked Sendable {
    func connect() {}
    func disconnect() throws {}

    func mlsCreateKeyPackage() throws -> FfiKeyPackageEventData {
        FfiKeyPackageEventData(kind: 30443, content: "", tags: [], legacyTags: [], dTag: "")
    }

    func mlsValidateKeyPackageEvent(eventJSON: String) throws {}
    func mlsDeleteConsumedKeyPackageFromEventJSON(eventJSON: String) throws {}
    func mlsDeleteConsumedKeyPackageByHashRef(hashRef: [UInt8]) throws {}
    func mlsGroupsNeedingSelfUpdate(thresholdSecs: UInt64) throws -> [String] { [] }

    func mlsCreateGroup(name: String, adminPubkeys: [String], relays: [String]) throws -> FfiMlsGroupInfo {
        FfiMlsGroupInfo(
            groupIdHex: UUID().uuidString,
            name: name,
            description: "",
            adminPubkeys: adminPubkeys,
            memberPubkeys: adminPubkeys,
            relays: relays,
            createdAt: 0,
            epoch: 0,
            disappearingMessageSecs: nil,
            isDm: false
        )
    }

    func mlsAddMember(groupIdHex: String, keyPackageEventJSON: String) throws -> FfiAddMemberResult {
        FfiAddMemberResult(
            commitEventData: FfiEncryptedMessageData(content: "", tags: [], ephemeralPubkey: ""),
            welcomeEventData: FfiWelcomeEventData(recipientPubkey: "", content: "", tags: [], giftWrappedEventJson: "", innerRumorJson: "")
        )
    }

    func mlsRemoveMember(groupIdHex: String, memberPubkeyHex: String) throws -> FfiEncryptedMessageData {
        FfiEncryptedMessageData(content: "", tags: [], ephemeralPubkey: "")
    }

    func mlsLeaveGroup(groupIdHex: String) throws -> FfiEncryptedMessageData {
        FfiEncryptedMessageData(content: "", tags: [], ephemeralPubkey: "")
    }

    func mlsListGroups() throws -> [FfiMlsGroupInfo] { [] }

    func mlsGetGroupInfo(groupIdHex: String) throws -> FfiMlsGroupInfo {
        FfiMlsGroupInfo(groupIdHex: groupIdHex, name: "", description: "", adminPubkeys: [], memberPubkeys: [], relays: [], createdAt: 0, epoch: 0, disappearingMessageSecs: nil, isDm: false)
    }

    func mlsCreateMessage(groupIdHex: String, content: String) throws -> FfiEncryptedMessageData {
        FfiEncryptedMessageData(content: content, tags: [], ephemeralPubkey: "")
    }

    func mlsProcessMessage(groupIdHex: String, eventJSON: String) throws -> FfiDecryptedMessage {
        FfiDecryptedMessage(senderPubkey: "", content: "", timestamp: 0, groupIdHex: groupIdHex)
    }

    func mlsProcessMessageResult(groupIdHex: String, eventJSON: String) throws -> FfiMlsProcessResult {
        .application(FfiDecryptedMessage(senderPubkey: "", content: "", timestamp: 0, groupIdHex: groupIdHex))
    }

    func mlsProcessWelcome(welcomeEventJSON: String) throws -> FfiMlsGroupInfo {
        FfiMlsGroupInfo(groupIdHex: "", name: "", description: "", adminPubkeys: [], memberPubkeys: [], relays: [], createdAt: 0, epoch: 0, disappearingMessageSecs: nil, isDm: false)
    }

    func mlsGetMessageHistory(groupIdHex: String, limit: UInt64) throws -> [FfiDecryptedMessage] { [] }
    func mlsMergePendingCommit(groupIdHex: String) throws {}

    func mlsCreateRecoveryCommit(groupIdHex: String) throws -> FfiEncryptedMessageData {
        FfiEncryptedMessageData(content: "", tags: [], ephemeralPubkey: "")
    }

    func mlsClearPendingCommit(groupIdHex: String) throws {}
}
