param(
    [string]$Service = 'comfyui-runtime',
    [int]$WaitTimeoutSeconds = 60,
    [string]$ShellWorkDir = ''
)

$ErrorActionPreference = 'Stop'

$dockerDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptDir = Join-Path $dockerDir 'scripts'
$envFile = Join-Path $dockerDir '.env'
$envExampleFile = Join-Path $dockerDir '.env.example'
$composeScript = Join-Path $dockerDir 'compose.ps1'
$composeProjectName = Split-Path -Leaf $dockerDir

. (Join-Path $scriptDir 'env.ps1')

function Resolve-ContainerPath {
    param(
        [string]$BasePath,
        [string]$PathValue
    )

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $BasePath
    }

    $normalizedPath = $PathValue.Replace('\', '/')
    if ($normalizedPath.StartsWith('/')) {
        return $normalizedPath
    }

    return '{0}/{1}' -f $BasePath.TrimEnd('/'), $normalizedPath.TrimStart('/')
}

function ConvertTo-BashSingleQuotedLiteral {
    param(
        [string]$Value
    )

    return $Value.Replace("'", "'""'""'")
}

function Invoke-Compose {
    param(
        [string[]]$Arguments
    )

    & pwsh -NoProfile -ExecutionPolicy Bypass -File $composeScript @Arguments 2>&1 | Out-Host
    return $LASTEXITCODE
}

function Open-OneOffShell {
    param(
        [string]$TargetService,
        [string]$WorkingDirectoryLiteral
    )

    Write-Host "服务 $TargetService 未运行，使用一次性 shell 容器进入..."
    $command = "cd '$WorkingDirectoryLiteral' && exec bash -i"
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $composeScript `
        run `
        --rm `
        --entrypoint bash `
        $TargetService `
        -lc `
        $command
    exit $LASTEXITCODE
}

function Get-ComposeContainerIds {
    param(
        [string]$TargetService
    )

    $output = & docker ps -aq `
        --filter "label=com.docker.compose.project=$composeProjectName" `
        --filter "label=com.docker.compose.service=$TargetService" 2>$null
    if ($LASTEXITCODE -ne 0) {
        return @()
    }

    return @(
        @($output) |
            Where-Object { $_ -is [string] } |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -match '^[0-9a-f]{12,64}$' }
    )
}

function Get-ContainerId {
    param(
        [string]$TargetService
    )

    $containerId = Get-ComposeContainerIds -TargetService $TargetService | Select-Object -Last 1

    if (-not $containerId) {
        return ''
    }

    return $containerId
}

function Test-ContainerRunning {
    param(
        [string]$ContainerId
    )

    if (-not $ContainerId) {
        return $false
    }

    $status = & docker inspect $ContainerId --format '{{.State.Status}}' 2>$null
    return ($LASTEXITCODE -eq 0 -and $status -eq 'running')
}

function Test-ContainerExecReady {
    param(
        [string]$ContainerId
    )

    if (-not $ContainerId) {
        return $false
    }

    & docker exec $ContainerId bash -lc 'exit 0' *> $null
    return ($LASTEXITCODE -eq 0)
}

function Wait-ServiceRunning {
    param(
        [string]$TargetService,
        [int]$TimeoutSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $containerId = Get-ContainerId -TargetService $TargetService
        if ($containerId -and (Test-ContainerRunning -ContainerId $containerId)) {
            return $true
        }

        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)

    return $false
}

function Wait-ContainerExecReady {
    param(
        [string]$TargetService,
        [int]$TimeoutSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $containerId = Get-ContainerId -TargetService $TargetService
        if ($containerId -and (Test-ContainerExecReady -ContainerId $containerId)) {
            return $containerId
        }

        Start-Sleep -Milliseconds 750
    } while ((Get-Date) -lt $deadline)

    return ''
}

Ensure-EnvFile -EnvFile $envFile -EnvExampleFile $envExampleFile
$envValues = Read-EnvFile -Path $envFile
$comfyUiHome = Use-EnvValue -Values $envValues -Name 'COMFYUI_HOME' -CurrentValue '/root/ComfyUI'
$resolvedShellWorkDir = Resolve-ContainerPath -BasePath $comfyUiHome -PathValue $ShellWorkDir
$escapedShellWorkDir = ConvertTo-BashSingleQuotedLiteral -Value $resolvedShellWorkDir

$containerId = Get-ContainerId -TargetService $Service

if (-not ($containerId -and (Test-ContainerRunning -ContainerId $containerId))) {
    Open-OneOffShell -TargetService $Service -WorkingDirectoryLiteral $escapedShellWorkDir
}

Write-Host "进入 $Service 交互 shell..."
$containerId = Wait-ContainerExecReady -TargetService $Service -TimeoutSeconds $WaitTimeoutSeconds
if (-not $containerId) {
    Write-Host "容器已经启动，但在 $WaitTimeoutSeconds 秒内仍未准备好接受 docker exec。"
    Write-Host "你可以先执行 .\docker\compose.ps1 ps $Service 或 .\docker\compose.ps1 logs $Service 检查状态。"
    exit 1
}

& docker exec -it $containerId bash -lc "cd '$escapedShellWorkDir' && exec bash -i"
exit $LASTEXITCODE
