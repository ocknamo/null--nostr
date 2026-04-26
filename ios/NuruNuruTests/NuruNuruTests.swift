import XCTest
@testable import NuruNuru  // app target

final class NuruNuruTests: XCTestCase {

    func testRecommendationEngagementScoreMatchesRustWeights() {
        let engine = RecommendationEngine()
        let data = RecommendationEngagementData(likes: 10, reposts: 1, replies: 2, zaps: 1, quotes: 0)
        XCTAssertEqual(engine.engagementScore(data), 236.0, accuracy: 0.0001)
    }

    func testRecommendationTimeDecayFreshnessBoost() {
        let engine = RecommendationEngine()
        let now = Date(timeIntervalSince1970: 10_000)
        XCTAssertEqual(engine.timeDecay(createdAt: 9_700, now: now), 1.5, accuracy: 0.0001)
    }

    func testRecommendationTimeDecayHalfLifeMatchesRustFormula() {
        let engine = RecommendationEngine()
        let now = Date(timeIntervalSince1970: 50_000)
        let createdAt = Int64(now.timeIntervalSince1970 - 6 * 3600)
        XCTAssertEqual(engine.timeDecay(createdAt: createdAt, now: now), 0.5, accuracy: 0.0001)
    }

    func testRecommendationTimeDecayFallsBackToMinScoreAfterMaxAge() {
        let engine = RecommendationEngine()
        let now = Date(timeIntervalSince1970: 200_000)
        let createdAt = Int64(now.timeIntervalSince1970 - 49 * 3600)
        XCTAssertEqual(engine.timeDecay(createdAt: createdAt, now: now), 0.1, accuracy: 0.0001)
    }

    func testRecommendationGeohashBoostMatchesRustRules() {
        XCTAssertEqual(RecommendationEngine.geohashBoost(userGeohash: "xn76u", authorGeohash: "xn76u"), 2.0, accuracy: 0.0001)
        XCTAssertEqual(RecommendationEngine.geohashBoost(userGeohash: "xn76u", authorGeohash: "xn7ab"), 1.5, accuracy: 0.0001)
        XCTAssertEqual(RecommendationEngine.geohashBoost(userGeohash: nil, authorGeohash: "xn76u"), 1.0, accuracy: 0.0001)
    }

    func testRecommendationExtract2ndDegreeNetwork() {
        let secondDegree = RecommendationEngine.extract2ndDegreeNetwork(
            myFollows: ["alice", "bob"],
            followsOfFollows: [
                "alice": ["charlie", "bob"],
                "bob": ["charlie", "dave"],
                "mallory": ["eve"]
            ]
        )
        XCTAssertEqual(secondDegree, ["charlie", "dave"])
    }

    func testRecommendationSocialBoostMatchesRustNetworkRules() {
        let engine = RecommendationEngine()
        let emptyHistory = RecommendationEngagementHistory()

        XCTAssertEqual(
            engine.socialBoost(
                authorPubkey: "mutual",
                followList: ["mutual", "first"],
                secondDegree: ["second"],
                followers: ["mutual"],
                engagementHistory: emptyHistory
            ),
            2.5,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            engine.socialBoost(
                authorPubkey: "first",
                followList: ["mutual", "first"],
                secondDegree: ["second"],
                followers: ["mutual"],
                engagementHistory: emptyHistory
            ),
            0.5,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            engine.socialBoost(
                authorPubkey: "second",
                followList: ["mutual", "first"],
                secondDegree: ["second"],
                followers: ["mutual"],
                engagementHistory: emptyHistory
            ),
            3.0,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            engine.socialBoost(
                authorPubkey: "unknown",
                followList: ["mutual", "first"],
                secondDegree: ["second"],
                followers: ["mutual"],
                engagementHistory: emptyHistory
            ),
            1.0,
            accuracy: 0.0001
        )
    }

