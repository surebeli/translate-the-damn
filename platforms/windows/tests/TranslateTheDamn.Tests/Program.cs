using TranslateTheDamn.Core;
using TranslateTheDamn.Core.Backends;
using TranslateTheDamn.Core.Backends.Manifest;
using TranslateTheDamn.Core.Config;
using TranslateTheDamn.Core.Util;
using TranslateTheDamn.Tests;

// Opt-in live end-to-end check against a real, installed, authenticated CLI (not part of the
// default offline suite). Usage: dotnet run -- --live [backendId]
if (args.Contains("--scan"))
{
    Console.WriteLine("# Credential auto-discovery — discovered STATIC keys (masked):");
    var found = TranslateTheDamn.Core.Config.CredentialDiscovery.Scan();
    if (found.Count == 0) Console.WriteLine("  (none found)");
    foreach (var c in found)
        Console.WriteLine($"  {c.Provider,-26} {c.Protocol,-10} {c.BaseUrl,-46} {c.KeyMasked,-16} [{c.Source}]");
    return 0;
}

if (args.Contains("--live"))
{
    var backendId = args.FirstOrDefault(a => !a.StartsWith("--")) ?? "claude";
    Console.WriteLine($"# LIVE end-to-end via real backend: {backendId}");
    // Use the REAL user config (incl. custom http providers) so --live tests what's actually installed.
    var liveCfg = new ConfigService().LoadOrBootstrap();
    var reg = TranslatorRegistry.Build(liveCfg);
    var translator = reg.Get(backendId);
    if (translator is null) { Console.WriteLine("unknown backend"); return 2; }

    var sample = "Hello, world. The TranslationPipeline supersedes any in-flight request.";
    Console.WriteLine($"source = {sample}");
    var sw = System.Diagnostics.Stopwatch.StartNew();
    var live = await translator.TranslateAsync(new TranslationRequest(sample), CancellationToken.None);
    sw.Stop();
    Console.WriteLine($"status = {live.Status}   ({sw.ElapsedMilliseconds} ms)");
    Console.WriteLine($"text   = {live.Text}");
    if (!string.IsNullOrEmpty(live.Error)) Console.WriteLine($"error  = {live.Error}");
    return live.Ok ? 0 : 2;
}

// ---------------------------------------------------------------- ConfigService
Check.Section("ConfigService");
{
    var dir = Path.Combine(Path.GetTempPath(), "ttd-test-" + Guid.NewGuid().ToString("N"));
    try
    {
        var svc = new ConfigService(dir);
        Check.True(!File.Exists(svc.FilePath), "config absent before bootstrap");

        var cfg = svc.LoadOrBootstrap();
        Check.True(File.Exists(svc.FilePath), "bootstrap writes config.json");
        Check.Eq(9, cfg.Backends.Count, "default has 9 backends");
        Check.True(cfg.Backends.ContainsKey("agy"), "default has agy backend");
        Check.True(cfg.ModelCatalog.ContainsKey("claude"), "default has claude model catalog");
        Check.Eq("claude", cfg.General.ActiveBackend, "default active backend = claude");
        Check.Eq("Shift+Alt+C", cfg.Hotkey.Translate, "Windows default translate hotkey = Shift+Alt+C (per-platform default; un-pinned from shared config-defaults vector)");

        var raw = File.ReadAllText(svc.FilePath);
        Check.Contains(raw, "简体中文", "prompt template Chinese stored unescaped");
        Check.NotContains(raw, "\\u7b80", "Chinese NOT \\u-escaped in file");

        // round-trip a change
        cfg.General.ActiveBackend = "doubao";
        cfg.Backends["doubao"].ApiKey = "secret-123";
        svc.Save(cfg);
        var reloaded = new ConfigService(dir).LoadOrBootstrap();
        Check.Eq("doubao", reloaded.General.ActiveBackend, "active backend round-trips");
        Check.Eq("secret-123", reloaded.Backends["doubao"].ApiKey, "apiKey round-trips");

        // corrupt file -> backed up + rebootstrapped
        File.WriteAllText(svc.FilePath, "{ this is : not json ");
        var recovered = new ConfigService(dir).LoadOrBootstrap();
        Check.Eq(9, recovered.Backends.Count, "corrupt config recovers to defaults");
        Check.True(Directory.GetFiles(dir, "config.json.bak.*").Length >= 1, "corrupt config backed up to .bak");
    }
    finally { try { Directory.Delete(dir, true); } catch { } }
}

