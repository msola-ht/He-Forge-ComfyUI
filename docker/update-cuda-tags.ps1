param(
    [string]$SourceUrl = 'https://gitlab.com/nvidia/container-images/cuda/-/raw/master/doc/supported-tags.md',
    [string[]]$UbuntuVersion = @('22.04', '24.04')
)

$ErrorActionPreference = 'Stop'

$dockerDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$updater = Join-Path $dockerDir 'scripts/update-cuda-tags.py'
$output = Join-Path $dockerDir 'data/cuda-tags.json'

$arguments = @(
    $updater,
    '--source-url', $SourceUrl,
    '--output', $output,
    '--ubuntu'
)
$arguments += $UbuntuVersion

& python @arguments
if ($LASTEXITCODE -ne 0) {
    throw "更新 CUDA 镜像标签失败，退出码：$LASTEXITCODE"
}