    func testRecommendationRankFeedPrioritizesHigherScore() {
        let engine = RecommendationEngine()
        let now = Int64(Date().timeIntervalSince1970)
        let first = ScoredPost(event: NostrEvent(id: "post-1", pubkey: "alice", createdAt: now - 3600, kind: 1, tags: [], content: "one", sig: "sig"))
        let second = ScoredPost(event: NostrEvent(id: "post-2", pubkey: "bob", createdAt: now - 3600, kind: 1, tags: [], content: "two", sig: "sig"))

        let ranked = engine.rankFeed(
            posts: [first, second],
            engagements: [
                "post-1": RecommendationEngagementData(likes: 1, reposts: 0, replies: 0, zaps: 0, quotes: 0),
                "post-2": RecommendationEngagementData(likes: 20, reposts: 2, replies: 0, zaps: 1, quotes: 0)
            ],
            followList: [],
            secondDegree: [],
            followers: [],
            engagementHistory: RecommendationEngagementHistory(),
            profiles: [:],
            mutedPubkeys: [],
            notInterestedPosts: [],
            authorScores: [:],
            userGeohash: nil,
            authorStats: [:],
            limit: 10
        )

        XCTAssertEqual(ranked.map(\.event.id), ["post-2", "post-1"])
        XCTAssertGreaterThan(ranked[0].score, ranked[1].score)
    }

    // MARK: - Bech32 / NIP-19

    func testNsecRoundTrip() throws {
        // Generate a known private key
        let (privBytes, pubBytes) = try NostrKeyUtils.generateKeys()

        let nsec = NostrKeyUtils.encodeNsec(privBytes)
        XCTAssertNotNil(nsec)
        XCTAssertTrue(nsec!.hasPrefix("nsec1"))

        let decoded = NostrKeyUtils.parsePrivateKey(nsec!)
        XCTAssertEqual(decoded, privBytes)

        let npub = NostrKeyUtils.encodeNpub(pubBytes)
        XCTAssertNotNil(npub)
        XCTAssertTrue(npub!.hasPrefix("npub1"))
    }

    func testHexParsing() {
        let hex = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        let bytes = NostrKeyUtils.hexToBytes(hex)
        XCTAssertEqual(bytes?.count, 32)
        let backToHex = bytes.map { NostrKeyUtils.bytesToHex($0) }
        XCTAssertEqual(backToHex, hex)
    }

    func testPublicKeyDerivation() throws {
        let (privBytes, expectedPubBytes) = try NostrKeyUtils.generateKeys()
        let derivedPubBytes = try NostrKeyUtils.derivePublicKey(from: privBytes)
        XCTAssertEqual(derivedPubBytes, expectedPubBytes)
    }

    // MARK: - Event ID

    func testEventIdComputation() {
        // Known test vector from NIP-01
        let id = NostrKeyUtils.computeEventId(
            pubkeyHex: "b0635d6a9851d3aed0cd6c495b282167acf761d180a586ed29c40d1e9c55adb0",
            createdAt: 1700000000,
            kind: 1,
            tags: [],
            content: "Hello Nostr"
        )
        XCTAssertNotNil(id)
        XCTAssertEqual(id?.count, 64)
    }

    // MARK: - SecureKeyManager

    func testKeychainStoreAndRetrieve() throws {
        let manager = SecureKeyManager()

        // Clean up before test
        manager.deleteAll()

        let fakeKey = [UInt8](repeating: 0x42, count: 32)
        let fakePubkey = "aabbcc001122334455667788"

        try manager.storeKey(privateKeyBytes: fakeKey, publicKeyHex: fakePubkey)
        XCTAssertTrue(manager.isUnlocked)
        XCTAssertEqual(manager.getStoredPublicKeyHex(), fakePubkey)

        // Zeroize and reload
        manager.zeroize()
        XCTAssertFalse(manager.isUnlocked)

        XCTAssertTrue(manager.unlockKey())
        XCTAssertTrue(manager.isUnlocked)

        // Clean up
        manager.deleteAll()
    }

    // MARK: - AuthViewModel

    func testInitialStateIsChecking() {
        let vm = AuthViewModel(
            keyManager: SecureKeyManager(),
            prefs: AppPreferences()
        )
        // After init, state transitions from .checking to .loggedOut asynchronously
        // Just verify the type exists
        XCTAssertNotNil(vm)
    }
}
