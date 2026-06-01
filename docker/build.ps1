param(
    [ValidateSet('runtime', 'devel')]
    [string]$Variant = 'runtime',

    [ValidateSet('bootstrap', 'final', '')]
    [string]$BuildStage = '',

    [string]$ImageName = 'hegenai/comfyui',

    [string]$CudaImageVersion = '12.8.2',

    [string]$PyTorchCudaProfile = 'cu128',

    [ValidateSet('22.04', '24.04')]
    [string]$UbuntuVersion = '22.04',

    [string]$MiniforgeInstallerUrl = 'https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh',

    [string]$PythonVersion = '3.12',

    [string]$ComfyUIRepo = 'https://github.com/Comfy-Org/ComfyUI.git',

    [string]$ComfyUIRef = 'master',

    [ValidateSet('22', '24')]
    [string]$NodeJsVersion = '22',

    [string]$TorchVersion = '2.7.0',

    [string]$PipIndexUrl = '',

    [string]$PipExtraIndexUrl = '',

    [string]$PipTrustedHost = '',

    [string]$PyTorchIndexUrlOverride = '',

    [switch]$FromEnv,

    [switch]$Push,

    [switch]$NoCache,

    [switch]$TestAfterBuild
)

$ErrorActionPreference = 'Stop'

$dockerDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $dockerDir
$scriptDir = Join-Path $dockerDir 'scripts'
$envFile = Join-Path $dockerDir '.env'
$envExampleFile = Join-Path $dockerDir '.env.example'
$pluginManifestFile = Join-Path $dockerDir 'plugins/custom-nodes.json'
$pluginLockResolver = Join-Path $scriptDir 'resolve-plugin-lock.py'

. (Join-Path $scriptDir 'env.ps1')
. (Join-Path $scriptDir 'versions.ps1')
. (Join-Path $scriptDir 'prompt.ps1')
. (Join-Path $scriptDir 'cache.ps1')
. (Join-Path $scriptDir 'test.ps1')

Ensure-EnvFile -EnvFile $envFile -EnvExampleFile $envExampleFile

$defaults = @{
    ImageName = $ImageName
    CudaImageVersion = $CudaImageVersion
    PyTorchCudaProfile = $PyTorchCudaProfile
    UbuntuVersion = $UbuntuVersion
    MiniforgeInstallerUrl = $MiniforgeInstallerUrl
    PythonVersion = $PythonVersion
    ComfyUIRepo = $ComfyUIRepo
    ComfyUIRef = $ComfyUIRef
    NodeJsVersion = $NodeJsVersion
    TorchVersion = $TorchVersion
    PipIndexUrl = $PipIndexUrl
    PipExtraIndexUrl = $PipExtraIndexUrl
    PipTrustedHost = $PipTrustedHost
    PyTorchIndexUrlOverride = $PyTorchIndexUrlOverride
}

$envValues = Read-EnvFile -Path $envFile
$versionConfig = Get-VersionConfig -Values $envValues -Defaults $defaults
$versionConfig = Merge-BoundVersionConfig -Config $versionConfig -BoundParameters $PSBoundParameters

$ImageName = $versionConfig.ImageName
$CudaImageVersion = $versionConfig.CudaImageVersion
$PyTorchCudaProfile = $versionConfig.PyTorchCudaProfile
$UbuntuVersion = $versionConfig.UbuntuVersion
$MiniforgeInstallerUrl = $versionConfig.MiniforgeInstallerUrl
$PythonVersion = $versionConfig.PythonVersion
$ComfyUIRepo = $versionConfig.ComfyUIRepo
$ComfyUIRef = $versionConfig.ComfyUIRef
$NodeJsVersion = $versionConfig.NodeJsVersion
$TorchVersion = $versionConfig.TorchVersion
$PipIndexUrl = $versionConfig.PipIndexUrl
$PipExtraIndexUrl = $versionConfig.PipExtraIndexUrl
$PipTrustedHost = $versionConfig.PipTrustedHost
$PyTorchIndexUrlOverride = $versionConfig.PyTorchIndexUrlOverride

