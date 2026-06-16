namespace TranslateTheDamn.Core.Util;

/// <summary>Substitutes the source text into the configurable prompt template.</summary>
public static class PromptBuilder
{
    public const string Placeholder = "{content}";

    public static string Build(string template, string content)
    {
        if (string.IsNullOrEmpty(template)) return content;
        if (template.Contains(Placeholder, StringComparison.Ordinal))
            return template.Replace(Placeholder, content);
        // No placeholder present: append the content after the rules.
        return template.TrimEnd() + "\n\n" + content;
    }
}
