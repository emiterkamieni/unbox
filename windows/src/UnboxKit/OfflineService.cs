using System.ComponentModel;
using System.Diagnostics;

namespace Unbox.Kit;

public sealed record OnlineOnlyOutcome(long FreedBytes, int FilesKeptLocally);

public sealed class OfflineService
{
    public BoxPaths Paths { get; }

    public OfflineService()
    {
        Paths = BoxPaths.Detect();
    }

    public static bool IsBoxRunning => Process.GetProcessesByName("Box").Length > 0;

    // MARK: Scanning

    public Task<IReadOnlyList<OfflineItem>> ScanAsync() => Task.Run(Scan);

    public IReadOnlyList<OfflineItem> Scan()
    {
        List<OfflineItem> candidates;
        try
        {
            candidates = new BoxDatabase(Paths).OfflineRoots()
                .Select(root => new OfflineItem(root.RelativePath, Paths.FullPath(root.RelativePath), !root.IsFile))
                .ToList();
        }
        catch (UnboxException)
        {
            return ScanAttributes();
        }
        // The database copy can lag behind by a moment; Windows has the final word.
        return candidates.Where(item => Exists(item.FullPath) && IsPinned(item.FullPath)).ToList();
    }

    /// <summary>Fallback if Box changes its database: walk the local part of the Box folder.</summary>
    private List<OfflineItem> ScanAttributes()
    {
        var result = new List<OfflineItem>();
        var queue = new Queue<string>([Paths.SyncRoot]);
        while (queue.Count > 0)
        {
            IEnumerable<FileSystemInfo> entries;
            try { entries = new DirectoryInfo(queue.Dequeue()).EnumerateFileSystemInfos(); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { continue; }
            foreach (var entry in entries)
            {
                int attributes = (int)entry.Attributes;
                bool isFolder = (attributes & (int)FileAttributes.Directory) != 0;
                if ((attributes & CloudFiles.AttributePinned) != 0)
                {
                    var relative = Paths.RelativePath(entry.FullName) ?? entry.Name;
                    result.Add(new OfflineItem(relative, entry.FullName, isFolder));
                }
                else if (isFolder && entry.LinkTarget == null && !CloudFiles.IsUnpopulatedDirectory(attributes))
                {
                    queue.Enqueue(entry.FullName);
                }
            }
        }
        return result.OrderBy(item => item.RelativePath, StringComparer.CurrentCultureIgnoreCase).ToList();
    }

    // MARK: Changing state

    /// <summary>
    /// Same as File Explorer's “Free up space” (or, with <paramref name="freeSpace"/> off, only
    /// clearing “Always keep on this device”).
    /// </summary>
    public async Task<OnlineOnlyOutcome> MakeOnlineOnlyAsync(OfflineItem item, bool freeSpace)
    {
        long before = await Task.Run(() => DiskUsage.AllocatedSize(item.FullPath));
        try
        {
            await Task.Run(() => CloudFiles.SetPinState(item.FullPath, freeSpace ? PinState.Unpinned : PinState.Unspecified));
        }
        catch (Win32Exception error)
        {
            throw UnboxException.ActionFailed(error.Message);
        }

        for (int i = 0; i < 20 && IsPinned(item.FullPath); i++) await Task.Delay(500);
        if (IsPinned(item.FullPath)) throw UnboxException.BoxDidNotApply(item.Name);

        long after = freeSpace ? await SettledSizeAsync(item.FullPath) : before;
        int kept = freeSpace ? await Task.Run(() => DiskUsage.DownloadedFiles(item.FullPath).Count) : 0;
        return new OnlineOnlyOutcome(Math.Max(0, before - after), kept);
    }

    /// <summary>Diagnostic helper used by the command line tool.</summary>
    public static void MakeAvailableOffline(string path) => CloudFiles.SetPinState(path, PinState.Pinned);

    /// <summary>Box removes the local content asynchronously; wait until the size stops changing.</summary>
    private static async Task<long> SettledSizeAsync(string path)
    {
        long last = long.MaxValue;
        int stable = 0;
        for (int i = 0; i < 120; i++)
        {
            long current = await Task.Run(() => DiskUsage.AllocatedSize(path));
            if (current == 0) return 0;
            stable = current == last ? stable + 1 : 0;
            if (stable >= 3) return current;
            last = current;
            await Task.Delay(1000);
        }
        return last;
    }

    private static bool Exists(string path) => File.Exists(path) || Directory.Exists(path);

    private static bool IsPinned(string path)
    {
        try { return CloudFiles.IsPinned(path); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return false; }
    }
}
