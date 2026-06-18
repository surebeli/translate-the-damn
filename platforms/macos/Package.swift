// swift-tools-version: 6.0
// M1 — SwiftPM scaffold + conformance runner for the translate-the-damn macOS port.
// See CONSTITUTION.md (Law 2: shared conformance vectors are the truth) and
// platforms/macos/CLAUDE.md. Zero external dependencies (Foundation only).
import PackageDescription

let package = Package(
    name: "TranslateTheDamn",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure-logic core (stubs in M1; real impl lands in M2). Native Swift, Foundation only.
        .target(
            name: "TranslateTheDamnCore",
            path: "src/Core"
        ),
        // Conformance runner: loads the repo-root /conformance vectors and feeds them through the
        // core stubs. This is the parity gate — every later milestone is "done" only when it goes
        // green here. RED in M1 by design (stubs).
        .testTarget(
            name: "TranslateTheDamnConformanceTests",
            dependencies: ["TranslateTheDamnCore"],
            path: "tests"
        ),
    ]
)