// ---------------------------------------------------------------- PathResolver
Check.Section("PathResolver");
{
    Check.True(PathResolver.Resolve("cmd") is not null, "resolves cmd on PATH");
    Check.True(PathResolver.Resolve("definitely-not-real-cmd-xyz-123") is null, "missing command -> null");

    var tmpExe = Path.Combine(Path.GetTempPath(), "ttd-fake-" + Guid.NewGuid().ToString("N") + ".exe");
    File.WriteAllText(tmpExe, "stub");
    try
    {
        var byKnown = PathResolver.Resolve("ttd-fake-not-on-path", new[] { tmpExe });
        Check.True(byKnown is not null, "knownInstallPaths fallback resolves");
        Check.Eq(tmpExe, byKnown!.ResolvedPath, "knownInstallPaths returns the right path");

        var qualified = PathResolver.Resolve(tmpExe);
        Check.True(qualified is not null && qualified.ResolvedPath == tmpExe, "qualified path passes through");
    }
    finally { try { File.Delete(tmpExe); } catch { } }

    // .cmd wrapping
    var tmpCmd = Path.Combine(Path.GetTempPath(), "ttd-fake-" + Guid.NewGuid().ToString("N") + ".cmd");
    File.WriteAllText(tmpCmd, "@echo off");
    try
    {
        var wrapped = PathResolver.Resolve(tmpCmd);
        Check.True(wrapped is not null, ".cmd resolves");
        Check.Contains(wrapped!.Executable.ToLowerInvariant(), "cmd.exe", ".cmd wrapped via cmd.exe");
        Check.SeqContains(wrapped.PrependArgs, "/c", ".cmd wrap uses /c");
    }
    finally { try { File.Delete(tmpCmd); } catch { } }
}

// ---------------------------------------------------------------- PromptBuilder
Check.Section("PromptBuilder");
{
    Check.Eq("rules: hello", PromptBuilder.Build("rules: {content}", "hello"), "placeholder substituted");
    Check.Eq("hello", PromptBuilder.Build("", "hello"), "empty template -> content");
    Check.Contains(PromptBuilder.Build("just rules", "hello"), "hello", "no placeholder -> appended");

    // unified target language: {target} resolved once, then {content} per request
    Check.Eq("译为English。内容:{content}", PromptBuilder.WithTarget("译为{target}。内容:{content}", "English"), "WithTarget resolves {target}, leaves {content}");
    Check.Eq("plain", PromptBuilder.WithTarget("plain", "English"), "WithTarget no-op when no {target}");
    var rendered = PromptBuilder.Build(PromptBuilder.WithTarget("译为{target}:{content}", "日本語"), "hi");
    Check.Eq("译为日本語:hi", rendered, "target then content compose correctly");
    // existing config carrying the OLD (pre-{target}) default is auto-upgraded on load
    var migCfg = DefaultConfig.Create();
    migCfg.Translation.PromptTemplate = DefaultConfig.OldPromptTemplate;
    var migDir = Path.Combine(Path.GetTempPath(), "ttd-mig-" + Guid.NewGuid().ToString("N"));
    try { var svc = new ConfigService(migDir); svc.Save(migCfg); var loaded = svc.LoadOrBootstrap();
        Check.Eq(DefaultConfig.DefaultPromptTemplate, loaded.Translation.PromptTemplate, "old default template auto-upgrades to {target} on load");
        Check.Contains(loaded.Translation.PromptTemplate, "{target}", "upgraded template uses {target}"); }
    finally { try { System.IO.Directory.Delete(migDir, true); } catch { } }
}

