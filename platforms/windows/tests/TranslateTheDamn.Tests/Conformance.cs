using System.Text.Json;
using TranslateTheDamn.Core;
using TranslateTheDamn.Core.Backends;
using TranslateTheDamn.Core.Backends.Http;
using TranslateTheDamn.Core.Config;
using TranslateTheDamn.Core.Util;

namespace TranslateTheDamn.Tests;

/// <summary>
/// Windows (reference) runner for the language-neutral conformance vectors in <c>/conformance</c>.
/// Feeds each case through the REAL Core implementation and asserts the expected output, so the
/// Windows column actually satisfies the shared vectors (Constitution Law 2). macOS/Linux add their
/// own runner over the same JSON.
/// </summary>
public static class Conformance
{
    private static readonly string Esc = ((char)0x1B).ToString();

    public static async Task RunAsync()
    {
        var dir = FindUp("conformance");
        if (dir is null) { Check.True(false, "conformance/ directory located"); return; }

        // --- pure functions ---
        Each(dir, "prompt-builder.json", (name, input, expected) =>
        {
            var r = PromptBuilder.Build(input.GetProperty("template").GetString()!, input.GetProperty("content").GetString()!);
            Check.Eq(expected.GetString(), r, $"conformance prompt-builder [{name}]");
        });

        Each(dir, "ansi-stripper.json", (name, input, expected) =>
        {
            var s = Markers(input.GetProperty("s").GetString());
            Check.Eq(expected.GetString(), AnsiStripper.Strip(s), $"conformance ansi-stripper [{name}]");
        });

        Each(dir, "hotkey-parser.json", (name, input, expected) =>
        {
            var spec = HotkeyParser.Parse(input.GetProperty("text").GetString());
            Check.Eq(expected.GetProperty("isValid").GetBoolean(), spec.IsValid, $"conformance hotkey [{name}]: isValid");
            if (expected.TryGetProperty("virtualKey", out var vk)) Check.Eq((uint)vk.GetInt32(), spec.VirtualKey, $"conformance hotkey [{name}]: virtualKey");
            if (expected.TryGetProperty("display", out var disp)) Check.Eq(disp.GetString(), spec.Display, $"conformance hotkey [{name}]: display");
            if (Flag(expected, "hasControl")) Check.True((spec.Modifiers & HotkeyParser.MOD_CONTROL) != 0, $"conformance hotkey [{name}]: Control");
            if (Flag(expected, "hasAlt")) Check.True((spec.Modifiers & HotkeyParser.MOD_ALT) != 0, $"conformance hotkey [{name}]: Alt");
            if (Flag(expected, "hasShift")) Check.True((spec.Modifiers & HotkeyParser.MOD_SHIFT) != 0, $"conformance hotkey [{name}]: Shift");
            if (Flag(expected, "hasWin")) Check.True((spec.Modifiers & HotkeyParser.MOD_WIN) != 0, $"conformance hotkey [{name}]: Win");
        });

        RunConfigDefaults(dir);
        RunBackendRequests(dir);
        await RunCacheScenariosAsync(dir);
    }

    // --- serialized default-config assertions ---
    private static void RunConfigDefaults(string dir)
    {
        var path = Path.Combine(dir, "config-defaults.json");
        if (!File.Exists(path)) { Check.True(false, "conformance file exists: config-defaults.json"); return; }

        var json = JsonSerializer.Serialize(DefaultConfig.Create(), ConfigService.JsonOptions);
        using var actual = JsonDocument.Parse(json);
        using var vec = JsonDocument.Parse(File.ReadAllText(path));

        foreach (var a in vec.RootElement.GetProperty("assert").EnumerateArray())
        {
            var p = a.GetProperty("path").GetString()!;
            if (!TryNav(actual.RootElement, p, out var el)) { Check.True(false, $"conformance config: path '{p}' exists"); continue; }

            if (a.TryGetProperty("equals", out var eq))
                Check.True(JsonEquals(el, eq), $"conformance config [{p}] equals {eq.GetRawText()}");
            else if (a.TryGetProperty("count", out var cnt))
                Check.Eq(cnt.GetInt32(), CountOf(el), $"conformance config [{p}] count");
            else if (a.TryGetProperty("contains", out var c))
                Check.True(el.ValueKind == JsonValueKind.String && el.GetString()!.Contains(c.GetString()!, StringComparison.Ordinal), $"conformance config [{p}] contains '{c.GetString()}'");
            else if (a.TryGetProperty("containsItem", out var ci))
                Check.True(ArrayContains(el, ci.GetString()!), $"conformance config [{p}] containsItem '{ci.GetString()}'");
        }
    }

