using TranslateTheDamn.Core.Backends.Manifest;
using TranslateTheDamn.Core.Config;

namespace TranslateTheDamn.Tests;

/// <summary>Builds manifest-driven backends straight from the embedded manifest for tests.</summary>
public static class Tb
{
    public static ManifestCliBackend Cli(string id, BackendConfig cfg, string promptTemplate = "T:{content}") =>
        new(id, BackendManifest.Load().Backends[id], cfg, promptTemplate);

    public static ManifestHttpBackend Http(string id, BackendConfig cfg, string promptTemplate = "") =>
        new(id, BackendManifest.Load().Backends[id], cfg, promptTemplate);
}
