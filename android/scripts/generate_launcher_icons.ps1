param(
    [string]$Source = "..\leafy\Resources\Assets.xcassets\AppIcon.appiconset\AppIcon.png"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$androidRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = [System.IO.Path]::GetFullPath((Join-Path $androidRoot $Source))
$resourceRoot = Join-Path $androidRoot "app\src\main\res"

function Save-ScaledPng {
    param(
        [System.Drawing.Image]$Image,
        [int]$Size,
        [string]$Destination
    )

    $bitmap = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.DrawImage($Image, 0, 0, $Size, $Size)
        $bitmap.Save($Destination, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

$sourceImage = [System.Drawing.Bitmap]::FromFile($sourcePath)
try {
    $legacySizes = [ordered]@{
        "mipmap-mdpi" = 48
        "mipmap-hdpi" = 72
        "mipmap-xhdpi" = 96
        "mipmap-xxhdpi" = 144
        "mipmap-xxxhdpi" = 192
    }
    foreach ($entry in $legacySizes.GetEnumerator()) {
        $directory = Join-Path $resourceRoot $entry.Key
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
        Save-ScaledPng -Image $sourceImage -Size $entry.Value -Destination (Join-Path $directory "ic_launcher.png")
        Save-ScaledPng -Image $sourceImage -Size $entry.Value -Destination (Join-Path $directory "ic_launcher_round.png")
    }

    # Derive the adaptive foreground from the same iOS master. Near-white pixels
    # belong to the master artwork's background and become transparent here.
    $transparentLeaf = New-Object System.Drawing.Bitmap($sourceImage.Width, $sourceImage.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        for ($y = 0; $y -lt $sourceImage.Height; $y++) {
            for ($x = 0; $x -lt $sourceImage.Width; $x++) {
                $pixel = $sourceImage.GetPixel($x, $y)
                $brightnessFloor = [Math]::Min($pixel.R, [Math]::Min($pixel.G, $pixel.B))
                $alpha = if ($brightnessFloor -ge 235) { 0 } else { [Math]::Min(255, (235 - $brightnessFloor) * 12) }
                $transparentLeaf.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($alpha, $pixel.R, $pixel.G, $pixel.B))
            }
        }

        $canvas = New-Object System.Drawing.Bitmap(432, 432, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $graphics = [System.Drawing.Graphics]::FromImage($canvas)
        try {
            $graphics.Clear([System.Drawing.Color]::Transparent)
            $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            # Keep the complete diagonal leaf inside the adaptive icon's 66dp safe circle.
            $graphics.DrawImage($transparentLeaf, 96, 96, 240, 240)
            $drawableDirectory = Join-Path $resourceRoot "drawable-nodpi"
            New-Item -ItemType Directory -Force -Path $drawableDirectory | Out-Null
            $canvas.Save((Join-Path $drawableDirectory "ic_launcher_leaf.png"), [System.Drawing.Imaging.ImageFormat]::Png)
        } finally {
            $graphics.Dispose()
            $canvas.Dispose()
        }
    } finally {
        $transparentLeaf.Dispose()
    }
} finally {
    $sourceImage.Dispose()
}
