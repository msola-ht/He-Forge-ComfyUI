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

. (Join-Path $scriptDir 'env.ps1')
. (Join-Path $scriptDir 'versions.ps1')

Ensure-EnvFile -EnvFile $envFile -EnvExampleFile $envExampleFile
$envValues = Read-EnvFile -Path $envFile

if ($ComposeArgs -and $ComposeArgs[0] -eq 'build') {
    throw "Build entry is docker/build.ps1. Use: .\docker\build.ps1 -FromEnv"
}

$cudaProfile = Use-EnvValue -Values $envValues -Name 'CUDA_PROFILE' -CurrentValue 'cu128'
$ubuntuVersion = Use-EnvValue -Values $envValues -Name 'UBUNTU_VERSION' -CurrentValue '22'
$cudaImageSet = Resolve-CudaImageSet -CudaProfile $cudaProfile -UbuntuVersion $ubuntuVersion

$env:CUDA_VERSION = $cudaImageSet.CudaVersion
$env:BUILDER_CUDA_IMAGE = $cudaImageSet.BuilderCudaImage
$env:RUNTIME_CUDA_IMAGE = $cudaImageSet.RuntimeCudaImage
$env:DEVEL_CUDA_IMAGE = $cudaImageSet.DevelCudaImage

Write-Host "[Compose] CUDA_PROFILE=$cudaProfile"
Write-Host "[Compose] UBUNTU_VERSION=$ubuntuVersion"
Write-Host "[Compose] BUILDER_CUDA_IMAGE=$env:BUILDER_CUDA_IMAGE"
Write-Host "[Compose] RUNTIME_CUDA_IMAGE=$env:RUNTIME_CUDA_IMAGE"
Write-Host "[Compose] DEVEL_CUDA_IMAGE=$env:DEVEL_CUDA_IMAGE"

$arguments = @(
    'compose',
    '--env-file', $envFile,
    '-f', $composeFile
)

if ($ComposeArgs) {
    $arguments += $ComposeArgs
}

& docker @arguments
exit $LASTEXITCODE
