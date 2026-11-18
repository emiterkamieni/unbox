using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace Unbox.Kit;

public enum PinState
{
    /// <summary>No preference: the content may stay or be removed by the sync provider.</summary>
    Unspecified = 0,
    /// <summary>“Always keep on this device”.</summary>
    Pinned = 1,
    /// <summary>“Free up space”: the sync provider removes the local content.</summary>
    Unpinned = 2,
}

/// <summary>
/// Windows Cloud Files API – the documented mechanism behind “Always keep on this device” and
/// “Free up space” in File Explorer. Box Drive (new architecture, 2.47+) is built on it, and
/// CfSetPinState may be called by any application, not only the sync provider.
/// </summary>
public static partial class CloudFiles
{
    public const int AttributePinned = 0x00080000;
    public const int AttributeUnpinned = 0x00100000;
    public const int AttributeRecallOnOpen = 0x00040000;
    public const int AttributeRecallOnDataAccess = 0x00400000;
    public const int AttributeOffline = 0x00001000;

    private const uint FileReadAttributes = 0x80;
    private const uint ShareAll = 0x7;
    private const uint OpenExisting = 3;
    private const uint FlagBackupSemantics = 0x02000000; // needed to open directories
    private const uint FlagOpenReparsePoint = 0x00200000;
    private const int SetPinFlagRecurse = 0x1;

    public static int RawAttributes(string path) => (int)File.GetAttributes(path);

    public static bool IsPinned(string path) => (RawAttributes(path) & AttributePinned) != 0;

    /// <summary>Content of a file is only in the cloud (a dehydrated placeholder).</summary>
    public static bool IsCloudOnly(int attributes) => (attributes & (AttributeRecallOnDataAccess | AttributeOffline)) != 0;

    /// <summary>
    /// A directory whose listing has not been fetched yet. Listing it would ask Box to download
    /// the listing, and nothing inside it can be available offline.
    /// </summary>
    public static bool IsUnpopulatedDirectory(int attributes) =>
        (attributes & (AttributeRecallOnDataAccess | AttributeRecallOnOpen | AttributeOffline)) != 0;

    public static void SetPinState(string path, PinState state, bool recurse = true)
    {
        using var handle = CreateFileW(path, FileReadAttributes, ShareAll, IntPtr.Zero, OpenExisting,
                                       FlagBackupSemantics | FlagOpenReparsePoint, IntPtr.Zero);
        if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
        int hr = CfSetPinState(handle, (int)state, recurse ? SetPinFlagRecurse : 0, IntPtr.Zero);
        if (hr < 0) throw new Win32Exception(hr, new Win32Exception(hr).Message);
    }

    /// <summary>Bytes actually stored on disk (0 for content that is only in the cloud).</summary>
    public static long AllocatedSize(string path)
    {
        uint low = GetCompressedFileSizeW(path, out uint high);
        if (low == 0xFFFFFFFF && Marshal.GetLastWin32Error() != 0) return 0;
        return ((long)high << 32) | low;
    }

    [LibraryImport("cldapi.dll")]
    private static partial int CfSetPinState(SafeFileHandle handle, int pinState, int pinFlags, IntPtr overlapped);

    [LibraryImport("kernel32.dll", SetLastError = true, StringMarshalling = StringMarshalling.Utf16)]
    private static partial SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);

    [LibraryImport("kernel32.dll", SetLastError = true, StringMarshalling = StringMarshalling.Utf16)]
    private static partial uint GetCompressedFileSizeW(string name, out uint high);
}