// ---------------------------------------------------------------- AnsiStripper
Check.Section("AnsiStripper");
{
    var esc = ((char)0x1B).ToString();
    Check.Eq("hello", AnsiStripper.Strip(esc + "[31mhello" + esc + "[0m"), "strips SGR colour");
    Check.Eq("ab", AnsiStripper.Strip("a\rb"), "strips carriage return");
    Check.Eq("", AnsiStripper.Strip(null), "null -> empty");
    Check.Eq("plain", AnsiStripper.Strip("plain"), "plain text untouched");
}

// ---------------------------------------------------------------- CLI invocations
Check.Section("CLI BuildInvocation");
{
    const string tmpl = "T:{content}";

    var claude = Tb.Cli("claude", new BackendConfig { Type = "cli", Command = "claude" }, tmpl);
    var ci = claude.BuildInvocation("PROMPT", null);
    Check.SeqContains(ci.Args, "-p", "claude has -p");
    Check.SeqContains(ci.Args, "haiku", "claude default model haiku");
    Check.SeqContains(ci.Args, "text", "claude output-format text");
    Check.Eq(StdinMode.Pipe, ci.StdinMode, "claude pipes prompt via stdin");
    Check.Eq("PROMPT", ci.StdinText, "claude stdin text = prompt (avoids cmd.exe mangling)");

    var claude2 = Tb.Cli("claude", new BackendConfig { Type = "cli", Command = "claude", Model = "sonnet" }, tmpl);
    Check.SeqContains(claude2.BuildInvocation("P", null).Args, "sonnet", "claude honours model override");

    var codex = Tb.Cli("codex", new BackendConfig { Type = "cli", Command = "codex" }, tmpl);
    var cx = codex.BuildInvocation("PROMPT", null);
    Check.Eq("exec", cx.Args[0], "codex subcommand exec");
    Check.SeqContains(cx.Args, "read-only", "codex sandbox read-only");
    Check.Eq("-", cx.Args[^1], "codex - is last arg (reads stdin)");
    Check.SeqContains(cx.Args, "model_reasoning_effort=\"low\"", "codex low reasoning");
    Check.Eq(StdinMode.Pipe, cx.StdinMode, "codex pipes stdin");
    Check.Eq("PROMPT", cx.StdinText, "codex stdin text = prompt");

    var copilot = Tb.Cli("copilot", new BackendConfig { Type = "cli", Command = "copilot" }, tmpl);
    var cp = copilot.BuildInvocation("P", null);
    Check.SeqContains(cp.Args, "--allow-all-tools", "copilot --allow-all-tools (required for non-interactive)");
    Check.SeqContains(cp.Args, "--model", "copilot passes --model");

    var agy = Tb.Cli("agy", new BackendConfig { Type = "cli", Command = "agy", FallbackCommand = "gemini" }, tmpl);
    var ay = agy.BuildInvocation("P", "C:\\tmp\\x.log");
    Check.True(ay.WantsLogFile, "agy wants log file");
    Check.SeqContains(ay.Args, "--dangerously-skip-permissions", "agy skips tool-permission prompt for non-interactive -p");
    Check.SeqContains(ay.Args, "--log-file", "agy passes --log-file");
    Check.SeqContains(ay.Args, "C:\\tmp\\x.log", "agy log path threaded");

    // effort wiring: claude/copilot append --effort ONLY when a reasoning tier is set (codex is inline)
    var claudeEff = Tb.Cli("claude", new BackendConfig { Type = "cli", Command = "claude", Reasoning = "high" }, tmpl).BuildInvocation("P", null);
    Check.SeqContains(claudeEff.Args, "--effort", "claude appends --effort when reasoning set");
    Check.SeqContains(claudeEff.Args, "high", "claude --effort value threaded");
    var claudeNoEff = Tb.Cli("claude", new BackendConfig { Type = "cli", Command = "claude" }, tmpl).BuildInvocation("P", null);
    Check.True(!claudeNoEff.Args.Contains("--effort"), "claude omits --effort when reasoning unset (no default behavior change)");
    var copilotEff = Tb.Cli("copilot", new BackendConfig { Type = "cli", Command = "copilot", Reasoning = "medium" }, tmpl).BuildInvocation("P", null);
    Check.SeqContains(copilotEff.Args, "--effort", "copilot appends --effort when reasoning set");
    Check.SeqContains(copilotEff.Args, "medium", "copilot --effort value threaded");
    var copilotNoEff = Tb.Cli("copilot", new BackendConfig { Type = "cli", Command = "copilot" }, tmpl).BuildInvocation("P", null);
    Check.True(!copilotNoEff.Args.Contains("--effort"), "copilot omits --effort when reasoning unset");
    var agyEff = Tb.Cli("agy", new BackendConfig { Type = "cli", Command = "agy", Reasoning = "high" }, tmpl).BuildInvocation("P", null);
    Check.True(!agyEff.Args.Contains("--effort"), "agy has no --effort flag even with reasoning set (effort = model label)");
    var codexInline = Tb.Cli("codex", new BackendConfig { Type = "cli", Command = "codex", Reasoning = "high" }, tmpl).BuildInvocation("P", null);
    Check.True(codexInline.Args.Any(a => a.Contains("model_reasoning_effort=\"high\"")), "codex threads effort inline (model_reasoning_effort)");

    // new vendors: opencode (run + positional prompt + --format json + skip-perms + --variant effort), kimi (-p + stream-json), mimo (run + skip-perms)
    var oc = Tb.Cli("opencode", new BackendConfig { Type = "cli", Command = "opencode" }, tmpl).BuildInvocation("PROMPT", null);
    Check.Eq("run", oc.Args[0], "opencode uses the run subcommand (not -p)");
    Check.SeqContains(oc.Args, "PROMPT", "opencode prompt is a positional arg");
    Check.SeqContains(oc.Args, "json", "opencode --format json");
    Check.SeqContains(oc.Args, "--dangerously-skip-permissions", "opencode skip-permissions");
    Check.True(!oc.Args.Contains("--variant"), "opencode omits --variant when no effort tier");
    var ocVar = Tb.Cli("opencode", new BackendConfig { Type = "cli", Command = "opencode", Reasoning = "high" }, tmpl).BuildInvocation("P", null);
    Check.SeqContains(ocVar.Args, "--variant", "opencode appends --variant when reasoning set");
    Check.SeqContains(ocVar.Args, "high", "opencode --variant value threaded");
    var km = Tb.Cli("kimi", new BackendConfig { Type = "cli", Command = "kimi" }, tmpl).BuildInvocation("P", null);
    Check.SeqContains(km.Args, "-p", "kimi non-interactive -p");
    Check.SeqContains(km.Args, "stream-json", "kimi --output-format stream-json (manifest default)");
    var mm = Tb.Cli("mimo", new BackendConfig { Type = "cli", Command = "mimo" }, tmpl).BuildInvocation("P", null);
    Check.Eq("run", mm.Args[0], "mimo uses the run subcommand (bare mimo = TUI)");
    Check.SeqContains(mm.Args, "--dangerously-skip-permissions", "mimo skip-permissions (required)");
    Check.SeqContains(mm.Args, "json", "mimo --format json (clean answer, no chrome header line)");

    // live model enumeration parser: keep provider/model ids; drop chrome / blank / spaced lines; dedup, order-preserved
    var parsed = ModelEnumerator.ParseModels("opencode/big-pickle\ndeepseek/deepseek-chat\n\n> build · chrome line\ndeepseek/deepseek-chat\nplainword\n");
    Check.Eq(2, parsed.Count, "ParseModels keeps only unique provider/model ids");
    Check.Eq("opencode/big-pickle", parsed[0], "ParseModels preserves source order");
    Check.SeqContains(parsed, "deepseek/deepseek-chat", "ParseModels keeps the deepseek id (deduped once)");

    // HTTP /models enumeration: derive the GET /models URL from a chat/messages endpoint + parse the OpenAI-shaped body
    Check.Eq("https://api.deepseek.com/v1/models", ModelEnumerator.DeriveModelsUrl("https://api.deepseek.com/v1/chat/completions"), "derive /models from openai chat endpoint");
    Check.Eq("https://api.kimi.com/coding/v1/models", ModelEnumerator.DeriveModelsUrl("https://api.kimi.com/coding/v1/messages"), "derive /models from anthropic messages endpoint");
    // bare base (e.g. tokbox-api.netease.im) serves /v1/models, NOT /models -> try /v1/models first, then /models
    var bareUrls = ModelEnumerator.DeriveModelsUrls("https://tokbox-api.netease.im");
    Check.Eq("https://tokbox-api.netease.im/v1/models", bareUrls[0], "bare base -> /v1/models is the first candidate");
    Check.SeqContains(bareUrls, "https://tokbox-api.netease.im/models", "bare base -> /models is a fallback candidate");
    Check.Eq("https://x.ai/v1/models", ModelEnumerator.DeriveModelsUrl("https://x.ai/v1"), "/v1 base -> /v1/models (no double /v1)");
    Check.Eq("https://openrouter.ai/api/v1/models", ModelEnumerator.DeriveModelsUrl("https://openrouter.ai/api/v1"), "openrouter /api/v1 -> /api/v1/models (versioned root)");
    Check.SeqContains(ModelEnumerator.ParseModelsJson("{\"models\":[{\"name\":\"llama3\"},{\"name\":\"qwen\"}]}"), "llama3", "ParseModelsJson handles {models:[{name}]} (ollama)");
    Check.SeqContains(ModelEnumerator.ParseModelsJson("[\"gpt-4o\",\"gpt-4o-mini\"]"), "gpt-4o-mini", "ParseModelsJson handles a bare string array");
    var apiModels = ModelEnumerator.ParseModelsJson("{\"object\":\"list\",\"data\":[{\"id\":\"deepseek-v4-flash\"},{\"id\":\"deepseek-reasoner\"},{\"id\":\"deepseek-v4-flash\"}]}");
    Check.Eq(2, apiModels.Count, "ParseModelsJson extracts unique data[].id");
    Check.Eq("deepseek-v4-flash", apiModels[0], "ParseModelsJson preserves API order");
    Check.Eq(0, ModelEnumerator.ParseModelsJson("not json at all").Count, "ParseModelsJson tolerates non-JSON");
}

