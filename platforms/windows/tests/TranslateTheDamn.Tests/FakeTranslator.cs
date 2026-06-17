using TranslateTheDamn.Core;
using TranslateTheDamn.Core.Backends;

namespace TranslateTheDamn.Tests;

/// <summary>A controllable in-memory translator for pipeline tests (no process/network).</summary>
public sealed class FakeTranslator : ITranslator
{
    private readonly Func<TranslationRequest, CancellationToken, Task<TranslationResult>> _fn;
    public int Calls;

    public FakeTranslator(string id, Func<TranslationRequest, CancellationToken, Task<TranslationResult>> fn)
    {
        Id = id;
        _fn = fn;
    }

    public string Id { get; }
    public BackendKind Kind => BackendKind.Http;

    public Task<TranslationResult> TranslateAsync(TranslationRequest request, CancellationToken ct)
    {
        Interlocked.Increment(ref Calls);
        return _fn(request, ct);
    }

    public Task<AuthState> CheckAuthAsync(CancellationToken ct) => Task.FromResult(AuthState.Ready());
}
