namespace Unbox.Kit;

/// <summary>
/// Measures what is actually stored on disk. Only entries that are already local are visited:
/// folders whose listing is still in the cloud are skipped, so nothing is fetched from Box.
/// </summary>
public static class DiskUsage
{
    public static long AllocatedSize(string path)
    {
        long total = 0;
        Walk(path, file => total += CloudFiles.AllocatedSize(file));
        return total;
    }

    /// <summary>Files under <paramref name="path"/> that currently have local content.</summary>
    public static List<string> DownloadedFiles(string path)
    {
        var files = new List<string>();
        Walk(path, file =>
        {
            if (!CloudFiles.IsCloudOnly(SafeAttributes(file)) && CloudFiles.AllocatedSize(file) > 0) files.Add(file);
        });
        return files;
    }

    private static void Walk(string path, Action<string> visitFile)
    {
        int attributes = SafeAttributes(path);
        if (attributes < 0) return;
        if ((attributes & (int)FileAttributes.Directory) == 0)
        {
            visitFile(path);
            return;
        }
        if (CloudFiles.IsUnpopulatedDirectory(attributes)) return;

        IEnumerable<FileSystemInfo> entries;
        try
        {
            entries = new DirectoryInfo(path).EnumerateFileSystemInfos("*", new EnumerationOptions
            {
                AttributesToSkip = 0,
                IgnoreInaccessible = true,
                RecurseSubdirectories = false,
            });
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return;
        }
        foreach (var entry in entries)
        {
            if (entry.LinkTarget != null) continue; // symlinks and junctions
            Walk(entry.FullName, visitFile);
        }
    }

    private static int SafeAttributes(string path)
    {
        try { return CloudFiles.RawAttributes(path); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return -1; }
    }
}