// ---------------------------------------------------------------- HTTP calls + parsing
Check.Section("HTTP BuildCall + ParseResponse");
{
    var g = Tb.Http("google-v2", new BackendConfig { Type = "http", ApiKey = "K", Target = "zh-CN", Format = "text" });
    var gc = g.BuildCall("Hello");
    Check.Eq("POST", gc.Method, "google POST");
    Check.Contains(gc.Url, "translate/v2", "google v2 endpoint");
    Check.True(gc.Headers.ContainsKey("x-goog-api-key"), "google sends x-goog-api-key");
    Check.Contains(gc.BodyJson, "\"target\":\"zh-CN\"", "google target zh-CN");
    Check.Contains(gc.BodyJson, "\"format\":\"text\"", "google format text");
    Check.NotContains(gc.BodyJson, "source", "google omits source when empty (auto-detect)");
    Check.Eq("你好,世界", g.ParseResponse("{\"data\":{\"translations\":[{\"translatedText\":\"你好,世界\",\"detectedSourceLanguage\":\"en\"}]}}"), "google parses translatedText");

    var gSrc = Tb.Http("google-v2", new BackendConfig { Type = "http", ApiKey = "K", Source = "en" });
    Check.Contains(gSrc.BuildCall("Hi").BodyJson, "\"source\":\"en\"", "google includes source when set");

    var d = Tb.Http("doubao", new BackendConfig { Type = "http", ApiKey = "K", Model = "doubao-seed-translation-250915", TargetLanguage = "zh" });
    var dc = d.BuildCall("Hello");
    Check.Contains(dc.Url, "/responses", "doubao hits /responses (NOT chat/completions)");
    Check.NotContains(dc.Url, "chat/completions", "doubao avoids chat/completions");
    Check.True(dc.Headers.TryGetValue("Authorization", out var auth) && auth.StartsWith("Bearer "), "doubao Bearer auth");
    Check.Contains(dc.BodyJson, "input_text", "doubao uses input_text content part");
    Check.Contains(dc.BodyJson, "\"target_language\":\"zh\"", "doubao target_language zh");
    Check.NotContains(dc.BodyJson, "source_language", "doubao omits source_language when empty");
    Check.NotContains(dc.BodyJson, "messages", "doubao does NOT use chat messages[]");
    Check.Eq("你好,世界", d.ParseResponse("{\"output\":[{\"type\":\"reasoning\",\"content\":[]},{\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"你好,世界\"}]}]}"), "doubao parses output_text past a reasoning item");
}

