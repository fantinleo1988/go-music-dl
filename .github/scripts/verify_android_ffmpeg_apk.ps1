[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ApkPath,
    [Parameter(Mandatory = $true)]
    [string[]]$Abis,
    [string]$AndroidHome = $env:ANDROID_HOME
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

if (-not (Test-Path $ApkPath)) {
    throw "APK não encontrado: $ApkPath"
}

$apkFull = [IO.Path]::GetFullPath($ApkPath)
$zip = [IO.Compression.ZipFile]::OpenRead($apkFull)
try {
$expandedAbis = @($Abis | ForEach-Object { $_ -split "," } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

foreach ($abi in $expandedAbis) {
        foreach ($tool in @("ffmpeg", "ffprobe")) {
            $assetEntryName = "assets/ffmpeg/$abi/$tool"
            if ($null -ne $zip.GetEntry($assetEntryName)) {
                throw "$apkFull não deve conter $assetEntryName; executáveis empacotados devem ficar em lib/$abi como bibliotecas nativas para que o Android 10+ possa executá-los"
            }

            $entryName = "lib/$abi/lib$tool.so"
            $entry = $zip.GetEntry($entryName)
            if ($null -eq $entry) {
                throw "Faltando $entryName em $apkFull"
            }
            if ($entry.Length -lt 1048576) {
                throw "$entryName em $apkFull é inesperadamente pequeno ($($entry.Length) bytes)"
            }
        }

        $libcxxEntryName = "lib/$abi/libc++_shared.so"
        $libcxxEntry = $zip.GetEntry($libcxxEntryName)
        if ($null -eq $libcxxEntry) {
            throw "Faltando $libcxxEntryName em $apkFull"
        }
        if ($libcxxEntry.Length -lt 1048576) {
            throw "$libcxxEntryName em $apkFull é inesperadamente pequeno ($($libcxxEntry.Length) bytes)"
        }
    }
}
finally {
    $zip.Dispose()
}

$buildToolsRoot = Join-Path $AndroidHome "build-tools"
$buildTools = Get-ChildItem -LiteralPath $buildToolsRoot -Directory |
    Sort-Object -Property @{ Expression = { try { [version]$_.Name } catch { [version]"0.0.0" } }; Descending = $true } |
    Select-Object -First 1
if ($null -eq $buildTools) {
    throw "Nenhum build-tools do Android encontrado em $buildToolsRoot"
}
$apkSigner = Join-Path $buildTools.FullName "apksigner.bat"
& $apkSigner verify --verbose $apkFull
if ($LASTEXITCODE -ne 0) {
    throw "apksigner verify falhou para $apkFull"
}

Write-Host "Verificados libffmpeg.so, libffprobe.so e libc++_shared.so empacotados em lib/<abi> no $apkFull"