    // --- HTTP backend request building ---
    private static void RunBackendRequests(string dir)
    {
        var path = Path.Combine(dir, "backend-requests.json");
        if (!File.Exists(path)) { Check.True(false, "conformance file exists: backend-requests.json"); return; }

        using var vec = JsonDocument.Parse(File.ReadAllText(path));
        foreach (var c in vec.RootElement.GetProperty("cases").EnumerateArray())
        {
            var name = c.GetProperty("name").GetString() ?? "?";
            var backend = c.GetProperty("backend").GetString();
            var bc = BackendFromConfig(c.GetProperty("config"));
            HttpTranslator t = backend == "doubao" ? new DoubaoTranslator(bc) : new GoogleV2Translator(bc);
            var call = t.BuildCall(c.GetProperty("text").GetString()!);
            var ex = c.GetProperty("expect");

            if (ex.TryGetProperty("method", out var m)) Check.Eq(m.GetString(), call.Method, $"backend-req [{name}] method");
            if (ex.TryGetProperty("urlContains", out var uc))
                foreach (var s in uc.EnumerateArray()) Check.True(call.Url.Contains(s.GetString()!, StringComparison.Ordinal), $"backend-req [{name}] url ∋ '{s.GetString()}'");
            if (ex.TryGetProperty("urlNotContains", out var un))
                foreach (var s in un.EnumerateArray()) Check.True(!call.Url.Contains(s.GetString()!, StringComparison.Ordinal), $"backend-req [{name}] url ∌ '{s.GetString()}'");
            if (ex.TryGetProperty("headers", out var hs))
                foreach (var h in hs.EnumerateObject())
                    Check.True(call.Headers.TryGetValue(h.Name, out var hv) && hv == h.Value.GetString(), $"backend-req [{name}] header {h.Name}");
            if (ex.TryGetProperty("bodyContains", out var bcs))
                foreach (var s in bcs.EnumerateArray()) Check.True(call.BodyJson.Contains(s.GetString()!, StringComparison.Ordinal), $"backend-req [{name}] body ∋ {s.GetString()}");
            if (ex.TryGetProperty("bodyNotContains", out var bn))
                foreach (var s in bn.EnumerateArray()) Check.True(!call.BodyJson.Contains(s.GetString()!, StringComparison.Ordinal), $"backend-req [{name}] body ∌ {s.GetString()}");
        }
    }

    private static BackendConfig BackendFromConfig(JsonElement cfg)
    {
        string? S(string k) => cfg.TryGetProperty(k, out var v) ? v.GetString() : null;
        return new BackendConfig
        {
            Type = "http",
            ApiKey = S("apiKey"),
            Endpoint = S("endpoint"),
            Model = S("model"),
            Target = S("target"),
            Source = S("source"),
            Format = S("format"),
            TargetLanguage = S("targetLanguage"),
            SourceLanguage = S("sourceLanguage")
        };
    }

