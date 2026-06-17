namespace CursorFollowWin;

/// <summary>
/// Constants shared across the tracking, capture, and output layers. Kept here so no layer has to
/// reach into another assembly for a value both sides need (for example, the window tracker must
/// recognize and skip the app's own output window by title).
/// </summary>
public static class CaptureConstants
{
    /// <summary>Title of the shareable output window. The tracker excludes it from enumeration and
    /// the capture controller refuses it as a target, so they must agree on the exact text.</summary>
    public const string OutputWindowTitle = "CursorFollow Output";
}