// ---------------------------------------------------------------- HTTP credential gating (no network)
Check.Section("HTTP credential gating");
{
    var noKey = Tb.Http("google-v2", new BackendConfig { Type = "http", ApiKey = "" });
    var res = await noKey.TranslateAsync(new TranslationRequest("hi"), CancellationToken.None);
    Check.Eq(TranslateStatus.AuthFail, res.Status, "empty key -> AuthFail without hitting network");
}

// ---------------------------------------------------------------- Registry
Check.Section("TranslatorRegistry");
{
    var reg = TranslatorRegistry.Build(DefaultConfig.Create());
    Check.Eq(9, reg.Ids.Count, "registry builds 9 backends");
    Check.True(reg.Get("claude") is ManifestCliBackend, "claude -> manifest CLI backend");
    Check.True(reg.Get("doubao") is ManifestHttpBackend, "doubao -> manifest HTTP backend");
    Check.True(reg.Get("CLAUDE") is ManifestCliBackend, "lookup is case-insensitive");
    Check.True(reg.Get("nope") is null, "unknown backend -> null");

    // custom provider: an id ABSENT from the manifest resolves a generic HTTP template by protocol (Law-6, no switch(id))
    var customCfg = DefaultConfig.Create();
    customCfg.Backends["my-deepseek"] = new BackendConfig { Type = "http", Protocol = "openai", Endpoint = "https://api.deepseek.com/v1/chat/completions", ApiKey = "K", Model = "deepseek-v4-flash" };
    customCfg.Backends["my-kimi"] = new BackendConfig { Type = "http", Protocol = "anthropic", Endpoint = "https://api.kimi.com/coding/v1/messages", ApiKey = "K", Model = "kimi-for-coding" };
    customCfg.Backends["no-proto"] = new BackendConfig { Type = "http", Endpoint = "https://x/y", ApiKey = "K" };  // no protocol -> dropped
    var creg = TranslatorRegistry.Build(customCfg);
    Check.True(creg.Get("my-deepseek") is ManifestHttpBackend, "custom openai provider resolves via protocol fallback");
    Check.True(creg.Get("my-kimi") is ManifestHttpBackend, "custom anthropic provider resolves via protocol fallback");
    Check.True(creg.Get("no-proto") is null, "custom http id with no protocol is dropped (not silently mis-resolved)");
    var dsCall = ((ManifestHttpBackend)creg.Get("my-deepseek")!).BuildCall("Hello");
    Check.True(dsCall.Url.Contains("api.deepseek.com", StringComparison.Ordinal), "custom provider uses the config endpoint, not the empty manifest one");
    Check.True(dsCall.BodyJson.Contains("\"stream\":false", StringComparison.Ordinal) && !dsCall.BodyJson.Contains("max_tokens", StringComparison.Ordinal), "custom openai provider emits the openai-http body shape");
}

