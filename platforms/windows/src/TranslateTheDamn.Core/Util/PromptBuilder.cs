namespace TranslateTheDamn.Core.Util;

/// <summary>Substitutes the source text into the configurable prompt template.</summary>
public static class PromptBuilder
{
    public const string Placeholder = "{content}";
    public const string TargetPlaceholder = "{target}";

    /// <summary>Resolve the unified target language into the template's <c>{target}</c> placeholder.
    /// Done ONCE at registry build time (not per request). Templates without <c>{target}</c> are unchanged.</summary>
    public static string WithTarget(string template, string? target) =>
        string.IsNullOrEmpty(template) ? template : template.Replace(TargetPlaceholder, target ?? string.Empty);

    public static string Build(string template, string content)
    {
        if (string.IsNullOrEmpty(template)) return content;
        if (template.Contains(Placeholder, StringComparison.Ordinal))
            return template.Replace(Placeholder, content);
        // No placeholder present: append the content after the rules.
        return template.TrimEnd() + "\n\n" + content;
    }
}
