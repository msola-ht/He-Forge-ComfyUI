param(
    [string]$LocallyUrl = 'https://pytorch.org/get-started/locally/',
    [string]$PreviousUrl = 'https://pytorch.org/get-started/previous-versions/',
    [string]$XformersUrl = 'https://pypi.org/pypi/xformers/json',
    [string]$MinVersion = '2.6.0',
    [switch]$VerifyWheels
)

$ErrorActionPreference = 'Stop'

$dockerDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$updater = Join-Path $dockerDir 'scripts/update-pytorch-tags.py'
$output = Join-Path $dockerDir 'data/pytorch-tags.json'

$arguments = @(
    $updater,
    '--locally-url', $LocallyUrl,
    '--previous-url', $PreviousUrl,
    '--xformers-url', $XformersUrl,
    '--output', $output,
    '--min-version', $MinVersion
)

if ($VerifyWheels) {
    $arguments += '--verify-wheels'
}

& python @arguments
if ($LASTEXITCODE -ne 0) {
    throw "更新 PyTorch 版本矩阵失败，退出码：$LASTEXITCODE"
}
