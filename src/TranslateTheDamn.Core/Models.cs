namespace TranslateTheDamn.Core;

/// <summary>Outcome classification for a translation attempt (mirrors hopper's parseResult taxonomy).</summary>
public enum TranslateStatus
{
    Success,
    AuthFail,
    Timeout,
    NotFound,    // backend binary / endpoint not found
    BadOutput,   // ran but produced no usable text
    UnknownFail
}

public enum BackendKind { Cli, Http }

public enum AuthLevel { Ready, Unknown, Missing }

/// <summary>Soft auth preflight result; drives the settings "auth lamp".</summary>
public sealed record AuthState(AuthLevel Level, string Detail)
{
    public static AuthState Ready(string detail = "") => new(AuthLevel.Ready, detail);
    public static AuthState Unknown(string detail = "") => new(AuthLevel.Unknown, detail);
    public static AuthState Missing(string detail) => new(AuthLevel.Missing, detail);
}

/// <summary>A unit of work for a translator. Text is the raw source captured from the clipboard.</summary>
public sealed record TranslationRequest(string Text);

/// <summary>Result of a translation attempt.</summary>
public sealed record TranslationResult(string Text, TranslateStatus Status, string? Error = null)
{
    public bool Ok => Status == TranslateStatus.Success;

    public static TranslationResult Successful(string text) => new(text, TranslateStatus.Success);
    public static TranslationResult Failure(TranslateStatus status, string error) => new(string.Empty, status, error);
}
