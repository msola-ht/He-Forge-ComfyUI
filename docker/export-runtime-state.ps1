param(
    [ValidateSet('comfyui-runtime', 'comfyui-devel')]
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
        [string]$ErrorFile = '',
        [switch]$ExpectJson,
        [switch]$AllowFailure
    )

    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()

    try {
        & docker @ComposeBaseArgs @CommandArgs 1> $stdoutFile 2> $stderrFile
        $exitCode = $LASTEXITCODE

        $stdoutText = if (Test-Path -LiteralPath $stdoutFile) {
            Get-Content -LiteralPath $stdoutFile -Raw
        } else {
            ''
        }
        $stderrText = if (Test-Path -LiteralPath $stderrFile) {
            Get-Content -LiteralPath $stderrFile -Raw
        } else {
            ''
        }

        if ($ExpectJson) {
            if ([string]::IsNullOrWhiteSpace($stdoutText)) {
                throw "导出命令未生成 JSON 输出：docker $($ComposeBaseArgs -join ' ') $($CommandArgs -join ' ')"
            }

            try {
                $null = $stdoutText | ConvertFrom-Json
            }
            catch {
                throw "导出命令生成了无效 JSON：docker $($ComposeBaseArgs -join ' ') $($CommandArgs -join ' ')"
            }
        }

        if ($ErrorFile) {
            Set-Content -LiteralPath $OutputFile -Value $stdoutText -Encoding utf8
            if ([string]::IsNullOrWhiteSpace($stderrText)) {
                if (Test-Path -LiteralPath $ErrorFile) {
                    Remove-Item -LiteralPath $ErrorFile -Force
                }
            } else {
                Set-Content -LiteralPath $ErrorFile -Value $stderrText -Encoding utf8
            }
        } else {
            $combinedOutput = @()
            if (-not [string]::IsNullOrWhiteSpace($stdoutText)) {
                $combinedOutput += $stdoutText.TrimEnd("`r", "`n")
            }
            if (-not [string]::IsNullOrWhiteSpace($stderrText)) {
                $combinedOutput += $stderrText.TrimEnd("`r", "`n")
            }

            Set-Content -LiteralPath $OutputFile -Value $combinedOutput -Encoding utf8
        }

        if ($exitCode -ne 0 -and -not $AllowFailure) {
            throw "导出命令执行失败：docker $($ComposeBaseArgs -join ' ') $($CommandArgs -join ' ')"
        }
    }
    finally {
        Remove-Item -LiteralPath $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
    }
}

function Get-ServiceExportConfig {
    param(
        [string]$TargetService,
        [hashtable]$EnvValues,
        [string]$DockerDir,
        [string]$RootDir
    )

    switch ($TargetService) {
        'comfyui-runtime' {
            $comfyuiDirValue = Use-EnvValue -Values $EnvValues -Name 'RUNTIME_COMFYUI_DIR' -CurrentValue '../storage/runtime/ComfyUI'
            return @{
                ComfyUIHostDir = Resolve-ExportPath -BasePath $DockerDir -PathValue $comfyuiDirValue
                DefaultExportDir = Join-Path $RootDir 'storage/runtime/exports'
            }
        }
        'comfyui-devel' {
            $comfyuiDirValue = Use-EnvValue -Values $EnvValues -Name 'DEVEL_COMFYUI_DIR' -CurrentValue '../storage/devel/ComfyUI'
            return @{
                ComfyUIHostDir = Resolve-ExportPath -BasePath $DockerDir -PathValue $comfyuiDirValue
                DefaultExportDir = Join-Path $RootDir 'storage/devel/exports'
            }
        }
        default {
            throw "不支持的服务：$TargetService"
        }
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

$serviceExportConfig = Get-ServiceExportConfig -TargetService $Service -EnvValues $envValues -DockerDir $dockerDir -RootDir $root
$comfyuiHostDir = $serviceExportConfig.ComfyUIHostDir
$customNodesDir = Join-Path $comfyuiHostDir 'custom_nodes'

$resolvedOutputBase = if ($OutputDir) {
    Resolve-ExportPath -BasePath $root -PathValue $OutputDir
} else {
    $serviceExportConfig.DefaultExportDir
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
Invoke-ComposeCapture -ComposeBaseArgs $composeBaseArgs -CommandArgs @('exec', '--no-TTY', $Service, 'python', '-m', 'pip', 'list', '--format=json') -OutputFile (Join-Path $exportDir 'pip-list.json') -ErrorFile (Join-Path $exportDir 'pip-list.stderr.txt') -ExpectJson
Invoke-ComposeCapture -ComposeBaseArgs $composeBaseArgs -CommandArgs @('exec', '--no-TTY', $Service, 'python', '-m', 'pip', 'cache', 'dir') -OutputFile (Join-Path $exportDir 'pip-cache-dir.txt')
Invoke-ComposeCapture -ComposeBaseArgs $composeBaseArgs -CommandArgs @('exec', '--no-TTY', $Service, 'python', '-m', 'pip', 'check') -OutputFile (Join-Path $exportDir 'pip-check.txt') -AllowFailure
Invoke-ComposeCapture -ComposeBaseArgs $composeBaseArgs -CommandArgs @(
    'exec',
    '--no-TTY',
    $Service,
    'python',
    '-c',
    'import json,site,sys; print(json.dumps({"executable": sys.executable, "prefix": sys.prefix, "site_packages": site.getsitepackages(), "sys_path": sys.path}, ensure_ascii=True, indent=2))'
) -OutputFile (Join-Path $exportDir 'python-env.json') -ErrorFile (Join-Path $exportDir 'python-env.stderr.txt') -ExpectJson

$customNodeSnapshot = Get-CustomNodeSnapshot -CustomNodesDir $customNodesDir
$customNodeSnapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $exportDir 'custom-nodes.json') -Encoding utf8

$summaryLines = @(
    "# Runtime 导出记录",
    "",
    "- 导出时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "- 服务名: $Service",
    "- 导出目录: $exportDir",
    "- ComfyUI 目录: $comfyuiHostDir",
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
    "- `pip-list.stderr.txt` / `python-env.stderr.txt`: 对应 JSON 导出命令的告警或错误输出，仅在存在时生成",
    "",
    "## 说明",
    "",
    "- 这个导出记录的是当前运行中容器状态，不会自动修改构建脚本。",
    "- 如果后续要固化到镜像构建，通常以 `pip-freeze.txt` 和 `custom-nodes.json` 为主来回填。"
)

Set-Content -LiteralPath (Join-Path $exportDir 'README.md') -Value $summaryLines -Encoding utf8

Write-Host "已导出 runtime 状态到：$exportDir"
