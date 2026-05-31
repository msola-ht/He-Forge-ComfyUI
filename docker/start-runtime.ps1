param(
    [string]$Service = 'comfyui-runtime',
    [int]$WaitTimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'

$dockerDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$composeScript = Join-Path $dockerDir 'compose.ps1'

function Invoke-Compose {
    param(
        [string[]]$Arguments
    )

    & pwsh -NoProfile -ExecutionPolicy Bypass -File $composeScript @Arguments
    return $LASTEXITCODE
}

function Invoke-ComposeCapture {
    param(
        [string[]]$Arguments
    )

    $output = & pwsh -NoProfile -ExecutionPolicy Bypass -File $composeScript @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    return [pscustomobject]@{
        Output = @($output)
        ExitCode = $exitCode
    }
}

function Get-RunningServices {
    $result = Invoke-ComposeCapture -Arguments @('ps', '--status', 'running', '--services')
    if ($result.ExitCode -ne 0) {
        return @()
    }

    return @(
        $result.Output |
            Where-Object { $_ -is [string] } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Where-Object { $_ -notmatch '^\[Compose\]' }
    )
}

function Wait-ServiceRunning {
    param(
        [string]$TargetService,
        [int]$TimeoutSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $runningServices = Get-RunningServices
        if ($runningServices -contains $TargetService) {
            return $true
        }

        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)

    return $false
}

$runningServices = Get-RunningServices
if ($runningServices -contains $Service) {
    Write-Host "服务 $Service 已在运行。"
    exit 0
}

Write-Host "服务 $Service 未运行，正在后台启动..."
$startExitCode = Invoke-Compose -Arguments @('up', '--detach', $Service)
if ($startExitCode -ne 0) {
    exit $startExitCode
}

Write-Host "等待 $Service 就绪..."
if (-not (Wait-ServiceRunning -TargetService $Service -TimeoutSeconds $WaitTimeoutSeconds)) {
    Write-Host "服务 $Service 已发起启动，但在 $WaitTimeoutSeconds 秒内未进入 running 状态。"
    Write-Host "你可以先执行 .\docker\compose.ps1 logs $Service 检查启动日志。"
    exit 1
}

Write-Host "服务 $Service 已启动。"
exit 0
