param(
    [ValidateSet('runtime', 'devel')]
    [string]$Variant = 'runtime',

    [string]$ImageName = 'hegenai/comfyui',

    [ValidateSet('cu128', 'cu126')]
    [string]$CudaProfile = 'cu128',

    [string]$UbuntuVersion = 'ubuntu22.04',

    [string]$MiniforgeInstallerUrl = 'https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh',

    [string]$PythonVersion = '3.12',

    [string]$ComfyUIRepo = 'https://github.com/Comfy-Org/ComfyUI.git',

    [string]$ComfyUIRef = 'master',

    [ValidateSet('22', '24')]
    [string]$NodeJsVersion = '22',

    [string]$TorchVersion = '2.7.0',

    [switch]$Push,

    [switch]$NoCache
)

$ErrorActionPreference = 'Stop'

function Get-DirectorySizeBytes {
    param(
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return 0
    }

    $items = Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue
    if (-not $items) {
        return 0
    }

    return ($items | Measure-Object -Property Length -Sum).Sum
}

function Format-Bytes {
    param(
        [double]$Bytes
    )

    if ($Bytes -ge 1GB) { return '{0:N2} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N2} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N2} KB' -f ($Bytes / 1KB) }
    return '{0:N0} B' -f $Bytes
}

function Show-CacheState {
    param(
        [string]$Label,
        [string]$CacheDir,
        [string]$CacheNewDir
    )

    $cacheExists = Test-Path $CacheDir
    $cacheNewExists = Test-Path $CacheNewDir
    $cacheSize = Format-Bytes (Get-DirectorySizeBytes $CacheDir)
    $cacheNewSize = Format-Bytes (Get-DirectorySizeBytes $CacheNewDir)

    Write-Host "[$Label] docker/.buildx-cache exists=$cacheExists size=$cacheSize"
    Write-Host "[$Label] docker/.buildx-cache-new exists=$cacheNewExists size=$cacheNewSize"
}

$dockerDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $dockerDir
$cacheDir = Join-Path $dockerDir '.buildx-cache'
$cacheNewDir = Join-Path $dockerDir '.buildx-cache-new'

$cudaProfileMap = @{
    'cu128' = @{
        CudaVersion = '12.8.2'
        PyTorchIndexUrl = 'https://download.pytorch.org/whl/cu128'
    }
    'cu126' = @{
        CudaVersion = '12.6.3'
        PyTorchIndexUrl = 'https://download.pytorch.org/whl/cu126'
    }
}

$torchVersionMap = @{
    '2.7.1' = @{
        TorchVisionVersion = '0.22.1'
        TorchAudioVersion = '2.7.1'
    }
    '2.7.0' = @{
        TorchVisionVersion = '0.22.0'
        TorchAudioVersion = '2.7.0'
    }
    '2.6.0' = @{
        TorchVisionVersion = '0.21.0'
        TorchAudioVersion = '2.6.0'
    }
}

if (-not $cudaProfileMap.ContainsKey($CudaProfile)) {
    $supportedCudaProfiles = ($cudaProfileMap.Keys | Sort-Object) -join ', '
    throw "不支持的 CudaProfile：$CudaProfile。当前支持：$supportedCudaProfiles"
}

if (-not $torchVersionMap.ContainsKey($TorchVersion)) {
    $supportedTorchVersions = ($torchVersionMap.Keys | Sort-Object -Descending) -join ', '
    throw "不支持的 TorchVersion：$TorchVersion。当前支持：$supportedTorchVersions"
}

$cudaVersion = $cudaProfileMap[$CudaProfile].CudaVersion
$pyTorchIndexUrl = $cudaProfileMap[$CudaProfile].PyTorchIndexUrl
$builderCudaImage = "nvidia/cuda:$cudaVersion-devel-$UbuntuVersion"
$finalCudaImage = "nvidia/cuda:$cudaVersion-$Variant-$UbuntuVersion"
$uvImage = 'ghcr.io/astral-sh/uv:latest'
$tag = "${ImageName}:${CudaProfile}-${Variant}"
$torchVisionVersion = $torchVersionMap[$TorchVersion].TorchVisionVersion
$torchAudioVersion = $torchVersionMap[$TorchVersion].TorchAudioVersion

if (Test-Path $cacheNewDir) {
    Remove-Item $cacheNewDir -Recurse -Force
}

$arguments = @(
    'buildx', 'build',
    '--file', 'docker/Dockerfile',
    '--tag', $tag,
    '--build-arg', "BUILDER_CUDA_IMAGE=$builderCudaImage",
    '--build-arg', "FINAL_CUDA_IMAGE=$finalCudaImage",
    '--build-arg', "MINIFORGE_INSTALLER_URL=$MiniforgeInstallerUrl",
    '--build-arg', "PYTHON_VERSION=$PythonVersion",
    '--build-arg', "COMFYUI_REPO=$ComfyUIRepo",
    '--build-arg', "COMFYUI_REF=$ComfyUIRef",
    '--build-arg', "NODEJS_VERSION=$NodeJsVersion",
    '--build-arg', "TORCH_VERSION=$TorchVersion",
    '--build-arg', "PYTORCH_INDEX_URL=$pyTorchIndexUrl",
    '--cache-to', "type=local,dest=$cacheNewDir,mode=max"
)

if (Test-Path $cacheDir) {
    $arguments += @('--cache-from', "type=local,src=$cacheDir")
}

if ($Push) {
    $arguments += '--push'
} else {
    $arguments += '--load'
}

if ($NoCache) {
    $arguments += '--no-cache'
}

$arguments += '.'

Push-Location $root

try {
    Show-CacheState -Label 'BeforeBuild' -CacheDir $cacheDir -CacheNewDir $cacheNewDir

    $pullImages = @($builderCudaImage, $finalCudaImage, $uvImage) | Select-Object -Unique
    foreach ($image in $pullImages) {
        & docker pull $image
        if ($LASTEXITCODE -ne 0) {
            throw "docker pull 执行失败：$image，退出码：$LASTEXITCODE"
        }
    }

    & docker @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "docker buildx build 执行失败，退出码：$LASTEXITCODE"
    }

    if (Test-Path $cacheDir) {
        Remove-Item $cacheDir -Recurse -Force
    }

    if (Test-Path $cacheNewDir) {
        Rename-Item $cacheNewDir '.buildx-cache'
    }

    Show-CacheState -Label 'AfterBuild' -CacheDir $cacheDir -CacheNewDir $cacheNewDir
}
finally {
    if ($LASTEXITCODE -ne 0) {
        Show-CacheState -Label 'OnFailure' -CacheDir $cacheDir -CacheNewDir $cacheNewDir
        if (Test-Path $cacheNewDir) {
            Write-Host "[OnFailure] 检测到未轮换的 docker/.buildx-cache-new，可用于观察这次失败前导出的缓存内容。"
        }
    }
    Pop-Location
}
