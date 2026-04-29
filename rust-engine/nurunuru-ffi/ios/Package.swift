// swift-tools-version: 5.9
// NuruNuru — iOS / macOS Swift Package
//
// Setup:
//   1. Build the XCFramework from the nurunuru-ffi crate:
//        cd rust-engine/nurunuru-ffi/bindgen && make xcframework
//      This creates ios/NuruNuruFFI.xcframework and syncs the generated
//      Swift file to Sources/NuruNuru/nurunuru_ffi.swift.
//
//   2. In Xcode: File > Add Package Dependencies > Add Local...
//      Select the `rust-engine/nurunuru-ffi/ios/` directory.
//
//   3. Import in Swift:
//        import NuruNuruFFILib
//        let client = try NuruNuruClient(secretKeyHex: nsec, dbPath: NuruNuruClient.defaultDbPath())
//        client.connect()

import PackageDescription

let package = Package(
    name: "NuruNuru",
    platforms: [
        .iOS(.v17),
        .macOS(.v13),
    ],
    products: [
        // Public API: import NuruNuruFFILib
        // ⚠️ Renamed from "NuruNuru" to avoid module name collision with the
        //    Xcode app target "NuruNuru" (causes "Multiple commands produce" error).
        .library(
            name: "NuruNuruFFILib",
            targets: ["nurunuruFFI", "NuruNuruFFILib"]
        ),
    ],
    targets: [
        // Pre-built XCFramework containing libnurunuru_ffi.a for each platform slice.
        // Produced by: cd bindgen && make xcframework
        // NOTE: Must match generated Swift import: `canImport(nurunuruFFI)`.
        .binaryTarget(
            name: "nurunuruFFI",
            path: "NuruNuruFFI.xcframework"
        ),
        // Swift wrapper target: re-exports the UniFFI-generated API and adds
        // Swift-friendly convenience extensions.
        // Sources/NuruNuru/ contains:
        //   - nurunuru_ffi.swift   (generated — copied by `make xcframework`)
        //   - NuruNuruClient+Extensions.swift (hand-written conveniences)
        // ⚠️ Renamed from "NuruNuru" to "NuruNuruFFILib" — see product note above.
        .target(
            name: "NuruNuruFFILib",
            dependencies: ["nurunuruFFI"],
            path: "Sources/NuruNuru"
        ),
    ]
)