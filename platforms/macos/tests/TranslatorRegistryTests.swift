import Foundation
import XCTest
@testable import TranslateTheDamnCore

final class TranslatorRegistryTests: XCTestCase {

    func testRegistryReturnsProcessTranslatorForCliBackend() {
        let registry = TranslatorRegistry()
        let config = BackendConfig(type: "cli")
        let translator = registry.translator(for: "claude", config: config)

        XCTAssertNotNil(translator, "Should return a translator for known cli backend 'claude'")
        XCTAssertTrue(translator is ProcessTranslator, "Should be ProcessTranslator type")
    }

    func testRegistryReturnsHttpTranslatorForHttpBackend() {
        let registry = TranslatorRegistry()
        let config = BackendConfig(type: "http", apiKey: "test-key")
        let translator = registry.translator(for: "google-v2", config: config)

        XCTAssertNotNil(translator, "Should return a translator for known http backend 'google-v2'")
        XCTAssertTrue(translator is HttpTranslator, "Should be HttpTranslator type")
    }

    func testRegistryReturnsNilForUnknownBackend() {
        let registry = TranslatorRegistry()
        let config = BackendConfig(type: "cli")
        let translator = registry.translator(for: "nonexistent-backend-xyz", config: config)

        XCTAssertNil(translator, "Should return nil for unknown backend")
    }

    func testRegistryCachesTranslators() {
        let registry = TranslatorRegistry()
        let config = BackendConfig(type: "cli")
        let t1 = registry.translator(for: "claude", config: config)
        let t2 = registry.translator(for: "claude", config: config)

        XCTAssertNotNil(t1)
        XCTAssertNotNil(t2)
        XCTAssertTrue(t1 as AnyObject === t2 as AnyObject, "Should return the same cached instance")
    }

    func testRegistryManualRegister() {
        let registry = TranslatorRegistry()
        let config = BackendConfig(type: "cli", command: "/bin/echo")
        let customTranslator = ProcessTranslator(id: "custom-cli", config: config)
        registry.register(customTranslator, for: "custom-cli")

        let retrieved = registry.translator(for: "custom-cli", config: config)
        XCTAssertNotNil(retrieved)
        XCTAssertTrue(retrieved as AnyObject === customTranslator as AnyObject)
    }

    func testRegistryIds() {
        let registry = TranslatorRegistry()
        let config = BackendConfig(type: "cli")
        _ = registry.translator(for: "claude", config: config)
        _ = registry.translator(for: "google-v2", config: BackendConfig(type: "http", apiKey: "test"))

        XCTAssertTrue(registry.ids.contains("claude"))
        XCTAssertTrue(registry.ids.contains("google-v2"))
    }

    func testRegistryCaseInsensitive() {
        let registry = TranslatorRegistry()
        let config = BackendConfig(type: "cli")
        let t1 = registry.translator(for: "CLAUDE", config: config)
        let t2 = registry.translator(for: "claude", config: config)

        XCTAssertNotNil(t1)
        XCTAssertNotNil(t2)
        XCTAssertTrue(t1 as AnyObject === t2 as AnyObject, "Should return the same instance regardless of case")
    }

    func testRegistryAllCliBackends() {
        let registry = TranslatorRegistry()
        let config = BackendConfig(type: "cli")

        for id in ["claude", "codex", "copilot", "agy"] {
            let translator = registry.translator(for: id, config: config)
            XCTAssertNotNil(translator, "Should support \(id)")
            XCTAssertTrue(translator is ProcessTranslator, "\(id) should be ProcessTranslator")
        }
    }

    func testRegistryAllHttpBackends() {
        let registry = TranslatorRegistry()
        let config = BackendConfig(type: "http")

        for id in ["google-v2", "doubao"] {
            let translator = registry.translator(for: id, config: config)
            XCTAssertNotNil(translator, "Should support \(id)")
            XCTAssertTrue(translator is HttpTranslator, "\(id) should be HttpTranslator")
        }
    }

    func testRegistryTranslatorProtocol() {
        let registry = TranslatorRegistry()
        let config = BackendConfig(type: "cli", command: "/bin/echo")
        let translator = registry.translator(for: "claude", config: config)

        XCTAssertNotNil(translator)

        let result = translator!.translate(text: "test", model: "gpt-4")
        XCTAssertTrue(result.ok)
    }
}