// ---------------------------------------------------------------- Manifest hardening (codex review fixes)
Check.Section("Manifest hardening");
{
    // Eval returns a string leaf; null (not raw JSON) for a non-string -> bad path fails cleanly.
    using var d1 = System.Text.Json.JsonDocument.Parse("{\"a\":{\"b\":\"hi\"}}");
    Check.Eq("hi", ManifestEngine.Eval(d1.RootElement, "a.b"), "Eval reads a string leaf");
    Check.True(ManifestEngine.Eval(d1.RootElement, "a") is null, "Eval -> null for an object (not raw JSON)");
    using var d2 = System.Text.Json.JsonDocument.Parse("{\"n\":5}");
    Check.True(ManifestEngine.Eval(d2.RootElement, "n") is null, "Eval -> null for a number");

    // A backend whose config key isn't lowercase still resolves against the manifest.
    var ucfg = DefaultConfig.Create();
    var bc = ucfg.Backends["claude"];
    ucfg.Backends.Remove("claude");
    ucfg.Backends["CLAUDE"] = bc;
    var ureg = TranslatorRegistry.Build(ucfg);
    Check.True(ureg.Get("CLAUDE") is ManifestCliBackend, "uppercase config backend key resolves via manifest");

    // Empty config value falls back to the manifest default (not sent empty).
    var hb = Tb.Http("google-v2", new BackendConfig { Type = "http", ApiKey = "K", Target = "" });
    Check.Contains(hb.BuildCall("Hi").BodyJson, "\"target\":\"zh-CN\"", "empty target -> manifest default zh-CN");
}

