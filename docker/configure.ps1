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
    CudaImageVersion = '12.8.2'
    PyTorchCudaProfile = 'cu128'
    UbuntuVersion = '22.04'
    MiniforgeInstallerUrl = 'https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh'
    PythonVersion = '3.12'
    ComfyUIRepo = 'https://github.com/Comfy-Org/ComfyUI.git'
    ComfyUIRef = 'master'
    NodeJsVersion = '22'
    TorchVersion = '2.7.0'
    AptHttpProxy = ''
    AptHttpsProxy = ''
    PipIndexUrl = ''
    PipExtraIndexUrl = ''
    PipTrustedHost = ''
    PyTorchIndexUrlOverride = ''
}

$versionConfig = Get-VersionConfig -Values (Read-EnvFile -Path $envFile) -Defaults $defaults

Write-Host ""
Write-Host "Docker 版本配置"
Write-Host "直接回车表示保留当前值。"

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
    -AptHttpProxy $versionConfig.AptHttpProxy `
    -AptHttpsProxy $versionConfig.AptHttpsProxy `
    -PipIndexUrl $versionConfig.PipIndexUrl `
    -PipExtraIndexUrl $versionConfig.PipExtraIndexUrl `
    -PipTrustedHost $versionConfig.PipTrustedHost `
    -PyTorchIndexUrlOverride $versionConfig.PyTorchIndexUrlOverride

Write-Host ""
Write-Host "已保存版本配置到 docker/.env"
Write-Host "下一步构建："
Write-Host "  .\docker\build.ps1"
