[CmdletBinding()]
param(
    [string]$AssetsRoot = "desktop_app\ffmpeg\android",
    [string]$AndroidHome =$env:ANDROID_HOME,
    [Parameter(Mandatory = $true)]
    [string]$KeystoreFile,
    [Parameter(Mandatory = $true)]
    [string]$KeystorePassword
)

$ErrorActionPreference = "Stop"

function Get-LatestBuildTools {
    param([string]$SdkHome)

    if ([string]::IsNullOrWhiteSpace($SdkHome)) {
        throw "ANDROID_HOME está vazio"
    }

    $buildToolsRoot = Join-Path$SdkHome "build-tools"
    $buildTools = Get-ChildItem -LiteralPath$buildToolsRoot -Directory |
        Sort-Object -Property @{ Expression = { try { [version]$_.Name } catch { [version]"0.0.0" } }; Descending = $true } |
        Select-Object -First 1

    if ($null -eq$buildTools) {
        throw "Nenhum build-tools do Android encontrado em $buildToolsRoot"
    }
    return $buildTools.FullName
}

function Remove-ApkEntries {
    param(
        [string]$ApkPath,
        [string]$Aapt
    )

    $entries = @(& $Aapt list$ApkPath)
    if ($LASTEXITCODE -ne 0) {
        throw "aapt list falhou para $ApkPath"
    }

    $removeEntries = @(
        $entries \vert{} Where-Object {$_ -like "META-INF/*" -or
            $_ -like "assets/ffmpeg/*" -or
            $_ -match "^lib/[^/]+/lib(ffmpeg\vert{}ffprobe\vert{}c\+\+_shared)\.so$"
        }
    )

    if ($removeEntries.Count -eq 0) {
        return
    }

    & $Aapt remove$ApkPath @removeEntries
    if ($LASTEXITCODE -ne 0) {
        throw "aapt remove falhou para $ApkPath"
    }
}

function Add-ApkAssets {
    param(
        [string]$ApkPath,
        [string[]]$Abis,
        [string]$AssetsRootFull,
        [string]$Aapt,
        [string]$WorkRoot
    )

    $stageRoot = Join-Path$WorkRoot "aapt-assets"
    $relativePaths = New-Object System.Collections.Generic.List[string]

    # O Android 10+ (targetSdk >= 29) proíbe a execução de binários do diretório
    # de arquivos privados do app. O único diretório que a plataforma marca como
    # executável é o diretório de biblioteca nativa extraída, portanto, envia o
    # ffmpeg/ffprobe como lib/<abi>/lib*.so. O PackageManager extrai isso para o
    # nativeLibraryDir no momento da instalação (o manifesto do APK mantém o
    # padrão android:extractNativeLibs="true").
    $toolMap = @{
        "ffmpeg"           = "libffmpeg.so"
        "ffprobe"          = "libffprobe.so"
        "libc++_shared.so" = "libc++_shared.so"
    }

    foreach ($abi in$Abis) {
        foreach ($tool in @("ffmpeg", "ffprobe", "libc++_shared.so")) {
            $source = Join-Path$AssetsRootFull (Join-Path $abi$tool)
            if (-not (Test-Path $source)) {
                throw "Faltando pacote $tool para $abi em$source"
            }

            $libName =$toolMap[$tool]$relativePath = "lib/$abi/$libName"
            $destination = Join-Path $stageRoot (Join-Path "lib\$abi" $libName)
            New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($destination)) -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination$destination -Force
            $relativePaths.Add($relativePath)
        }
    }

    if ($relativePaths.Count -eq 0) {
        return
    }

    Push-Location $stageRoot
    try {
        $relativePathArray = @($relativePaths.ToArray())
        & $Aapt add$ApkPath @relativePathArray
        if ($LASTEXITCODE -ne 0) {
            throw "aapt add falhou para $ApkPath"
        }
    }
    finally {
        Pop-Location
    }
}

function Inject-Tools {
    param(
        [string]$ApkPath,
        [string[]]$Abis,
        [string]$AssetsRootFull,
        [string]$Aapt,
        [string]$ZipAlign,
        [string]$ApkSigner,
        [string]$KeystoreFileFull,
        [string]$Password
    )

    if (-not (Test-Path $ApkPath)) {
        Write-Host "Pulando o APK ausente $ApkPath"
        return
    }

    $apkFull = [IO.Path]::GetFullPath($ApkPath)$workRoot = Join-Path ([IO.Path]::GetTempPath()) ("music-dl-apk-inject-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $workRoot -Force | Out-Null

    try {
        $unsignedApk = Join-Path$workRoot ([IO.Path]::GetFileName($apkFull))$alignedApk = Join-Path $workRoot ("aligned-" + [IO.Path]::GetFileName($apkFull))
        Copy-Item -LiteralPath $apkFull -Destination$unsignedApk -Force

        Remove-ApkEntries -ApkPath $unsignedApk -Aapt$Aapt
        Add-ApkAssets -ApkPath $unsignedApk -Abis $Abis -AssetsRootFull$AssetsRootFull -Aapt $Aapt -WorkRoot$workRoot

        & $ZipAlign -f -p 4 $unsignedApk$alignedApk
        if ($LASTEXITCODE -ne 0) {
            throw "zipalign falhou para $apkFull"
        }

        & $ApkSigner sign --ks-pass "pass:$Password" --ks $KeystoreFileFull$alignedApk
        if ($LASTEXITCODE -ne 0) {
            throw "apksigner sign falhou para $apkFull"
        }

        & $ApkSigner verify --verbose$alignedApk
        if ($LASTEXITCODE -ne 0) {
            throw "apksigner verify falhou para $apkFull"
        }

        Copy-Item -LiteralPath $alignedApk -Destination$apkFull -Force
        Write-Host "Fez o empacotamento dos recursos ffmpeg e ffprobe em $apkFull"
    }
    finally {
        Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$assetsRootFull = [IO.Path]::GetFullPath($AssetsRoot)
$keystoreFileFull = [IO.Path]::GetFullPath($KeystoreFile)
$buildTools = Get-LatestBuildTools -SdkHome$AndroidHome
$aapt = Join-Path$buildTools "aapt.exe"
$zipAlign = Join-Path$buildTools "zipalign.exe"
$apkSigner = Join-Path$buildTools "apksigner.bat"

if (-not (Test-Path $aapt)) {
    throw "aapt não encontrado em $aapt"
}
if (-not (Test-Path $zipAlign)) {
    throw "zipalign não encontrado em $zipAlign"
}
if (-not (Test-Path $apkSigner)) {
    throw "apksigner não encontrado em $apkSigner"
}

$apkSpecs = @(
    @{ Path = "music-dl.apk";           Abis = @("armeabi-v7a", "arm64-v8a", "x86", "x86_64") },
    @{ Path = "music-dl_arm64-v8a.apk"; Abis = @("arm64-v8a") },
    @{ Path = "music-dl_x86_64.apk";    Abis = @("x86_64") }
)

foreach ($spec in$apkSpecs) {
    Inject-Tools `
        -ApkPath $spec.Path `
        -Abis $spec.Abis `
        -AssetsRootFull $assetsRootFull `
        -Aapt $aapt `
        -ZipAlign $zipAlign `
        -ApkSigner $apkSigner `
        -KeystoreFileFull $keystoreFileFull `
        -Password $KeystorePassword
}
