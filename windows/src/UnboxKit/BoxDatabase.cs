using Microsoft.Data.Sqlite;

namespace Unbox.Kit;

/// <summary>
/// Reads Box Drive's own offline flags (fsnodes.markForOffline: 1 = pinned) – the same database
/// as on macOS. Box keeps it open, so it is copied together with its write-ahead log to a private
/// temporary folder and only the copy is read. Box's files are never opened for writing.
/// </summary>
public sealed class BoxDatabase(BoxPaths paths)
{
    public sealed record Root(string RelativePath, bool IsFile);

    private const string RootsQuery = """
        WITH RECURSIVE tree(inodeId, path, isFile, mfo, parentMfo) AS (
            SELECT inodeId, '', isFile, IFNULL(markForOffline, 0), 0 FROM fsnodes
             WHERE name = '' AND parentInodeId NOT IN (SELECT inodeId FROM fsnodes)
            UNION ALL
            SELECT f.inodeId, tree.path || '\' || f.name, f.isFile, IFNULL(f.markForOffline, 0), tree.mfo
              FROM fsnodes f JOIN tree ON f.parentInodeId = tree.inodeId
        )
        SELECT path, isFile FROM tree
         WHERE mfo = 1 AND parentMfo != 1 AND path != ''
         ORDER BY path COLLATE NOCASE;
        """;

    public IReadOnlyList<Root> OfflineRoots()
    {
        var folder = MakeSnapshot();
        try
        {
            using var connection = new SqliteConnection(new SqliteConnectionStringBuilder
            {
                DataSource = Path.Combine(folder, "streemfs.db"),
                Mode = SqliteOpenMode.ReadWrite, // the copy needs write access to replay its WAL
                Pooling = false,
            }.ToString());
            connection.Open();

            if (!Columns(connection, "fsnodes").IsSupersetOf(["inodeId", "parentInodeId", "name", "isFile", "markForOffline"]))
                throw UnboxException.UnsupportedDatabase();

            using var command = connection.CreateCommand();
            command.CommandText = RootsQuery;
            using var reader = command.ExecuteReader();
            var roots = new List<Root>();
            while (reader.Read()) roots.Add(new Root(reader.GetString(0), reader.GetInt64(1) != 0));
            return roots;
        }
        catch (SqliteException error)
        {
            throw UnboxException.DatabaseUnavailable(error.Message);
        }
        finally
        {
            try { Directory.Delete(folder, recursive: true); } catch (IOException) { }
        }
    }

    private static HashSet<string> Columns(SqliteConnection connection, string table)
    {
        using var command = connection.CreateCommand();
        command.CommandText = $"PRAGMA table_info({table});";
        using var reader = command.ExecuteReader();
        var names = new HashSet<string>();
        while (reader.Read()) names.Add(reader.GetString(1));
        return names;
    }

    /// <summary>Copies the database and WAL; retries when Box checkpoints in the middle of the copy.</summary>
    private string MakeSnapshot()
    {
        var source = paths.Database;
        if (!File.Exists(source))
            throw UnboxException.DatabaseUnavailable(L10n.Text("streemfs.db is missing", "brak pliku streemfs.db"));

        var folder = Path.Combine(Path.GetTempPath(), "unbox-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(folder);
        for (int attempt = 0; attempt < 5; attempt++)
        {
            var before = Signature(source);
            try
            {
                Copy(source, Path.Combine(folder, "streemfs.db"));
                if (File.Exists(source + "-wal")) Copy(source + "-wal", Path.Combine(folder, "streemfs.db-wal"));
            }
            catch (IOException)
            {
                Thread.Sleep(200);
                continue;
            }
            if (Signature(source) == before) return folder;
            Thread.Sleep(200);
        }
        Directory.Delete(folder, recursive: true);
        throw UnboxException.DatabaseUnavailable(L10n.Text("the database kept changing while it was copied",
                                                           "baza zmieniała się podczas kopiowania"));
    }

    /// <summary>Box keeps the database open; FileShare.ReadWrite lets us read it anyway.</summary>
    private static void Copy(string from, string to)
    {
        using var input = new FileStream(from, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        using var output = new FileStream(to, FileMode.Create, FileAccess.Write);
        input.CopyTo(output);
    }

    private static string Signature(string path)
    {
        var info = new FileInfo(path);
        return info.Exists ? $"{info.LastWriteTimeUtc.Ticks}-{info.Length}" : "";
    }
}
