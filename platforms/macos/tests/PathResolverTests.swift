import Foundation
import XCTest
@testable import TranslateTheDamnCore

final class PathResolverTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("PathResolverTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        addTeardownBlock { [base] in
            try? FileManager.default.removeItem(at: base)
        }
        return base
    }

    private func makeDummyExecutable(named name: String, in directory: URL, executable: Bool) -> URL {
        let url = directory.appendingPathComponent(name)
        let script = Data("#!/bin/sh\necho ok\n".utf8)
        FileManager.default.createFile(atPath: url.path, contents: script, attributes: nil)

        if executable {
            // 0o755 = owner read/write/execute, group/other read/execute.
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        } else {
            // Explicitly non-executable.
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        }

        return url
    }

    // MARK: - Acceptance tests

    func testResolveFindsExecutableOnPATH() throws {
        let dir = try makeTempDir()
        let expected = makeDummyExecutable(named: "mytool", in: dir, executable: true)

        let resolver = PathResolver(
            knownDirs: [],
            extraPathProvider: { [] },
            pathEnvironment: dir.path
        )

        XCTAssertEqual(resolver.resolve("mytool"), expected.path)
    }

    func testResolveFindsExecutableInKnownInstallPaths() throws {
        let dir = try makeTempDir()
        let expected = makeDummyExecutable(named: "claude", in: dir, executable: true)

        let resolver = PathResolver(
            knownDirs: [dir.path],
            extraPathProvider: { [] },
            pathEnvironment: "" // make sure PATH is empty
        )

        XCTAssertEqual(resolver.resolve("claude"), expected.path)
    }

    func testResolveRespectsExecuteBit() throws {
        let dir = try makeTempDir()
        _ = makeDummyExecutable(named: "not-runnable", in: dir, executable: false)

        let resolver = PathResolver(
            knownDirs: [dir.path],
            extraPathProvider: { [] },
            pathEnvironment: ""
        )

        XCTAssertNil(resolver.resolve("not-runnable"))
    }

    func testResolveReturnsNilWhenNotFound() {
        let resolver = PathResolver(
            knownDirs: [],
            extraPathProvider: { [] },
            pathEnvironment: ""
        )

        XCTAssertNil(resolver.resolve("definitely-not-installed-6f3a9b"))
    }

    func testResolveUsesInjectedExtraPathProvider() throws {
        let dir = try makeTempDir()
        let expected = makeDummyExecutable(named: "shelltool", in: dir, executable: true)

        var providerCalled = false
        let resolver = PathResolver(
            knownDirs: [],
            extraPathProvider: {
                providerCalled = true
                return [dir.path]
            },
            pathEnvironment: ""
        )

        XCTAssertEqual(resolver.resolve("shelltool"), expected.path)
        XCTAssertTrue(providerCalled, "extraPathProvider should be invoked for the fallback search")
    }

    func testResolvePrefersPATHOverKnownDirs() throws {
        let pathDir = try makeTempDir()
        let knownDir = try makeTempDir()
        let expected = makeDummyExecutable(named: "prefertool", in: pathDir, executable: true)
        _ = makeDummyExecutable(named: "prefertool", in: knownDir, executable: true)

        let resolver = PathResolver(
            knownDirs: [knownDir.path],
            extraPathProvider: { [] },
            pathEnvironment: pathDir.path
        )

        XCTAssertEqual(resolver.resolve("prefertool"), expected.path)
    }
}
