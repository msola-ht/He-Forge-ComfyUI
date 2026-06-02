param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ComposeArgs
)

$ErrorActionPreference = 'Stop'

$dockerDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptDir = Join-Path $dockerDir 'scripts'
$envFile = Join-Path $dockerDir '.env'
$envExampleFile = Join-Path $dockerDir '.env.example'
$composeFile = Join-Path $dockerDir 'docker-compose.yml'

function Test-DockerGpuRuntimeSupport {
    $runtimeJson = & docker info --format '{{json .Runtimes}}' 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $runtimeJson) {
        return $false
    }

    return $runtimeJson -match '"nvidia"'
}

function Resolve-GpuEnabled {
    param(
        [string]$Mode
    )

    $normalizedMode = if ([string]::IsNullOrWhiteSpace($Mode)) { 'auto' } else { $Mode.Trim().ToLowerInvariant() }
    switch ($normalizedMode) {
        'auto' { return (Test-DockerGpuRuntimeSupport) }
        'on' { return $true }
        'true' { return $true }
        '1' { return $true }
        'yes' { return $true }
        'off' { return $false }
        'false' { return $false }
        '0' { return $false }
        'no' { return $false }
        default { throw "不支持的 COMFYUI_GPU_MODE：$Mode。可选值：auto、on、off。" }
    }
}

. (Join-Path $scriptDir 'env.ps1')
. (Join-Path $scriptDir 'versions.ps1')

Ensure-EnvFile -EnvFile $envFile -EnvExampleFile $envExampleFile
$envValues = Read-EnvFile -Path $envFile

if ($ComposeArgs -and $ComposeArgs[0] -eq 'build') {
    throw "构建入口已统一为 docker/build.ps1。请使用：.\docker\build.ps1 -FromEnv"
}

$cudaImageVersion = Use-EnvValue -Values $envValues -Name 'CUDA_IMAGE_VERSION' -CurrentValue '12.8.2'
$pyTorchCudaProfile = Use-EnvValue -Values $envValues -Name 'PYTORCH_CUDA_PROFILE' -CurrentValue (Use-EnvValue -Values $envValues -Name 'CUDA_PROFILE' -CurrentValue 'cu128')
$pyTorchIndexUrlOverride = Use-EnvValue -Values $envValues -Name 'PYTORCH_INDEX_URL_OVERRIDE' -CurrentValue ''
$comfyUiGpuMode = Use-EnvValue -Values $envValues -Name 'COMFYUI_GPU_MODE' -CurrentValue 'auto'
$ubuntuVersion = Use-EnvValue -Values $envValues -Name 'UBUNTU_VERSION' -CurrentValue '22.04'
$torchVersion = Use-EnvValue -Values $envValues -Name 'TORCH_VERSION' -CurrentValue '2.7.0'
$pythonVersion = Use-EnvValue -Values $envValues -Name 'PYTHON_VERSION' -CurrentValue '3.12'
$gpuEnabled = Resolve-GpuEnabled -Mode $comfyUiGpuMode
$cudaImageSet = Resolve-CudaImageSet -CudaImageVersion $cudaImageVersion -UbuntuVersion $ubuntuVersion
Assert-PyTorchCudaProfile -PyTorchCudaProfile $pyTorchCudaProfile -TorchVersion $torchVersion
$pyTorchIndexUrl = if ($pyTorchIndexUrlOverride) {
    $pyTorchIndexUrlOverride.Replace('{profile}', $pyTorchCudaProfile).Replace('{cuda_profile}', $pyTorchCudaProfile)
} else {
    Resolve-PyTorchIndexUrl -PyTorchCudaProfile $pyTorchCudaProfile -TorchVersion $torchVersion
}
$pyTorchPackageVersions = Resolve-PyTorchPackageVersions -TorchVersion $torchVersion
$aptCacheKey = "cuda$cudaImageVersion-$($cudaImageSet.UbuntuCacheKey)"
$condaCacheKey = "conda-py$($pythonVersion.Replace('.', ''))"
$pipCacheKey = "pip-py$($pythonVersion.Replace('.', ''))-torch$torchVersion-$pyTorchCudaProfile"
$runtimeImageTag = Resolve-ImageTagSuffix -CudaImageVersion $cudaImageVersion -PyTorchCudaProfile $pyTorchCudaProfile -UbuntuVersion $ubuntuVersion -TorchVersion $torchVersion -PythonVersion $pythonVersion -Variant runtime
$develImageTag = Resolve-ImageTagSuffix -CudaImageVersion $cudaImageVersion -PyTorchCudaProfile $pyTorchCudaProfile -UbuntuVersion $ubuntuVersion -TorchVersion $torchVersion -PythonVersion $pythonVersion -Variant devel