    // --- stateful cache scenarios ---
    private static async Task RunCacheScenariosAsync(string dir)
    {
        var path = Path.Combine(dir, "pipeline-cache.json");
        if (!File.Exists(path)) { Check.True(false, "conformance file exists: pipeline-cache.json"); return; }

        using var vec = JsonDocument.Parse(File.ReadAllText(path));
        foreach (var sc in vec.RootElement.GetProperty("scenarios").EnumerateArray())
        {
            var name = sc.GetProperty("name").GetString() ?? "?";
            var backend = sc.GetProperty("backend").GetString()!;

            var cfg = DefaultConfig.Create();
            cfg.General.ActiveBackend = backend;
            cfg.Backends[backend] = new BackendConfig { Type = "http", Model = "" };
            var reg = TranslatorRegistry.Build(new AppConfig());
            var fake = new FakeTranslator(backend, (req, _) => Task.FromResult(TranslationResult.Successful("T:" + req.Text)));
            reg.Add(fake);
            var pipe = new TranslationPipeline(cfg, reg);

            var i = 0;
            foreach (var step in sc.GetProperty("steps").EnumerateArray())
            {
                i++;
                cfg.Backends[backend].Model = step.GetProperty("model").GetString();
                var before = fake.Calls;
                await pipe.RunAsync(step.GetProperty("text").GetString(), TriggerSource.Hotkey);
                var delta = fake.Calls - before;
                var expectCall = step.GetProperty("expectModelCall").GetBoolean();
                Check.Eq(expectCall ? 1 : 0, delta, $"conformance cache [{name}] step {i} ({(expectCall ? "miss" : "hit")})");
            }
        }
    }

    // --- helpers ---
    private static bool Flag(JsonElement obj, string name) => obj.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.True;

    private static string Markers(string? s) => (s ?? string.Empty).Replace("<ESC>", Esc).Replace("<CR>", "\r");

    private static bool TryNav(JsonElement root, string path, out JsonElement el)
    {
        el = root;
        foreach (var seg in path.Split('.'))
        {
            if (el.ValueKind != JsonValueKind.Object || !el.TryGetProperty(seg, out var next)) { el = default; return false; }
            el = next;
        }
        return true;
    }

    private static int CountOf(JsonElement el) => el.ValueKind switch
    {
        JsonValueKind.Array => el.GetArrayLength(),
        JsonValueKind.Object => el.EnumerateObject().Count(),
        _ => -1
    };

    private static bool ArrayContains(JsonElement el, string item) =>
        el.ValueKind == JsonValueKind.Array && el.EnumerateArray().Any(x => x.ValueKind == JsonValueKind.String && x.GetString() == item);

    private static bool JsonEquals(JsonElement actual, JsonElement expected) => expected.ValueKind switch
    {
        JsonValueKind.String => actual.ValueKind == JsonValueKind.String && actual.GetString() == expected.GetString(),
        JsonValueKind.Number => actual.ValueKind == JsonValueKind.Number && actual.GetRawText() == expected.GetRawText(),
        JsonValueKind.True => actual.ValueKind == JsonValueKind.True,
        JsonValueKind.False => actual.ValueKind == JsonValueKind.False,
        _ => actual.GetRawText() == expected.GetRawText()
    };

    private static void Each(string dir, string file, Action<string, JsonElement, JsonElement> run)
    {
        var path = Path.Combine(dir, file);
        if (!File.Exists(path)) { Check.True(false, "conformance file exists: " + file); return; }
        using var doc = JsonDocument.Parse(File.ReadAllText(path));
        foreach (var c in doc.RootElement.GetProperty("cases").EnumerateArray())
            run(c.GetProperty("name").GetString() ?? "?", c.GetProperty("in"), c.GetProperty("out"));
    }

    private static string? FindUp(string dirName)
    {
        var d = new DirectoryInfo(AppContext.BaseDirectory);
        while (d is not null)
        {
            var candidate = Path.Combine(d.FullName, dirName);
            if (Directory.Exists(candidate)) return candidate;
            d = d.Parent;
        }
        return null;
    }
}
