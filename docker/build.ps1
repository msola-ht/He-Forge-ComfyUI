param(
    [ValidateSet('runtime', 'devel')]
    [string]$Variant = 'runtime',

    [ValidateSet('bootstrap', 'final', '')]
    [string]$BuildStage = '',

    [string]$ImageName = 'hegenai/comfyui',

    [ValidateSet('cu128', 'cu126')]
    [string]$CudaProfile = 'cu128',

    [ValidateSet('22', '24')]
    [string]$UbuntuVersion = '22',

    [string]$MiniforgeInstallerUrl = 'https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh',

    [string]$PythonVersion = '3.12',

    [string]$ComfyUIRepo = 'https://github.com/Comfy-Org/ComfyUI.git',

    [string]$ComfyUIRef = 'master',

    [ValidateSet('22', '24')]
    [string]$NodeJsVersion = '22',

    [string]$TorchVersion = '2.7.0',

    [switch]$FromEnv,

    [switch]$Push,

    [switch]$NoCache
)

$ErrorActionPreference = 'Stop'

$dockerDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $dockerDir
$scriptDir = Join-Path $dockerDir 'scripts'
$envFile = Join-Path $dockerDir '.env'
$envExampleFile = Join-Path $dockerDir '.env.example'

. (Join-Path $scriptDir 'env.ps1')
. (Join-Path $scriptDir 'versions.ps1')
. (Join-Path $scriptDir 'prompt.ps1')
. (Join-Path $scriptDir 'cache.ps1')

Ensure-EnvFile -EnvFile $envFile -EnvExampleFile $envExampleFile

$defaults = @{
    ImageName = $ImageName
    CudaProfile = $CudaProfile
    UbuntuVersion = $UbuntuVersion
    MiniforgeInstallerUrl = $MiniforgeInstallerUrl
    PythonVersion = $PythonVersion
    ComfyUIRepo = $ComfyUIRepo
    ComfyUIRef = $ComfyUIRef
    NodeJsVersion = $NodeJsVersion
    TorchVersion = $TorchVersion
}

$versionConfig = Get-VersionConfig -Values (Read-EnvFile -Path $envFile) -Defaults $defaults
$versionConfig = Merge-BoundVersionConfig -Config $versionConfig -BoundParameters $PSBoundParameters

$ImageName = $versionConfig.ImageName
$CudaProfile = $versionConfig.CudaProfile
$UbuntuVersion = $versionConfig.UbuntuVersion
$MiniforgeInstallerUrl = $versionConfig.MiniforgeInstallerUrl
$PythonVersion = $versionConfig.PythonVersion
$ComfyUIRepo = $versionConfig.ComfyUIRepo
$ComfyUIRef = $versionConfig.ComfyUIRef
$NodeJsVersion = $versionConfig.NodeJsVersion
$TorchVersion = $versionConfig.TorchVersion

if (-not $FromEnv) {
    Show-VersionConfig -Config $versionConfig
    $shouldConfigure = Select-YesNo -Label 'Modify version configuration before build?' -DefaultValue $false

    if ($shouldConfigure) {
        $versionConfig = Edit-VersionConfig -Config $versionConfig

        Save-VersionConfig `
            -Path $envFile `
            -ImageName $versionConfig.ImageName `
            -CudaProfile $versionConfig.CudaProfile `
            -UbuntuVersion $versionConfig.UbuntuVersion `
            -MiniforgeInstallerUrl $versionConfig.MiniforgeInstallerUrl `
            -PythonVersion $versionConfig.PythonVersion `
            -ComfyUIRepo $versionConfig.ComfyUIRepo `
            -ComfyUIRef $versionConfig.ComfyUIRef `
            -NodeJsVersion $versionConfig.NodeJsVersion `
            -TorchVersion $versionConfig.TorchVersion

        Write-Host ""
        Write-Host "Saved version configuration to docker/.env"

        $ImageName = $versionConfig.ImageName
        $CudaProfile = $versionConfig.CudaProfile
        $UbuntuVersion = $versionConfig.UbuntuVersion
        $MiniforgeInstallerUrl = $versionConfig.MiniforgeInstallerUrl
        $PythonVersion = $versionConfig.PythonVersion
        $ComfyUIRepo = $versionConfig.ComfyUIRepo
        $ComfyUIRef = $versionConfig.ComfyUIRef
        $NodeJsVersion = $versionConfig.NodeJsVersion
        $TorchVersion = $versionConfig.TorchVersion
    }
}

if (-not $BuildStage) {
    $BuildStage = Select-BuildStage -CurrentValue 'final'
}

Assert-UbuntuVersion -UbuntuVersion $UbuntuVersion
Assert-NodeJsVersion -NodeJsVersion $NodeJsVersion
Assert-TorchVersion -TorchVersion $TorchVersion

