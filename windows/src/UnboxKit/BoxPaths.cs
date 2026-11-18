using Windows.Storage.Provider;

namespace Unbox.Kit;

public sealed record BoxPaths(string DataDirectory, string SyncRoot)
{
    public string Database => Path.Combine(DataDirectory, "streemfs.db");

    public static BoxPaths Detect()
    {
        var data = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Box", "Box", "data");
        if (!Directory.Exists(data)) throw UnboxException.BoxNotInstalled();
        // Only the new Box Drive architecture (2.47+) registers its folder with Windows Cloud Files.
        var root = RegisteredSyncRoot() ?? throw UnboxException.LegacyBoxDrive();
        if (!Directory.Exists(root)) throw UnboxException.SyncRootMissing(root);
        return new BoxPaths(data, root);
    }

    /// <summary>The folder Box Drive registered with Windows (its ID starts with "Box!").</summary>
    private static string? RegisteredSyncRoot()
    {
        try
        {
            return StorageProviderSyncRootManager.GetCurrentSyncRoots()
                .Where(root => root.Id.StartsWith("Box!", StringComparison.OrdinalIgnoreCase))
                .Select(root => root.Path?.Path)
                .FirstOrDefault(path => !string.IsNullOrEmpty(path));
        }
        catch (Exception)
        {
            return null;
        }
    }

    public string FullPath(string relativePath) =>
        Path.Combine(SyncRoot, relativePath.TrimStart('\\', '/').Replace('/', '\\'));

    public string? RelativePath(string fullPath)
    {
        var root = Path.GetFullPath(SyncRoot).TrimEnd('\\');
        var path = Path.GetFullPath(fullPath).TrimEnd('\\');
        if (path.Equals(root, StringComparison.OrdinalIgnoreCase)) return "";
        return path.StartsWith(root + "\\", StringComparison.OrdinalIgnoreCase) ? path[root.Length..] : null;
    }
}
