# Generates Windows icon assets from the macOS 1024px master icon.
# Source: CursorFollowMac/CursorFollowMac/Assets.xcassets/AppIcon.appiconset/icon_1024.png
# Run from the repo root:  pwsh -File tools/gen-win-icons.ps1
[CmdletBinding()]
param(
    [string]$Master = "CursorFollowMac/CursorFollowMac/Assets.xcassets/AppIcon.appiconset/icon_1024.png",
    [string]$AssetsDir = "CursorFollowWin/Assets",
    [string]$RepoIconDir = "Docs/images"
)

Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = "Stop"

$masterPath = (Resolve-Path $Master).Path
$assetsPath = (Resolve-Path $AssetsDir).Path
$repoIconPath = (Resolve-Path $RepoIconDir).Path
$src = [System.Drawing.Bitmap]::FromFile($masterPath)

# Produce a high-quality square resize of the master into a new 32bpp ARGB bitmap.
function New-Resized([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.DrawImage($src, (New-Object System.Drawing.Rectangle(0, 0, $size, $size)))
    $g.Dispose()
    return $bmp
}

# Draw the square icon centered (no upscaling beyond canvas height) on a transparent canvas.
function New-Canvas([int]$w, [int]$h, [double]$fill = 0.82) {
    $bmp = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)
    $side = [int]([Math]::Min($w, $h) * $fill)
    $x = [int](($w - $side) / 2)
    $y = [int](($h - $side) / 2)
    $g.DrawImage($src, (New-Object System.Drawing.Rectangle($x, $y, $side, $side)))
    $g.Dispose()
    return $bmp
}

function Save-Png([System.Drawing.Bitmap]$bmp, [string]$name) {
    $out = Join-Path $assetsPath $name
    $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Host ("  {0,-55} {1}x{2}" -f $name, $bmp.Width, $bmp.Height)
}

Write-Host "Generating tile PNGs ->" $assetsPath
$square = {
    param($size, $name)
    $b = New-Resized $size
    Save-Png $b $name
    $b.Dispose()
}
& $square 48 "LockScreenLogo.scale-200.png"
& $square 300 "Square150x150Logo.scale-200.png"
& $square 88 "Square44x44Logo.scale-200.png"
& $square 24 "Square44x44Logo.targetsize-24_altform-unplated.png"
& $square 48 "Square44x44Logo.targetsize-48_altform-lightunplated.png"
& $square 50 "StoreLogo.png"

$splash = New-Canvas 1240 600 0.75
Save-Png $splash "SplashScreen.scale-200.png"
$splash.Dispose()

$wide = New-Canvas 620 300 0.78
Save-Png $wide "Wide310x150Logo.scale-200.png"
$wide.Dispose()

# ---- Multi-resolution AppIcon.ico ----
# Small sizes use uncompressed 32bpp BGRA DIB entries (maximum LoadImage compatibility);
# 256px uses an embedded PNG to keep the file small.
$icoSizes = @(16, 24, 32, 48, 64, 128, 256)

function Get-DibBytes([System.Drawing.Bitmap]$bmp) {
    $w = $bmp.Width; $h = $bmp.Height
    $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
    $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $stride = $data.Stride
    $buf = New-Object byte[] ($stride * $h)
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $buf, 0, $buf.Length)
    $bmp.UnlockBits($data)

    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    # BITMAPINFOHEADER
    $bw.Write([int]40)             # biSize
    $bw.Write([int]$w)             # biWidth
    $bw.Write([int]($h * 2))       # biHeight (image + AND mask)
    $bw.Write([int16]1)            # biPlanes
    $bw.Write([int16]32)           # biBitCount
    $bw.Write([int]0)              # biCompression BI_RGB
    $bw.Write([int]0)              # biSizeImage
    $bw.Write([int]0); $bw.Write([int]0)   # ppm x/y
    $bw.Write([int]0); $bw.Write([int]0)   # clrUsed / clrImportant
    # XOR pixel data, bottom-up
    for ($y = $h - 1; $y -ge 0; $y--) {
        $bw.Write($buf, $y * $stride, $w * 4)
    }
    # AND mask, all-zero (opaque), rows padded to 32-bit
    $maskRow = [int]([Math]::Floor(($w + 31) / 32) * 4)
    $zeros = New-Object byte[] ($maskRow * $h)
    $bw.Write($zeros, 0, $zeros.Length)
    $bw.Flush()
    return $ms.ToArray()
}

function Get-PngBytes([System.Drawing.Bitmap]$bmp) {
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    return $ms.ToArray()
}

$entries = @()
foreach ($s in $icoSizes) {
    $b = New-Resized $s
    if ($s -ge 256) { $bytes = Get-PngBytes $b } else { $bytes = Get-DibBytes $b }
    $entries += [pscustomobject]@{ Size = $s; Bytes = $bytes }
    $b.Dispose()
}

$icoPath = Join-Path $assetsPath "AppIcon.ico"
$fs = [System.IO.File]::Create($icoPath)
$w = New-Object System.IO.BinaryWriter($fs)
$w.Write([int16]0)                 # reserved
$w.Write([int16]1)                 # type = icon
$w.Write([int16]$entries.Count)    # count
$offset = 6 + (16 * $entries.Count)
foreach ($e in $entries) {
    $dim = if ($e.Size -ge 256) { 0 } else { $e.Size }
    $w.Write([byte]$dim)           # width
    $w.Write([byte]$dim)           # height
    $w.Write([byte]0)              # colors
    $w.Write([byte]0)              # reserved
    $w.Write([int16]1)             # planes
    $w.Write([int16]32)            # bpp
    $w.Write([int]$e.Bytes.Length) # bytesInRes
    $w.Write([int]$offset)         # offset
    $offset += $e.Bytes.Length
}
foreach ($e in $entries) { $w.Write($e.Bytes, 0, $e.Bytes.Length) }
$w.Flush(); $fs.Close()
Write-Host ("  {0,-55} {1} entries -> {2}" -f "AppIcon.ico", $entries.Count, ($icoSizes -join ","))

# ---- Repo / README icon ----
$repoIcon = New-Resized 256
$repoOut = Join-Path $repoIconPath "app-icon.png"
$repoIcon.Save($repoOut, [System.Drawing.Imaging.ImageFormat]::Png)
$repoIcon.Dispose()
Write-Host ("  {0,-55} 256x256" -f "Docs/images/app-icon.png")

$src.Dispose()
Write-Host "Done."
