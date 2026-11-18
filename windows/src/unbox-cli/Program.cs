using Unbox.Kit;

const string Usage = """
    Usage:
      unbox-cli list [--sizes]            folders and files kept offline (“Always keep on this device”)
      unbox-cli status <path>             pin state and local size of an item
      unbox-cli unmark <path> [--keep-local]
                                          make online-only and free the disk space
      unbox-cli mark <path>               make available offline (diagnostics)
    """;

static string Bytes(long value) => value switch
{
    >= 1L << 30 => $"{value / (double)(1L << 30):0.##} GB",
    >= 1L << 20 => $"{value / (double)(1L << 20):0.#} MB",
    >= 1L << 10 => $"{value / 1024.0:0} KB",
    _ => $"{value} B",
};

Console.OutputEncoding = System.Text.Encoding.UTF8;
L10n.Configure(AppLanguage.English);
if (args.Length == 0)
{
    Console.WriteLine(Usage);
    return 1;
}

try
{
    var service = new OfflineService();
    string Resolve(string path) => Path.GetFullPath(Environment.ExpandEnvironmentVariables(path));

    switch (args[0])
    {
        case "list":
            bool sizes = args.Contains("--sizes");
            var items = await service.ScanAsync();
            long total = 0;
            foreach (var item in items)
            {
                var kind = item.IsFolder ? "folder" : "file  ";
                if (sizes)
                {
                    long size = DiskUsage.AllocatedSize(item.FullPath);
                    total += size;
                    Console.WriteLine($"{kind}  {Bytes(size),-10}  {item.RelativePath}");
                }
                else
                {
                    Console.WriteLine($"{kind}  {item.RelativePath}");
                }
            }
            Console.WriteLine($"Total: {items.Count}" + (sizes ? $", {Bytes(total)}" : ""));
            Console.WriteLine($"Box folder: {service.Paths.SyncRoot}, Box Drive running: {(OfflineService.IsBoxRunning ? "yes" : "no")}");
            return 0;

        case "status" when args.Length > 1:
        {
            var path = Resolve(args[1]);
            int attributes = CloudFiles.RawAttributes(path);
            var pin = (attributes & CloudFiles.AttributePinned) != 0 ? "pinned (offline)"
                : (attributes & CloudFiles.AttributeUnpinned) != 0 ? "unpinned (online-only)" : "unspecified";
            Console.WriteLine($"pin state:    {pin}");
            Console.WriteLine($"attributes:   0x{attributes:X8}");
            Console.WriteLine($"on disk:      {Bytes(DiskUsage.AllocatedSize(path))}");
            Console.WriteLine($"local files:  {DiskUsage.DownloadedFiles(path).Count}");
            return 0;
        }

        case "unmark" when args.Length > 1:
        {
            var path = Resolve(args[1]);
            var relative = service.Paths.RelativePath(path) ?? throw UnboxException.ItemNotInBox(path);
            var item = new OfflineItem(relative, path, Directory.Exists(path));
            var outcome = await service.MakeOnlineOnlyAsync(item, freeSpace: !args.Contains("--keep-local"));
            Console.WriteLine($"Online-only: {relative}");
            Console.WriteLine($"Freed: {Bytes(outcome.FreedBytes)}, files still on disk: {outcome.FilesKeptLocally}");
            return 0;
        }

        case "mark" when args.Length > 1:
            OfflineService.MakeAvailableOffline(Resolve(args[1]));
            Console.WriteLine("Marked available offline.");
            return 0;

        default:
            Console.WriteLine(Usage);
            return 1;
    }
}
catch (Exception error) when (error is UnboxException or IOException or UnauthorizedAccessException or System.ComponentModel.Win32Exception)
{
    Console.Error.WriteLine($"Error: {error.Message}");
    return 2;
}