if (-not $FromEnv) {
    Show-VersionConfig -Config $versionConfig
    $shouldConfigure = Select-YesNo -Label '构建前是否修改版本配置？' -DefaultValue $false

    if ($shouldConfigure) {
        $versionConfig = Edit-VersionConfig -Config $versionConfig

        Save-VersionConfig `
            -Path $envFile `
            -ImageName $versionConfig.ImageName `
            -CudaImageVersion $versionConfig.CudaImageVersion `
            -PyTorchCudaProfile $versionConfig.PyTorchCudaProfile `
            -UbuntuVersion $versionConfig.UbuntuVersion `
            -MiniforgeInstallerUrl $versionConfig.MiniforgeInstallerUrl `
            -PythonVersion $versionConfig.PythonVersion `
            -ComfyUIRepo $versionConfig.ComfyUIRepo `
            -ComfyUIRef $versionConfig.ComfyUIRef `
            -NodeJsVersion $versionConfig.NodeJsVersion `
            -TorchVersion $versionConfig.TorchVersion `
            -PipIndexUrl $versionConfig.PipIndexUrl `
            -PipExtraIndexUrl $versionConfig.PipExtraIndexUrl `
            -PipTrustedHost $versionConfig.PipTrustedHost `
            -PyTorchIndexUrlOverride $versionConfig.PyTorchIndexUrlOverride

        Write-Host ""
        Write-Host "已保存版本配置到 docker/.env"

        $ImageName = $versionConfig.ImageName
        $CudaImageVersion = $versionConfig.CudaImageVersion
        $PyTorchCudaProfile = $versionConfig.PyTorchCudaProfile
        $UbuntuVersion = $versionConfig.UbuntuVersion
        $MiniforgeInstallerUrl = $versionConfig.MiniforgeInstallerUrl
        $PythonVersion = $versionConfig.PythonVersion
        $ComfyUIRepo = $versionConfig.ComfyUIRepo
        $ComfyUIRef = $versionConfig.ComfyUIRef
        $NodeJsVersion = $versionConfig.NodeJsVersion
        $TorchVersion = $versionConfig.TorchVersion
        $PipIndexUrl = $versionConfig.PipIndexUrl
        $PipExtraIndexUrl = $versionConfig.PipExtraIndexUrl
        $PipTrustedHost = $versionConfig.PipTrustedHost
        $PyTorchIndexUrlOverride = $versionConfig.PyTorchIndexUrlOverride
    }
}

if (-not $BuildStage) {
    $BuildStage = Select-BuildStage -CurrentValue 'final'
}

if (-not $FromEnv -and -not $PSBoundParameters.ContainsKey('TestAfterBuild')) {
    $TestAfterBuild = Select-YesNo -Label '构建完成后是否运行镜像自检？' -DefaultValue $true
}

Assert-UbuntuVersion -UbuntuVersion $UbuntuVersion
Assert-CudaImageVersion -CudaImageVersion $CudaImageVersion -UbuntuVersion $UbuntuVersion
Assert-NodeJsVersion -NodeJsVersion $NodeJsVersion
Assert-TorchVersion -TorchVersion $TorchVersion
Assert-PyTorchCudaProfile -PyTorchCudaProfile $PyTorchCudaProfile -TorchVersion $TorchVersion

$cudaImageSet = Resolve-CudaImageSet -CudaImageVersion $CudaImageVersion -UbuntuVersion $UbuntuVersion -Variant $Variant
$builderCudaImage = $cudaImageSet.BuilderCudaImage
$finalCudaImage = $cudaImageSet.FinalCudaImage
$ubuntuCacheKey = $cudaImageSet.UbuntuCacheKey
$aptCacheKey = "cuda$CudaImageVersion-$ubuntuCacheKey"
$condaCacheKey = "conda-py$($PythonVersion.Replace('.', ''))"
$pipCacheKey = "pip-py$($PythonVersion.Replace('.', ''))-torch$TorchVersion-$PyTorchCudaProfile"
$pyTorchIndexUrl = if ($PyTorchIndexUrlOverride) {
    $PyTorchIndexUrlOverride.Replace('{profile}', $PyTorchCudaProfile).Replace('{cuda_profile}', $PyTorchCudaProfile)
} else {
    Resolve-PyTorchIndexUrl -PyTorchCudaProfile $PyTorchCudaProfile -TorchVersion $TorchVersion
}
$pyTorchPackageVersions = Resolve-PyTorchPackageVersions -TorchVersion $TorchVersion
$torchVisionVersion = $pyTorchPackageVersions.TorchVisionVersion
$torchAudioVersion = $pyTorchPackageVersions.TorchAudioVersion
$xformersVersion = Resolve-XformersVersion -TorchVersion $TorchVersion -PyTorchCudaProfile $PyTorchCudaProfile
$uvImage = 'ghcr.io/astral-sh/uv:latest'
$tagSuffix = Resolve-ImageTagSuffix -CudaImageVersion $CudaImageVersion -PyTorchCudaProfile $PyTorchCudaProfile -UbuntuVersion $UbuntuVersion -TorchVersion $TorchVersion -PythonVersion $PythonVersion -Variant $Variant -BuildStage $BuildStage
$tag = "${ImageName}:${tagSuffix}"
$cacheKeySuffix = Resolve-CacheKeySuffix -CudaImageVersion $CudaImageVersion -PyTorchCudaProfile $PyTorchCudaProfile -UbuntuVersion $UbuntuVersion -TorchVersion $TorchVersion -PythonVersion $PythonVersion -Variant $Variant
$pluginLockJson = '{"plugins":[]}'
if ($BuildStage -eq 'final') {
    try {
        $pluginLockJson = (& python $pluginLockResolver --manifest $pluginManifestFile)
        if ($LASTEXITCODE -ne 0 -or -not $pluginLockJson) {
            throw "插件锁解析失败。"
        }
    }
    catch {
        throw "解析插件引用失败。请检查网络连通性、git 可用性和插件仓库配置。详细信息：$($_.Exception.Message)"
    }

    $pluginLockJson = $pluginLockJson.Trim()
}

$customNodesHashBytes = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($pluginLockJson))
$customNodesHash = ([System.BitConverter]::ToString($customNodesHashBytes)).Replace('-', '').Substring(0, 12).ToLowerInvariant()
$customNodesLockB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($pluginLockJson))
$comfyUIResolvedCommit = ''

try {
    $comfyUIResolvedCommit = Resolve-RemoteGitCommit -Repo $ComfyUIRepo -Ref $ComfyUIRef
}
catch {
    throw "解析 ComfyUI 引用失败。请检查网络连通性、git 可用性和 COMFYUI_REPO / COMFYUI_REF 配置。详细信息：$($_.Exception.Message)"
}

if ($Push -and $TestAfterBuild) {
    throw "TestAfterBuild 需要本地已加载的镜像。请不要和 -Push 一起使用。"
}

$legacyCacheDir = Join-Path $dockerDir '.buildx-cache'
$legacyCacheNewDir = Join-Path $dockerDir '.buildx-cache-new'
$legacyBootstrapCacheDir = Join-Path $dockerDir '.buildx-cache-bootstrap'
$legacyBootstrapCacheNewDir = Join-Path $dockerDir '.buildx-cache-bootstrap-new'
$legacyFinalCacheDir = Join-Path $dockerDir '.buildx-cache-final'
$legacyFinalCacheNewDir = Join-Path $dockerDir '.buildx-cache-final-new'
$cacheRootDir = Join-Path $dockerDir '.buildx-cache-v2'
$bootstrapCacheParentDir = Join-Path $cacheRootDir 'bootstrap'
$finalCacheParentDir = Join-Path $cacheRootDir 'final'
$bootstrapCacheDir = Join-Path $cacheRootDir "bootstrap/$cacheKeySuffix"
$bootstrapCacheNewDir = Join-Path $cacheRootDir "bootstrap/$cacheKeySuffix-new"
$finalCacheKeySuffix = "$cacheKeySuffix-plugins$customNodesHash"
$finalCacheDir = Join-Path $cacheRootDir "final/$finalCacheKeySuffix"
$finalCacheNewDir = Join-Path $cacheRootDir "final/$finalCacheKeySuffix-new"
$cacheDir = if ($BuildStage -eq 'bootstrap') { $bootstrapCacheDir } else { $finalCacheDir }
$cacheNewDir = if ($BuildStage -eq 'bootstrap') { $bootstrapCacheNewDir } else { $finalCacheNewDir }

if (Test-Path $cacheNewDir) {
    Remove-Item $cacheNewDir -Recurse -Force
}

Remove-StaleBuildKitNewDirs -ParentDir $bootstrapCacheParentDir -ExcludePath $bootstrapCacheNewDir -BaseDir $dockerDir
Remove-StaleBuildKitNewDirs -ParentDir $finalCacheParentDir -ExcludePath $finalCacheNewDir -BaseDir $dockerDir

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
    '--build-arg', "COMFYUI_RESOLVED_COMMIT=$comfyUIResolvedCommit",
    '--build-arg', "CUDA_PROFILE=$PyTorchCudaProfile",
    '--build-arg', "UBUNTU_VERSION=$UbuntuVersion",
    '--build-arg', "UBUNTU_CACHE_KEY=$ubuntuCacheKey",
    '--build-arg', "APT_CACHE_KEY=$aptCacheKey",
    '--build-arg', "CONDA_CACHE_KEY=$condaCacheKey",
    '--build-arg', "PIP_CACHE_KEY=$pipCacheKey",
    '--build-arg', "PYTORCH_INDEX_URL=$pyTorchIndexUrl",
    '--build-arg', "PIP_INDEX_URL=$PipIndexUrl",
    '--build-arg', "PIP_EXTRA_INDEX_URL=$PipExtraIndexUrl",
    '--build-arg', "PIP_TRUSTED_HOST=$PipTrustedHost",
    '--build-arg', "NODEJS_VERSION=$NodeJsVersion",
    '--build-arg', "TORCH_VERSION=$TorchVersion",
    '--build-arg', "TORCHVISION_VERSION=$torchVisionVersion",
    '--build-arg', "TORCHAUDIO_VERSION=$torchAudioVersion",
    '--build-arg', "XFORMERS_VERSION=$xformersVersion",
    '--build-arg', "CUSTOM_NODES_CACHE_KEY=$customNodesHash",
    '--build-arg', "CUSTOM_NODES_LOCK_B64=$customNodesLockB64"
)

$arguments += @('--cache-to', "type=local,dest=$cacheNewDir,mode=max")

$cacheFromDirs = @()
if (-not (Test-Path $bootstrapCacheDir) -and -not (Test-Path $finalCacheDir) -and (Test-BuildKitLocalCache -Path $legacyCacheDir)) {
    $cacheFromDirs += $legacyCacheDir
}
if ($BuildStage -eq 'bootstrap' -and -not (Test-Path $cacheDir) -and (Test-BuildKitLocalCache -Path $legacyBootstrapCacheDir)) {
    $cacheFromDirs += $legacyBootstrapCacheDir
}
if ($BuildStage -eq 'final' -and -not (Test-Path $cacheDir) -and (Test-BuildKitLocalCache -Path $legacyFinalCacheDir)) {
    $cacheFromDirs += $legacyFinalCacheDir
}
if ($BuildStage -eq 'final') {
    if (Test-Path $finalCacheParentDir) {
        $relatedFinalCaches = Get-ChildItem -LiteralPath $finalCacheParentDir -Directory | Where-Object {
            $_.Name -like "$cacheKeySuffix*" -and
            $_.Name -ne (Split-Path -Leaf $cacheDir) -and
            $_.Name -notlike '*-new' -and
            (Test-BuildKitLocalCache -Path $_.FullName)
        } | Sort-Object Name

        foreach ($relatedFinalCache in $relatedFinalCaches) {
            $cacheFromDirs += $relatedFinalCache.FullName
        }
    }
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
    Show-CacheState -Label 'BeforeBuild' -CacheDir $cacheDir -CacheNewDir $cacheNewDir -BaseDir $dockerDir
    Show-CacheState -Label 'LegacyCache' -CacheDir $legacyCacheDir -CacheNewDir $legacyCacheNewDir -BaseDir $dockerDir
    Show-CacheState -Label 'LegacyBootstrapCache' -CacheDir $legacyBootstrapCacheDir -CacheNewDir $legacyBootstrapCacheNewDir -BaseDir $dockerDir
    Show-CacheState -Label 'LegacyFinalCache' -CacheDir $legacyFinalCacheDir -CacheNewDir $legacyFinalCacheNewDir -BaseDir $dockerDir
    if ($BuildStage -eq 'final') {
        Show-CacheState -Label 'BootstrapCache' -CacheDir $bootstrapCacheDir -CacheNewDir $bootstrapCacheNewDir -BaseDir $dockerDir
        Write-Host "[PluginLock] hash=$customNodesHash"
        Write-Host "[ComfyUI] resolved_commit=$comfyUIResolvedCommit"
    }
    if ($PipIndexUrl) {
        Write-Host "[BuildProxy] PIP_INDEX_URL=$PipIndexUrl"
    }
    if ($PipExtraIndexUrl) {
        Write-Host "[BuildProxy] PIP_EXTRA_INDEX_URL=$PipExtraIndexUrl"
    }
    if ($PyTorchIndexUrlOverride) {
        Write-Host "[BuildProxy] PYTORCH_INDEX_URL_OVERRIDE=$PyTorchIndexUrlOverride"
    }

    $pullImages = @($builderCudaImage, $finalCudaImage, $uvImage) | Select-Object -Unique
    foreach ($image in $pullImages) {
        & docker pull $image
        if ($LASTEXITCODE -ne 0) {
            throw "docker pull 失败：$image，退出码：$LASTEXITCODE"
        }
    }

    & docker @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "docker buildx build 失败，退出码：$LASTEXITCODE"
    }

    if (Test-Path $cacheDir) {
        Remove-Item $cacheDir -Recurse -Force
    }

    if (Test-Path $cacheNewDir) {
        Rename-Item -LiteralPath $cacheNewDir -NewName (Split-Path -Leaf $cacheDir)
    }

    Remove-StaleBuildKitNewDirs -ParentDir $bootstrapCacheParentDir -ExcludePath $bootstrapCacheNewDir -BaseDir $dockerDir
    Remove-StaleBuildKitNewDirs -ParentDir $finalCacheParentDir -ExcludePath $finalCacheNewDir -BaseDir $dockerDir
    if ($BuildStage -eq 'final') {
        Remove-BuildKitSiblingCaches `
            -ParentDir $finalCacheParentDir `
            -CurrentDir $cacheDir `
            -Patterns @("$cacheKeySuffix*") `
            -BaseDir $dockerDir
    }

    Show-CacheState -Label 'AfterBuild' -CacheDir $cacheDir -CacheNewDir $cacheNewDir -BaseDir $dockerDir
    Show-CacheState -Label 'LegacyCache' -CacheDir $legacyCacheDir -CacheNewDir $legacyCacheNewDir -BaseDir $dockerDir
    if ($BuildStage -eq 'final') {
        Show-CacheState -Label 'BootstrapCache' -CacheDir $bootstrapCacheDir -CacheNewDir $bootstrapCacheNewDir -BaseDir $dockerDir
    }

    if ($TestAfterBuild) {
        Invoke-ImageSmokeTest -ImageTag $tag -BuildStage $BuildStage
    }
}
finally {
    if ($LASTEXITCODE -ne 0) {
        Show-CacheState -Label 'OnFailure' -CacheDir $cacheDir -CacheNewDir $cacheNewDir -BaseDir $dockerDir
        if (Test-Path $cacheNewDir) {
            $cacheNewName = Split-Path -Leaf $cacheNewDir
            Write-Host "[OnFailure] docker/$cacheNewName 仍然存在且尚未轮换，可用于查看失败前导出的缓存内容。"
        }
    }
    Pop-Location
}
