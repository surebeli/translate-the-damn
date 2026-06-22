import XCTest
@testable import TranslateTheDamnCore

/// Unit tests for the pure model-enumeration helpers (mirrors the Windows ParseModels/DeriveModelsUrl tests).
final class ModelEnumeratorTests: XCTestCase {
    func testDeriveModelsUrls() {
        XCTAssertEqual(ModelEnumerator.deriveModelsUrls("https://api.deepseek.com/v1/chat/completions").first,
                       "https://api.deepseek.com/v1/models", "openai chat endpoint -> /v1/models")
        XCTAssertEqual(ModelEnumerator.deriveModelsUrls("https://api.kimi.com/coding/v1/messages").first,
                       "https://api.kimi.com/coding/v1/models", "anthropic messages endpoint -> /v1/models")

        let bare = ModelEnumerator.deriveModelsUrls("https://tokbox-api.netease.im")
        XCTAssertEqual(bare.first, "https://tokbox-api.netease.im/v1/models", "bare base -> /v1/models first")
        XCTAssertTrue(bare.contains("https://tokbox-api.netease.im/models"), "bare base -> /models fallback")

        XCTAssertEqual(ModelEnumerator.deriveModelsUrls("https://openrouter.ai/api/v1").first,
                       "https://openrouter.ai/api/v1/models", "/api/v1 base -> /api/v1/models (versioned)")
        XCTAssertEqual(ModelEnumerator.deriveModelsUrls("https://x.ai/v1").first,
                       "https://x.ai/v1/models", "/v1 base -> /v1/models (no double /v1)")
    }

    func testParseModelsJson() {
        let openai = #"{"object":"list","data":[{"id":"deepseek-v4-flash"},{"id":"deepseek-v4-pro"},{"id":"deepseek-v4-flash"}]}"#
        XCTAssertEqual(ModelEnumerator.parseModelsJson(Data(openai.utf8)), ["deepseek-v4-flash", "deepseek-v4-pro"],
                       "OpenAI data[].id, deduped + order-preserved")

        let ollama = #"{"models":[{"name":"llama3"},{"name":"qwen"}]}"#
        XCTAssertTrue(ModelEnumerator.parseModelsJson(Data(ollama.utf8)).contains("llama3"), "Ollama models[].name")

        let bareArr = #"["gpt-4o","gpt-4o-mini"]"#
        XCTAssertTrue(ModelEnumerator.parseModelsJson(Data(bareArr.utf8)).contains("gpt-4o-mini"), "bare string array")

        XCTAssertTrue(ModelEnumerator.parseModelsJson(Data("not json".utf8)).isEmpty, "non-JSON -> empty")
    }
}
