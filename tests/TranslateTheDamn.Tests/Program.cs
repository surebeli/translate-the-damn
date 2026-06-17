using TranslateTheDamn.Core;
using TranslateTheDamn.Core.Backends;
using TranslateTheDamn.Core.Backends.Cli;
using TranslateTheDamn.Core.Backends.Http;
using TranslateTheDamn.Core.Config;
using TranslateTheDamn.Core.Util;
using TranslateTheDamn.Tests;

// Opt-in live end-to-end check against a real, installed, authenticated CLI (not part of the
// default offline suite). Usage: dotnet run -- --live [backendId]
if (args.Contains("--live"))
{
    var backendId = args.FirstOrDefault(a => !a.StartsWith("--")) ?? "claude";
    Console.WriteLine($"# LIVE end-to-end via real backend: {backendId}");
    var liveCfg = DefaultConfig.Create();
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
        Check.Eq(6, cfg.Backends.Count, "default has 6 backends");
        Check.True(cfg.Backends.ContainsKey("agy"), "default has agy backend");
        Check.True(cfg.ModelCatalog.ContainsKey("claude"), "default has claude model catalog");
        Check.Eq("claude", cfg.General.ActiveBackend, "default active backend = claude");

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
        Check.Eq(6, recovered.Backends.Count, "corrupt config recovers to defaults");
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

    var claude = new ClaudeTranslator(new BackendConfig { Type = "cli", Command = "claude" }, tmpl);
    var ci = claude.BuildInvocation("PROMPT", null);
    Check.SeqContains(ci.Args, "-p", "claude has -p");
    Check.SeqContains(ci.Args, "haiku", "claude default model haiku");
    Check.SeqContains(ci.Args, "text", "claude output-format text");
    Check.Eq(StdinMode.Pipe, ci.StdinMode, "claude pipes prompt via stdin");
    Check.Eq("PROMPT", ci.StdinText, "claude stdin text = prompt (avoids cmd.exe mangling)");

    var claude2 = new ClaudeTranslator(new BackendConfig { Type = "cli", Command = "claude", Model = "sonnet" }, tmpl);
    Check.SeqContains(claude2.BuildInvocation("P", null).Args, "sonnet", "claude honours model override");

    var codex = new CodexTranslator(new BackendConfig { Type = "cli", Command = "codex" }, tmpl);
    var cx = codex.BuildInvocation("PROMPT", null);
    Check.Eq("exec", cx.Args[0], "codex subcommand exec");
    Check.SeqContains(cx.Args, "read-only", "codex sandbox read-only");
    Check.Eq("-", cx.Args[^1], "codex - is last arg (reads stdin)");
    Check.SeqContains(cx.Args, "model_reasoning_effort=\"low\"", "codex low reasoning");
    Check.Eq(StdinMode.Pipe, cx.StdinMode, "codex pipes stdin");
    Check.Eq("PROMPT", cx.StdinText, "codex stdin text = prompt");

    var copilot = new CopilotTranslator(new BackendConfig { Type = "cli", Command = "copilot" }, tmpl);
    var cp = copilot.BuildInvocation("P", null);
    Check.SeqContains(cp.Args, "-s", "copilot silent -s");
    Check.SeqContains(cp.Args, "--no-ask-user", "copilot --no-ask-user");

    var agy = new AgyTranslator(new BackendConfig { Type = "cli", Command = "agy", FallbackCommand = "gemini" }, tmpl);
    var ay = agy.BuildInvocation("P", "C:\\tmp\\x.log");
    Check.True(ay.WantsLogFile, "agy wants log file");
    Check.SeqContains(ay.Args, "--log-file", "agy passes --log-file");
    Check.SeqContains(ay.Args, "C:\\tmp\\x.log", "agy log path threaded");
}

// ---------------------------------------------------------------- HTTP calls + parsing
Check.Section("HTTP BuildCall + ParseResponse");
{
    var g = new GoogleV2Translator(new BackendConfig { Type = "http", ApiKey = "K", Target = "zh-CN", Format = "text" });
    var gc = g.BuildCall("Hello");
    Check.Eq("POST", gc.Method, "google POST");
    Check.Contains(gc.Url, "translate/v2", "google v2 endpoint");
    Check.True(gc.Headers.ContainsKey("x-goog-api-key"), "google sends x-goog-api-key");
    Check.Contains(gc.BodyJson, "\"target\":\"zh-CN\"", "google target zh-CN");
    Check.Contains(gc.BodyJson, "\"format\":\"text\"", "google format text");
    Check.NotContains(gc.BodyJson, "source", "google omits source when empty (auto-detect)");
    Check.Eq("你好,世界", g.ParseResponse("{\"data\":{\"translations\":[{\"translatedText\":\"你好,世界\",\"detectedSourceLanguage\":\"en\"}]}}"), "google parses translatedText");

    var gSrc = new GoogleV2Translator(new BackendConfig { Type = "http", ApiKey = "K", Source = "en" });
    Check.Contains(gSrc.BuildCall("Hi").BodyJson, "\"source\":\"en\"", "google includes source when set");

    var d = new DoubaoTranslator(new BackendConfig { Type = "http", ApiKey = "K", Model = "doubao-seed-translation-250915", TargetLanguage = "zh" });
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
    var noKey = new GoogleV2Translator(new BackendConfig { Type = "http", ApiKey = "" });
    var res = await noKey.TranslateAsync(new TranslationRequest("hi"), CancellationToken.None);
    Check.Eq(TranslateStatus.AuthFail, res.Status, "empty key -> AuthFail without hitting network");
}

// ---------------------------------------------------------------- Registry
Check.Section("TranslatorRegistry");
{
    var reg = TranslatorRegistry.Build(DefaultConfig.Create());
    Check.Eq(6, reg.Ids.Count, "registry builds 6 backends");
    Check.True(reg.Get("claude") is ClaudeTranslator, "claude -> ClaudeTranslator");
    Check.True(reg.Get("doubao") is DoubaoTranslator, "doubao -> DoubaoTranslator");
    Check.True(reg.Get("CLAUDE") is ClaudeTranslator, "lookup is case-insensitive");
    Check.True(reg.Get("nope") is null, "unknown backend -> null");
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

// ---------------------------------------------------------------- Conformance (shared vectors)
Check.Section("Conformance (language-neutral vectors from /conformance)");
Conformance.Run();

return Check.Report();