// ---------------------------------------------------------------- TranslationPipeline
Check.Section("TranslationPipeline");
{
    var cfg = DefaultConfig.Create();
    cfg.General.ActiveBackend = "fake";
    cfg.Translation.MaxChars = 10;
    var reg = TranslatorRegistry.Build(new AppConfig());           // empty
    var fake = new FakeTranslator("fake", (req, _) => Task.FromResult(TranslationResult.Successful("译文<" + req.Text + ">")));
    reg.Add(fake);
    var pipe = new TranslationPipeline(cfg, reg);

    Check.True(pipe.Accept("   ", TriggerSource.Hotkey) is null, "whitespace filtered out");
    Check.Eq("0123456789", pipe.Accept("0123456789ABCDEF", TriggerSource.Hotkey), "truncated to MaxChars");

    pipe.NoteClipboardText("dup");
    Check.True(pipe.Accept("dup", TriggerSource.Clipboard) is null, "clipboard dedupe skips identical");
    Check.Eq("dup", pipe.Accept("dup", TriggerSource.Hotkey), "hotkey ignores dedupe");

    var r = await pipe.RunAsync("hello", TriggerSource.Hotkey);
    Check.True(r is not null && r.Ok, "pipeline runs active backend");
    Check.Eq("译文<hello>", r!.Text, "pipeline returns backend text");
    Check.Eq(1, fake.Calls, "backend called exactly once");

    Check.True(await pipe.RunAsync("   ", TriggerSource.Hotkey) is null, "filtered trigger returns null");
}

// ---------------------------------------------------------------- HotkeyParser
Check.Section("HotkeyParser");
{
    var h = HotkeyParser.Parse("Ctrl+Alt+T");
    Check.True(h.IsValid, "Ctrl+Alt+T valid");
    Check.True((h.Modifiers & HotkeyParser.MOD_CONTROL) != 0, "has Control");
    Check.True((h.Modifiers & HotkeyParser.MOD_ALT) != 0, "has Alt");
    Check.Eq((uint)'T', h.VirtualKey, "vk = T (0x54)");
    Check.Eq("Ctrl+Alt+T", h.Display, "display normalised");

    Check.Eq((uint)0x71, HotkeyParser.Parse("Ctrl+F2").VirtualKey, "F2 -> 0x71");
    Check.True(!HotkeyParser.Parse("T").IsValid, "bare key without modifier invalid");
    Check.True(!HotkeyParser.Parse("").IsValid, "empty invalid");
    Check.True(!HotkeyParser.Parse("Ctrl+Foo").IsValid, "unknown key invalid");
}

