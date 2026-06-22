import Foundation

/// Classifies a backend auth/connectivity probe's output into ok / fail / unknown — the shared rule
/// behind the doctor (spec §9). Mirrors the `doctor-classify` conformance vector exactly.
///
/// Normalize both the output and every signature by lowercasing and stripping ALL whitespace, then:
///   - default (SUCCESS-WINS): any success signature → ok; else any fail signature → fail; else unknown.
///   - `failWins` (opencode): check fail FIRST — `"0 credentials"` contains the success marker
///     `"credentials"` as a substring, so success-wins would wrongly read it as ok.
///
/// Whitespace stripping is load-bearing: it defeats the codex trap (`"not logged in"` must NOT match
/// success `"logged in using"`) and makes compact-vs-pretty JSON equivalent. SUCCESS-WINS also keeps
/// the agy keyring transient (a `"not logged into Antigravity"` line FOLLOWED by a success marker)
/// classified as ok rather than a spurious logout.
public enum ProbeClassifier {
    public static func classify(_ text: String,
                                success: [String],
                                fail: [String],
                                failWins: Bool = false) -> String {
        func norm(_ s: String) -> String { s.lowercased().filter { !$0.isWhitespace } }
        let nt = norm(text)
        let hasSuccess = success.contains { let n = norm($0); return !n.isEmpty && nt.contains(n) }
        let hasFail = fail.contains { let n = norm($0); return !n.isEmpty && nt.contains(n) }
        if failWins {
            if hasFail { return "fail" }
            if hasSuccess { return "ok" }
        } else {
            if hasSuccess { return "ok" }
            if hasFail { return "fail" }
        }
        return "unknown"
    }
}