$env:CUDA_VERSION = $cudaImageSet.CudaVersion
$env:UBUNTU_CACHE_KEY = $cudaImageSet.UbuntuCacheKey
$env:APT_CACHE_KEY = $aptCacheKey
$env:CONDA_CACHE_KEY = $condaCacheKey
$env:PIP_CACHE_KEY = $pipCacheKey
$env:PYTORCH_INDEX_URL = $pyTorchIndexUrl
$env:TORCHVISION_VERSION = $pyTorchPackageVersions.TorchVisionVersion
$env:TORCHAUDIO_VERSION = $pyTorchPackageVersions.TorchAudioVersion
$env:XFORMERS_VERSION = Resolve-XformersVersion -TorchVersion $torchVersion -PyTorchCudaProfile $pyTorchCudaProfile
$env:BUILDER_CUDA_IMAGE = $cudaImageSet.BuilderCudaImage
$env:RUNTIME_CUDA_IMAGE = $cudaImageSet.RuntimeCudaImage
$env:DEVEL_CUDA_IMAGE = $cudaImageSet.DevelCudaImage
$env:RUNTIME_IMAGE_TAG = $runtimeImageTag
$env:DEVEL_IMAGE_TAG = $develImageTag

Write-Host "[Compose] CUDA_IMAGE_VERSION=$cudaImageVersion"
Write-Host "[Compose] PYTORCH_CUDA_PROFILE=$pyTorchCudaProfile"
Write-Host "[Compose] UBUNTU_VERSION=$ubuntuVersion"
Write-Host "[Compose] TORCH_VERSION=$torchVersion"
Write-Host "[Compose] COMFYUI_GPU_MODE=$comfyUiGpuMode"
Write-Host "[Compose] GPU_ENABLED=$gpuEnabled"
Write-Host "[Compose] UBUNTU_CACHE_KEY=$env:UBUNTU_CACHE_KEY"
Write-Host "[Compose] APT_CACHE_KEY=$env:APT_CACHE_KEY"
Write-Host "[Compose] PIP_CACHE_KEY=$env:PIP_CACHE_KEY"
Write-Host "[Compose] PYTORCH_INDEX_URL=$env:PYTORCH_INDEX_URL"
Write-Host "[Compose] XFORMERS_VERSION=$env:XFORMERS_VERSION"
Write-Host "[Compose] RUNTIME_IMAGE_TAG=$env:RUNTIME_IMAGE_TAG"
Write-Host "[Compose] DEVEL_IMAGE_TAG=$env:DEVEL_IMAGE_TAG"
Write-Host "[Compose] BUILDER_CUDA_IMAGE=$env:BUILDER_CUDA_IMAGE"
Write-Host "[Compose] RUNTIME_CUDA_IMAGE=$env:RUNTIME_CUDA_IMAGE"
Write-Host "[Compose] DEVEL_CUDA_IMAGE=$env:DEVEL_CUDA_IMAGE"

$arguments = @(
    'compose',
    '--env-file', $envFile,
    '-f', $composeFile
)

if ($gpuEnabled) {
    $gpuOverrideFile = Join-Path ([System.IO.Path]::GetTempPath()) ("comfyui-compose-gpu-{0}.yml" -f [System.Guid]::NewGuid().ToString('N'))
    $gpuOverrideContent = @"
services:
  comfyui-runtime:
    gpus: all
  comfyui-devel:
    gpus: all
"@
    Set-Content -LiteralPath $gpuOverrideFile -Value $gpuOverrideContent -Encoding utf8
}

try {
    if ($gpuEnabled) {
        $arguments += @('-f', $gpuOverrideFile)
    }
    if ($ComposeArgs) {
        $arguments += $ComposeArgs
    }

    & docker @arguments
    exit $LASTEXITCODE
}
finally {
    if ($gpuOverrideFile -and (Test-Path $gpuOverrideFile)) {
        Remove-Item -LiteralPath $gpuOverrideFile -Force
    }
}
