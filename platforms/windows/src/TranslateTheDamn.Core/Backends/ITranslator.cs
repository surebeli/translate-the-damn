using TranslateTheDamn.Core.Util;

namespace TranslateTheDamn.Core.Backends;

/// <summary>One backend, taming a CLI or an HTTP API into a clean text→text translation call.</summary>
public interface ITranslator
{
    string Id { get; }
    BackendKind Kind { get; }
    Task<TranslationResult> TranslateAsync(TranslationRequest request, CancellationToken ct);
    Task<AuthState> CheckAuthAsync(CancellationToken ct);
}

/// <summary>A built CLI invocation (pure, testable) — argv plus how the prompt reaches the process.</summary>
public sealed record CliInvocation(
    IReadOnlyList<string> Args,
    StdinMode StdinMode,
    string? StdinText,
    bool WantsLogFile = false);
