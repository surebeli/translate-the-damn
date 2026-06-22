using System.Text.Json;
using TranslateTheDamn.Core;
using TranslateTheDamn.Core.Backends;
using TranslateTheDamn.Core.Backends.Manifest;
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

        // --- pure functions --- (each block tags its vector so per-vector results can be emitted)
        Check.Vector("prompt-builder");
        Each(dir, "prompt-builder.json", (name, input, expected) =>
        {
            var r = PromptBuilder.Build(input.GetProperty("template").GetString()!, input.GetProperty("content").GetString()!);
            Check.Eq(expected.GetString(), r, $"conformance prompt-builder [{name}]");
        });

        Check.Vector("ansi-stripper");
        Each(dir, "ansi-stripper.json", (name, input, expected) =>
        {
            var s = Markers(input.GetProperty("s").GetString());
            Check.Eq(expected.GetString(), AnsiStripper.Strip(s), $"conformance ansi-stripper [{name}]");
        });

        Check.Vector("popup-sizing");
        Each(dir, "popup-sizing.json", (name, input, expected) =>
        {
            var cls = PopupSizing.SizeClass(input.GetProperty("sourceChars").GetInt32());
            Check.Eq(expected.GetString(), cls, $"conformance popup-sizing [{name}]");
        });

        Check.Vector("hotkey-parser");
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
        RunEffortTiers(dir);
        RunDoctorProbe(dir);
        RunDoctorClassify(dir);
        RunCredentialDiscovery(dir);
        Check.Vector(null); // stop attributing to any vector
    }

    // --- per-vendor effort tiers declared in the manifest ---
    private static void RunEffortTiers(string dir)
    {
        var path = Path.Combine(dir, "effort-tiers.json");
        if (!File.Exists(path)) { Check.True(false, "conformance file exists: effort-tiers.json"); return; }

        var manifest = BackendManifest.Load();
        using var vec = JsonDocument.Parse(File.ReadAllText(path));
        foreach (var c in vec.RootElement.GetProperty("cases").EnumerateArray())
        {
            var backend = c.GetProperty("backend").GetString()!;
            var expected = string.Join(",", c.GetProperty("tiers").EnumerateArray().Select(x => x.GetString()));
            var actual = string.Join(",", (manifest.Backends.TryGetValue(backend, out var def) ? def.EffortTiers : null) ?? new List<string>());
            Check.Eq(expected, actual, $"conformance effort-tiers [{backend}]");
        }
    }

    // --- per-vendor doctor probe argv/kind declared in the manifest ---
    private static void RunDoctorProbe(string dir)
    {
        var path = Path.Combine(dir, "doctor-probe.json");
        if (!File.Exists(path)) { Check.True(false, "conformance file exists: doctor-probe.json"); return; }

        var manifest = BackendManifest.Load();
        using var vec = JsonDocument.Parse(File.ReadAllText(path));
        foreach (var c in vec.RootElement.GetProperty("cases").EnumerateArray())
        {
            var backend = c.GetProperty("backend").GetString()!;
            manifest.Backends.TryGetValue(backend, out var def);
            var probe = def?.Probe;
            if (c.TryGetProperty("args", out var argsEl))
            {
                if (argsEl.ValueKind == JsonValueKind.Null)
                    Check.True(probe?.Args is null || probe.Args.Count == 0, $"conformance doctor-probe [{backend}] presence-only (no argv)");
                else
                {
                    var expected = string.Join(" ", argsEl.EnumerateArray().Select(x => x.GetString()));
                    Check.Eq(expected, string.Join(" ", probe?.Args ?? new List<string>()), $"conformance doctor-probe [{backend}] argv");
                }
            }
            if (c.TryGetProperty("kind", out var kindEl))
                Check.Eq(kindEl.GetString(), probe?.Kind, $"conformance doctor-probe [{backend}] kind");
            if (c.TryGetProperty("network", out var netEl))
                Check.Eq(netEl.GetBoolean(), probe?.Network ?? false, $"conformance doctor-probe [{backend}] network");
            if (c.TryGetProperty("retries", out var retEl))
                Check.Eq(retEl.GetInt32(), probe?.Retries ?? 0, $"conformance doctor-probe [{backend}] retries");
            if (c.TryGetProperty("successSignatures", out var ssEl))
                Check.Eq(string.Join("|", ssEl.EnumerateArray().Select(x => x.GetString())), string.Join("|", probe?.SuccessSignatures ?? new List<string>()), $"conformance doctor-probe [{backend}] successSignatures");
            if (c.TryGetProperty("failSignatures", out var fsEl))
                Check.Eq(string.Join("|", fsEl.EnumerateArray().Select(x => x.GetString())), string.Join("|", probe?.FailSignatures ?? new List<string>()), $"conformance doctor-probe [{backend}] failSignatures");
            if (c.TryGetProperty("failWins", out var fwEl))
                Check.Eq(fwEl.GetBoolean(), probe?.FailWins ?? false, $"conformance doctor-probe [{backend}] failWins");
        }
    }

    // --- generic auth/connectivity classifier (success-wins; agy transient regression) ---
    private static void RunDoctorClassify(string dir)
    {
        var path = Path.Combine(dir, "doctor-classify.json");
        if (!File.Exists(path)) { Check.True(false, "conformance file exists: doctor-classify.json"); return; }

        using var vec = JsonDocument.Parse(File.ReadAllText(path));
        foreach (var c in vec.RootElement.GetProperty("cases").EnumerateArray())
        {
            var name = c.GetProperty("name").GetString() ?? "?";
            var success = c.GetProperty("success").EnumerateArray().Select(x => x.GetString()!).ToList();
            var fail = c.GetProperty("fail").EnumerateArray().Select(x => x.GetString()!).ToList();
            var text = c.GetProperty("text").GetString() ?? string.Empty;
            var expected = c.GetProperty("out").GetString();
            var failWins = c.TryGetProperty("failWins", out var fwEl) && fwEl.GetBoolean();
            var got = ProbeClassifier.Classify(success, fail, text, failWins) switch
            {
                ProbeStatus.Ok => "ok",
                ProbeStatus.Fail => "fail",
                _ => "unknown"
            };
            Check.Eq(expected, got, $"conformance doctor-classify [{name}]");
        }
    }

    // --- serialized default-config assertions ---
    private static void RunConfigDefaults(string dir)
    {
        Check.Vector("config-defaults");
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
        Check.Vector("backend-requests");
        var path = Path.Combine(dir, "backend-requests.json");
        if (!File.Exists(path)) { Check.True(false, "conformance file exists: backend-requests.json"); return; }

        using var vec = JsonDocument.Parse(File.ReadAllText(path));
        foreach (var c in vec.RootElement.GetProperty("cases").EnumerateArray())
        {
            var name = c.GetProperty("name").GetString() ?? "?";
            var backend = c.GetProperty("backend").GetString()!;
            var bc = BackendFromConfig(c.GetProperty("config"));
            var tmpl = c.TryGetProperty("promptTemplate", out var pt) ? (pt.GetString() ?? "") : "";
            var t = Tb.Http(backend, bc, tmpl);
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
            Protocol = S("protocol"),
            Model = S("model"),
            Target = S("target"),
            Source = S("source"),
            Format = S("format"),
            TargetLanguage = S("targetLanguage"),
            SourceLanguage = S("sourceLanguage")
        };
    }

    // --- credential auto-discovery: the static-key/OAuth import boundary ---
    private static void RunCredentialDiscovery(string dir)
    {
        var path = Path.Combine(dir, "credential-discovery.json");
        if (!File.Exists(path)) { Check.True(false, "conformance file exists: credential-discovery.json"); return; }

        using var vec = JsonDocument.Parse(File.ReadAllText(path));
        foreach (var c in vec.RootElement.GetProperty("cases").EnumerateArray())
        {
            var name = c.GetProperty("name").GetString() ?? "?";
            var got = CredentialClassifier.Classify("test", c.GetProperty("baseUrl").GetString(), c.GetProperty("key").GetString());
            var ex = c.GetProperty("expect");
            var wantImport = ex.GetProperty("import").GetBoolean();
            Check.Eq(wantImport, got is not null, $"cred-classify [{name}] import?");
            if (wantImport && got is not null)
            {
                if (ex.TryGetProperty("provider", out var pv)) Check.Eq(pv.GetString(), got.Provider, $"cred-classify [{name}] provider");
                if (ex.TryGetProperty("protocol", out var pr)) Check.Eq(pr.GetString(), got.Protocol, $"cred-classify [{name}] protocol");
                if (ex.TryGetProperty("suggestedId", out var si)) Check.Eq(si.GetString(), got.SuggestedId, $"cred-classify [{name}] suggestedId");
            }
        }
    }

    // --- stateful cache scenarios ---
    private static async Task RunCacheScenariosAsync(string dir)
    {
        Check.Vector("pipeline-cache");
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
