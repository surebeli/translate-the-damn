using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace TranslateTheDamn.Core.Config;

/// <summary>
/// Loads / bootstraps / persists config.json. Directory is injectable so tests never touch the
/// real user profile. On first run (file absent) the hardcoded <see cref="DefaultConfig"/> is
/// written. A corrupt file is preserved as a <c>.bak</c> rather than silently destroyed.
/// </summary>
public sealed class ConfigService
{
    public static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DictionaryKeyPolicy = null,                 // backend ids / model-catalog keys verbatim
        PropertyNameCaseInsensitive = true,
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping  // keep Chinese readable in the file
    };

    public string Directory { get; }
    public string FilePath => Path.Combine(Directory, "config.json");

    public ConfigService(string? directory = null)
    {
        Directory = directory ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".translatethedamn");
    }

    /// <summary>Returns the persisted config, or writes+returns the bootstrap default if absent/corrupt.</summary>
    public AppConfig LoadOrBootstrap()
    {
        if (File.Exists(FilePath))
        {
            try
            {
                var json = File.ReadAllText(FilePath);
                var cfg = JsonSerializer.Deserialize<AppConfig>(json, JsonOptions);
                if (cfg is not null)
                {
                    EnsureDefaults(cfg);
                    return cfg;
                }
            }
            catch (JsonException)
            {
                BackupCorrupt();
            }
        }

        var fresh = DefaultConfig.Create();
        Save(fresh);
        return fresh;
    }

    public void Save(AppConfig config)
    {
        System.IO.Directory.CreateDirectory(Directory);
        var json = JsonSerializer.Serialize(config, JsonOptions);
        var tmp = FilePath + ".tmp";
        File.WriteAllText(tmp, json);
        File.Move(tmp, FilePath, overwrite: true);
    }

    /// <summary>Fill in any structurally-missing sub-objects so old/partial files stay usable.</summary>
    private static void EnsureDefaults(AppConfig cfg)
    {
        var def = DefaultConfig.Create();
        cfg.General ??= def.General;
        cfg.Hotkey ??= def.Hotkey;
        cfg.Popup ??= def.Popup;
        cfg.Translation ??= def.Translation;
        if (string.IsNullOrWhiteSpace(cfg.Translation.PromptTemplate))
            cfg.Translation.PromptTemplate = DefaultConfig.DefaultPromptTemplate;
        cfg.Backends ??= def.Backends;
        cfg.ModelCatalog ??= def.ModelCatalog;
    }

    private void BackupCorrupt()
    {
        try
        {
            var stamp = DateTime.Now.ToString("yyyyMMdd-HHmmss");
            File.Move(FilePath, FilePath + ".bak." + stamp, overwrite: true);
        }
        catch { /* best effort; bootstrap will overwrite anyway */ }
    }
}