$cudaImageSet = Resolve-CudaImageSet -CudaProfile $CudaProfile -UbuntuVersion $UbuntuVersion -Variant $Variant
$builderCudaImage = $cudaImageSet.BuilderCudaImage
$finalCudaImage = $cudaImageSet.FinalCudaImage
$uvImage = 'ghcr.io/astral-sh/uv:latest'
$tagSuffix = if ($BuildStage -eq 'bootstrap') { "$CudaProfile-$Variant-bootstrap" } else { "$CudaProfile-$Variant" }
$tag = "${ImageName}:${tagSuffix}"

$legacyCacheDir = Join-Path $dockerDir '.buildx-cache'
$legacyCacheNewDir = Join-Path $dockerDir '.buildx-cache-new'
$bootstrapCacheDir = Join-Path $dockerDir '.buildx-cache-bootstrap'
$bootstrapCacheNewDir = Join-Path $dockerDir '.buildx-cache-bootstrap-new'
$finalCacheDir = Join-Path $dockerDir '.buildx-cache-final'
$finalCacheNewDir = Join-Path $dockerDir '.buildx-cache-final-new'
$cacheDir = if ($BuildStage -eq 'bootstrap') { $bootstrapCacheDir } else { $finalCacheDir }
$cacheNewDir = if ($BuildStage -eq 'bootstrap') { $bootstrapCacheNewDir } else { $finalCacheNewDir }

if (Test-Path $cacheNewDir) {
    Remove-Item $cacheNewDir -Recurse -Force
}

$arguments = @(
    'buildx', 'build',
    '--file', 'docker/Dockerfile',
    '--target', $BuildStage,
    '--tag', $tag,
    '--build-arg', "BUILDER_CUDA_IMAGE=$builderCudaImage",
    '--build-arg', "FINAL_CUDA_IMAGE=$finalCudaImage",
    '--build-arg', "MINIFORGE_INSTALLER_URL=$MiniforgeInstallerUrl",
    '--build-arg', "PYTHON_VERSION=$PythonVersion",
    '--build-arg', "COMFYUI_REPO=$ComfyUIRepo",
    '--build-arg', "COMFYUI_REF=$ComfyUIRef",
    '--build-arg', "CUDA_PROFILE=$CudaProfile",
    '--build-arg', "UBUNTU_VERSION=$UbuntuVersion",
    '--build-arg', "NODEJS_VERSION=$NodeJsVersion",
    '--build-arg', "TORCH_VERSION=$TorchVersion",
    '--cache-to', "type=local,dest=$cacheNewDir,mode=max"
)

$cacheFromDirs = @()
if (-not (Test-Path $bootstrapCacheDir) -and -not (Test-Path $finalCacheDir) -and (Test-Path $legacyCacheDir)) {
    $cacheFromDirs += $legacyCacheDir
}
if ($BuildStage -eq 'final' -and (Test-Path $bootstrapCacheDir)) {
    $cacheFromDirs += $bootstrapCacheDir
}
if (Test-Path $cacheDir) {
    $cacheFromDirs += $cacheDir
}

foreach ($cacheFromDir in ($cacheFromDirs | Select-Object -Unique)) {
    $arguments += @('--cache-from', "type=local,src=$cacheFromDir")
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
    Show-CacheState -Label 'LegacyCache' -CacheDir $legacyCacheDir -CacheNewDir $legacyCacheNewDir
    if ($BuildStage -eq 'final') {
        Show-CacheState -Label 'BootstrapCache' -CacheDir $bootstrapCacheDir -CacheNewDir $bootstrapCacheNewDir
    }

    $pullImages = @($builderCudaImage, $finalCudaImage, $uvImage) | Select-Object -Unique
    foreach ($image in $pullImages) {
        & docker pull $image
        if ($LASTEXITCODE -ne 0) {
            throw "docker pull failed: $image, exit code: $LASTEXITCODE"
        }
    }

    & docker @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "docker buildx build failed, exit code: $LASTEXITCODE"
    }

    if (Test-Path $cacheDir) {
        Remove-Item $cacheDir -Recurse -Force
    }

    if (Test-Path $cacheNewDir) {
        Rename-Item -LiteralPath $cacheNewDir -NewName (Split-Path -Leaf $cacheDir)
    }

    Show-CacheState -Label 'AfterBuild' -CacheDir $cacheDir -CacheNewDir $cacheNewDir
    Show-CacheState -Label 'LegacyCache' -CacheDir $legacyCacheDir -CacheNewDir $legacyCacheNewDir
    if ($BuildStage -eq 'final') {
        Show-CacheState -Label 'BootstrapCache' -CacheDir $bootstrapCacheDir -CacheNewDir $bootstrapCacheNewDir
    }
}
finally {
    if ($LASTEXITCODE -ne 0) {
        Show-CacheState -Label 'OnFailure' -CacheDir $cacheDir -CacheNewDir $cacheNewDir
        if (Test-Path $cacheNewDir) {
            $cacheNewName = Split-Path -Leaf $cacheNewDir
            Write-Host "[OnFailure] docker/$cacheNewName exists and was not rotated. Inspect it for cache exported before failure."
        }
    }
    Pop-Location
}
