param(
    [string]$Service = 'comfyui-runtime',
    [string]$OutputDir = ''
)

$ErrorActionPreference = 'Stop'

$dockerDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $dockerDir
$scriptDir = Join-Path $dockerDir 'scripts'
$envFile = Join-Path $dockerDir '.env'
$envExampleFile = Join-Path $dockerDir '.env.example'
$composeFile = Join-Path $dockerDir 'docker-compose.yml'

. (Join-Path $scriptDir 'env.ps1')

function Resolve-ExportPath {
    param(
        [string]$BasePath,
        [string]$PathValue
    )

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $null
    }

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $BasePath $PathValue))
}

function Invoke-ComposeCapture {
    param(
        [string[]]$ComposeBaseArgs,
        [string[]]$CommandArgs,
        [string]$OutputFile,
        [switch]$AllowFailure
    )

    $result = & docker @ComposeBaseArgs @CommandArgs 2>&1
    $exitCode = $LASTEXITCODE

    @($result) | Set-Content -LiteralPath $OutputFile -Encoding utf8

    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "导出命令执行失败：docker $($ComposeBaseArgs -join ' ') $($CommandArgs -join ' ')"
    }
}

function Get-CustomNodeSnapshot {
    param(
        [string]$CustomNodesDir
    )

    $items = @()
    if (-not (Test-Path -LiteralPath $CustomNodesDir)) {
        return $items
    }

    foreach ($dir in Get-ChildItem -LiteralPath $CustomNodesDir -Directory | Sort-Object Name) {
        $requirementsFiles = @(
            Get-ChildItem -LiteralPath $dir.FullName -File |
                Where-Object { $_.Name -like 'requirements*.txt' } |
                Sort-Object Name |
                ForEach-Object { $_.Name }
        )

        $snapshot = [ordered]@{
            name = $dir.Name
            path = $dir.FullName
            requirements_files = $requirementsFiles
        }

        $isGitRepo = $false
        $remoteUrl = ''
        $commit = ''
        $branch = ''
        $statusLines = @()

        try {
            $null = & git -C $dir.FullName rev-parse --is-inside-work-tree 2>$null
            if ($LASTEXITCODE -eq 0) {
                $isGitRepo = $true
                $remoteUrl = ((& git -C $dir.FullName remote get-url origin 2>$null) | Select-Object -First 1)
                $commit = ((& git -C $dir.FullName rev-parse HEAD 2>$null) | Select-Object -First 1)
                $branch = ((& git -C $dir.FullName branch --show-current 2>$null) | Select-Object -First 1)
                $statusLines = @(& git -C $dir.FullName status --short 2>$null)
            }
        } catch {
            $isGitRepo = $false
        }

        if ($isGitRepo) {
            $snapshot.git = [ordered]@{
                remote = $remoteUrl
                commit = $commit
                branch = $branch
                dirty = [bool]($statusLines.Count)
                status = $statusLines
            }
        }

        $items += [pscustomobject]$snapshot
    }

    return $items
}

Ensure-EnvFile -EnvFile $envFile -EnvExampleFile $envExampleFile
$envValues = Read-EnvFile -Path $envFile

$runtimeComfyuiDirValue = Use-EnvValue -Values $envValues -Name 'RUNTIME_COMFYUI_DIR' -CurrentValue '../storage/runtime/ComfyUI'
$runtimeComfyuiDir = Resolve-ExportPath -BasePath $dockerDir -PathValue $runtimeComfyuiDirValue
$customNodesDir = Join-Path $runtimeComfyuiDir 'custom_nodes'

$resolvedOutputBase = if ($OutputDir) {
    Resolve-ExportPath -BasePath $root -PathValue $OutputDir
} else {
    Join-Path $root 'storage/runtime/exports'
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$exportDir = Join-Path $resolvedOutputBase $timestamp
New-Item -ItemType Directory -Force -Path $exportDir | Out-Null

$composeBaseArgs = @(
    'compose',
    '--env-file', $envFile,
    '-f', $composeFile
)

$runningServices = @(& docker @composeBaseArgs ps --status running --services 2>$null)
if ($LASTEXITCODE -ne 0 -or $runningServices -notcontains $Service) {
    throw "服务 $Service 当前未运行。请先执行：.\docker\compose.ps1 up ""--detach"" $Service"
}

Invoke-ComposeCapture -ComposeBaseArgs $composeBaseArgs -CommandArgs @('exec', '--no-TTY', $Service, 'python', '--version') -OutputFile (Join-Path $exportDir 'python-version.txt')
Invoke-ComposeCapture -ComposeBaseArgs $composeBaseArgs -CommandArgs @('exec', '--no-TTY', $Service, 'python', '-m', 'pip', 'freeze') -OutputFile (Join-Path $exportDir 'pip-freeze.txt')
Invoke-ComposeCapture -ComposeBaseArgs $composeBaseArgs -CommandArgs @('exec', '--no-TTY', $Service, 'python', '-m', 'pip', 'list', '--format=json') -OutputFile (Join-Path $exportDir 'pip-list.json')
Invoke-ComposeCapture -ComposeBaseArgs $composeBaseArgs -CommandArgs @('exec', '--no-TTY', $Service, 'python', '-m', 'pip', 'cache', 'dir') -OutputFile (Join-Path $exportDir 'pip-cache-dir.txt')
Invoke-ComposeCapture -ComposeBaseArgs $composeBaseArgs -CommandArgs @('exec', '--no-TTY', $Service, 'python', '-m', 'pip', 'check') -OutputFile (Join-Path $exportDir 'pip-check.txt') -AllowFailure
Invoke-ComposeCapture -ComposeBaseArgs $composeBaseArgs -CommandArgs @(
    'exec',
    '--no-TTY',
    $Service,
    'python',
    '-c',
    'import json,site,sys; print(json.dumps({"executable": sys.executable, "prefix": sys.prefix, "site_packages": site.getsitepackages(), "sys_path": sys.path}, ensure_ascii=True, indent=2))'
) -OutputFile (Join-Path $exportDir 'python-env.json')

$customNodeSnapshot = Get-CustomNodeSnapshot -CustomNodesDir $customNodesDir
$customNodeSnapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $exportDir 'custom-nodes.json') -Encoding utf8

$summaryLines = @(
    "# Runtime 导出记录",
    "",
    "- 导出时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "- 服务名: $Service",
    "- 导出目录: $exportDir",
    "- Runtime ComfyUI 目录: $runtimeComfyuiDir",
    "- Custom Nodes 目录: $customNodesDir",
    "",
    "## 文件说明",
    "",
    "- `python-version.txt`: 当前容器 Python 版本",
    "- `python-env.json`: 当前 Python 可执行文件、prefix、site-packages、sys.path",
    "- `pip-freeze.txt`: 当前已安装包锁定快照",
    "- `pip-list.json`: 当前已安装包 JSON 清单",
    "- `pip-check.txt`: 当前依赖冲突检查结果",
    "- `pip-cache-dir.txt`: 容器内 pip 缓存目录",
    "- `custom-nodes.json`: 当前 custom nodes 目录及 Git 快照",
    "",
    "## 说明",
    "",
    "- 这个导出记录的是当前运行中容器状态，不会自动修改构建脚本。",
    "- 如果后续要固化到镜像构建，通常以 `pip-freeze.txt` 和 `custom-nodes.json` 为主来回填。"
)

Set-Content -LiteralPath (Join-Path $exportDir 'README.md') -Value $summaryLines -Encoding utf8

Write-Host "已导出 runtime 状态到：$exportDir"
