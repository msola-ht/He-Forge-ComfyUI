$ErrorActionPreference = 'Stop'

$dockerDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptDir = Join-Path $dockerDir 'scripts'
$envFile = Join-Path $dockerDir '.env'
$envExampleFile = Join-Path $dockerDir '.env.example'

. (Join-Path $scriptDir 'env.ps1')
. (Join-Path $scriptDir 'versions.ps1')
. (Join-Path $scriptDir 'prompt.ps1')

Ensure-EnvFile -EnvFile $envFile -EnvExampleFile $envExampleFile

$defaults = @{
    ImageName = 'hegenai/comfyui'
    CudaProfile = 'cu128'
    UbuntuVersion = '22'
    MiniforgeInstallerUrl = 'https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh'
    PythonVersion = '3.12'
    ComfyUIRepo = 'https://github.com/Comfy-Org/ComfyUI.git'
    ComfyUIRef = 'master'
    NodeJsVersion = '22'
    TorchVersion = '2.7.0'
}

$versionConfig = Get-VersionConfig -Values (Read-EnvFile -Path $envFile) -Defaults $defaults

Write-Host ""
Write-Host "Docker version configuration"
Write-Host "Press Enter to keep current values."

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
Write-Host "Next build:"
Write-Host "  .\docker\build.ps1"
