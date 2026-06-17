using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace TranslateTheDamn.Core.Backends.Manifest;

/// <summary>
/// Small, dependency-free engine that turns a backend's manifest definition + variables into a
/// concrete request: <see cref="Subst"/> fills <c>{placeholder}</c> tokens, <see cref="BuildBody"/>
/// renders a JSON body template (dropping empty <c>omitWhenEmpty</c> keys), and <see cref="Eval"/>
/// reads a value out of a response via a small path syntax (<c>a.b[0].c</c>, <c>arr[key=value].x</c>).
/// </summary>
public static class ManifestEngine
{
    /// <summary>Replace every <c>{name}</c> with vars[name] (empty string if absent).</summary>
    public static string Subst(string template, IReadOnlyDictionary<string, string> vars)
    {
        if (string.IsNullOrEmpty(template) || template.IndexOf('{') < 0) return template;

        var sb = new StringBuilder(template.Length);
        var i = 0;
        while (i < template.Length)
        {
            var open = template.IndexOf('{', i);
            if (open < 0) { sb.Append(template, i, template.Length - i); break; }
            var close = template.IndexOf('}', open + 1);
            if (close < 0) { sb.Append(template, i, template.Length - i); break; }

            sb.Append(template, i, open - i);
            var name = template.Substring(open + 1, close - open - 1);
            sb.Append(vars.TryGetValue(name, out var val) ? val : string.Empty);
            i = close + 1;
        }
        return sb.ToString();
    }

    /// <summary>Render a JSON body template: substitute string leaves, then drop any property whose
    /// key is in <paramref name="omitWhenEmpty"/> and whose rendered value is empty.</summary>
    public static string BuildBody(JsonElement template, IReadOnlyDictionary<string, string> vars, ISet<string> omitWhenEmpty)
    {
        var node = JsonNode.Parse(template.GetRawText());
        var built = BuildNode(node, vars, omitWhenEmpty);
        return built?.ToJsonString() ?? "{}";
    }

    private static JsonNode? BuildNode(JsonNode? node, IReadOnlyDictionary<string, string> vars, ISet<string> omit)
    {
        switch (node)
        {
            case JsonObject obj:
                var res = new JsonObject();
                foreach (var kv in obj)
                {
                    var child = BuildNode(kv.Value, vars, omit);
                    if (omit.Contains(kv.Key) && IsEmptyString(child)) continue;
                    res[kv.Key] = child;
                }
                return res;

            case JsonArray arr:
                var ra = new JsonArray();
                foreach (var item in arr) ra.Add(BuildNode(item, vars, omit));
                return ra;

            case JsonValue val:
                return val.TryGetValue<string>(out var s)
                    ? JsonValue.Create(Subst(s, vars))
                    : JsonNode.Parse(val.ToJsonString());

            default:
                return null;
        }
    }

    private static bool IsEmptyString(JsonNode? node) =>
        node is JsonValue v && v.TryGetValue<string>(out var s) && string.IsNullOrEmpty(s);

    /// <summary>Read a string out of a JSON document by path: <c>data.translations[0].translatedText</c>
    /// or <c>output[type=message].content[type=output_text].text</c>. Returns null if not found.</summary>
    public static string? Eval(JsonElement root, string path)
    {
        var cur = root;
        foreach (var rawSeg in path.Split('.'))
        {
            var seg = rawSeg;
            string? bracket = null;

            var lb = seg.IndexOf('[');
            if (lb >= 0)
            {
                var rb = seg.IndexOf(']', lb + 1);
                if (rb < 0) return null;
                bracket = seg.Substring(lb + 1, rb - lb - 1);
                seg = seg[..lb];
            }

            if (seg.Length > 0)
            {
                if (cur.ValueKind != JsonValueKind.Object || !cur.TryGetProperty(seg, out cur)) return null;
            }

            if (bracket is not null)
            {
                if (cur.ValueKind != JsonValueKind.Array) return null;
                var eq = bracket.IndexOf('=');
                if (eq >= 0)
                {
                    var key = bracket[..eq];
                    var value = bracket[(eq + 1)..];
                    var found = false;
                    foreach (var el in cur.EnumerateArray())
                    {
                        if (el.ValueKind == JsonValueKind.Object && el.TryGetProperty(key, out var kv)
                            && kv.ValueKind == JsonValueKind.String && kv.GetString() == value)
                        {
                            cur = el; found = true; break;
                        }
                    }
                    if (!found) return null;
                }
                else if (int.TryParse(bracket, out var idx))
                {
                    if (idx < 0 || idx >= cur.GetArrayLength()) return null;
                    cur = cur[idx];
                }
                else return null;
            }
        }

        // Only a string is a valid translated value; anything else is a path miss -> null (fail cleanly).
        return cur.ValueKind == JsonValueKind.String ? cur.GetString() : null;
    }
}
