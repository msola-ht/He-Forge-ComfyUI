param(
    [string]$Service = 'comfyui-runtime',
    [int]$WaitTimeoutSeconds = 30,
    [string]$ShellWorkDir = '/root/ComfyUI'
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

function Get-ContainerId {
    param(
        [string]$TargetService
    )

    $result = Invoke-ComposeCapture -Arguments @('ps', '-q', $TargetService)
    if ($result.ExitCode -ne 0) {
        return ''
    }

    $containerId = $result.Output |
        Where-Object { $_ -is [string] } |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -match '^[0-9a-f]{12,64}$' } |
        Select-Object -Last 1

    if (-not $containerId) {
        return ''
    }

    return $containerId
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

if ($runningServices -notcontains $Service) {
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
}

Write-Host "进入 $Service 交互 shell..."
$containerId = Get-ContainerId -TargetService $Service
if (-not $containerId) {
    Write-Host "未能解析 $Service 对应的容器 ID。"
    Write-Host "你可以先执行 .\docker\compose.ps1 ps $Service 检查容器状态。"
    exit 1
}

& docker exec -it $containerId bash -lc "cd '$ShellWorkDir' && exec bash -i"
exit $LASTEXITCODE