// ---------------------------------------------------------------- TranslationPipeline cache
Check.Section("TranslationPipeline cache");
{
    var cfg = DefaultConfig.Create();
    cfg.General.ActiveBackend = "fake";
    cfg.Backends["fake"] = new BackendConfig { Type = "http", Model = "m1" };
    var reg = TranslatorRegistry.Build(new AppConfig());
    var fake = new FakeTranslator("fake", (req, _) => Task.FromResult(TranslationResult.Successful("T:" + req.Text)));
    reg.Add(fake);
    var pipe = new TranslationPipeline(cfg, reg);

    var a = await pipe.RunAsync("same", TriggerSource.Hotkey);
    Check.Eq(1, fake.Calls, "first translate calls the model");
    Check.Eq("T:same", a!.Text, "first translate returns model text");

    var b = await pipe.RunAsync("same", TriggerSource.Hotkey);
    Check.Eq(1, fake.Calls, "repeated same text+model -> cache hit, model NOT called");
    Check.Eq("T:same", b!.Text, "cache returns the same translation");

    // switching the model forces a re-translate even for identical text
    cfg.Backends["fake"].Model = "m2";
    await pipe.RunAsync("same", TriggerSource.Hotkey);
    Check.Eq(2, fake.Calls, "model switch forces re-translate (cache key includes model)");

    // different text misses
    await pipe.RunAsync("other", TriggerSource.Hotkey);
    Check.Eq(3, fake.Calls, "different text -> cache miss");

    // failures are not cached (so a retry still hits the model)
    var failReg = TranslatorRegistry.Build(new AppConfig());
    var failFake = new FakeTranslator("fake", (_, _) => Task.FromResult(TranslationResult.Failure(TranslateStatus.UnknownFail, "boom")));
    failReg.Add(failFake);
    var failPipe = new TranslationPipeline(cfg, failReg);
    await failPipe.RunAsync("z", TriggerSource.Hotkey);
    await failPipe.RunAsync("z", TriggerSource.Hotkey);
    Check.Eq(2, failFake.Calls, "failed translations are not cached");
}

// ---------------------------------------------------------------- TranslationPipeline cache supersession
Check.Section("TranslationPipeline cache supersession");
{
    var cfg = DefaultConfig.Create();
    cfg.General.ActiveBackend = "fake";
    cfg.Backends["fake"] = new BackendConfig { Type = "http", Model = "m1" };
    var reg = TranslatorRegistry.Build(new AppConfig());

    // Backend that deliberately IGNORES the cancellation token: a superseded in-flight request
    // still completes successfully (mirrors a CLI/HTTP backend that doesn't observe cancellation).
    var release = new TaskCompletionSource();
    var fake = new FakeTranslator("fake", async (req, _) =>
    {
        await release.Task;
        return TranslationResult.Successful("T:" + req.Text);
    });
    reg.Add(fake);
    var pipe = new TranslationPipeline(cfg, reg);

    var a = pipe.RunAsync("same", TriggerSource.Hotkey);   // in-flight
    var b = pipe.RunAsync("same", TriggerSource.Hotkey);   // supersedes A (cancels A's token)
    release.SetResult();                                    // both complete (A ignored cancellation)
    await Task.WhenAll(a, b);

    Check.Eq(2, fake.Calls, "both overlapping requests invoked the model");
    Check.Eq(1, pipe.RecentHistory().Count, "same key cached once despite a superseded overlapping run (no duplicate)");
}

// ---------------------------------------------------------------- Conformance (shared vectors)
Check.Section("Conformance (language-neutral vectors from /conformance)");
await Conformance.RunAsync();

var exit = Check.Report();

// Emit per-vector results for scripts/parity-verify.py (mechanism #9) when asked. Done AFTER Report
// so the suite's pass/fail is unchanged whether or not emission is requested.
var emitPath = Environment.GetEnvironmentVariable("TTD_EMIT_RESULTS");
if (!string.IsNullOrEmpty(emitPath)) Check.WriteResults(emitPath);

return exit;
