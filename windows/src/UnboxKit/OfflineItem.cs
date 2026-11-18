namespace Unbox.Kit;

public sealed record OfflineItem(string RelativePath, string FullPath, bool IsFolder)
{
    private string[] Components => RelativePath.Split(['\\', '/'], StringSplitOptions.RemoveEmptyEntries);

    public string Id => RelativePath;
    public string Name => Components.LastOrDefault() ?? RelativePath;

    /// <summary>Top-level Box folder (usually the client); items directly in the Box root return "Box".</summary>
    public string Group => Components.Length > 1 ? Components[0] : "Box";

    /// <summary>Folders between the group and the item itself.</summary>
    public IReadOnlyList<string> IntermediatePath => Components.Length > 2 ? Components[1..^1] : [];
}
