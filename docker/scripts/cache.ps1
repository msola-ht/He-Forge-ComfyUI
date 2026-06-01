function Get-DirectorySizeBytes {
    param(
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return 0
    }

    $items = Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue
    if (-not $items) {
        return 0
    }

    return ($items | Measure-Object -Property Length -Sum).Sum
}

function Format-Bytes {
    param(
        [double]$Bytes
    )

    if ($Bytes -ge 1GB) { return '{0:N2} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N2} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N2} KB' -f ($Bytes / 1KB) }
    return '{0:N0} B' -f $Bytes
}

function Show-CacheState {
    param(
        [string]$Label,
        [string]$CacheDir,
        [string]$CacheNewDir,
        [string]$BaseDir = ''
    )

    $cacheExists = Test-Path $CacheDir
    $cacheNewExists = Test-Path $CacheNewDir
    $cacheSize = Format-Bytes (Get-DirectorySizeBytes $CacheDir)
    $cacheNewSize = Format-Bytes (Get-DirectorySizeBytes $CacheNewDir)

    $cacheName = Split-Path -Leaf $CacheDir
    $cacheNewName = Split-Path -Leaf $CacheNewDir
    if ($BaseDir) {
        $cacheName = [System.IO.Path]::GetRelativePath($BaseDir, $CacheDir).Replace('\', '/')
        $cacheNewName = [System.IO.Path]::GetRelativePath($BaseDir, $CacheNewDir).Replace('\', '/')
    }

    Write-Host "[$Label] docker/$cacheName exists=$cacheExists size=$cacheSize"
    Write-Host "[$Label] docker/$cacheNewName exists=$cacheNewExists size=$cacheNewSize"
}

function Test-BuildKitLocalCache {
    param(
        [string]$Path
    )

    return (Test-Path (Join-Path $Path 'index.json')) -and (Test-Path (Join-Path $Path 'blobs'))
}

function Remove-BuildKitCacheDirectory {
    param(
        [string]$Path,
        [string]$Reason = '',
        [string]$BaseDir = ''
    )

    if (-not (Test-Path $Path)) {
        return
    }

    $displayPath = $Path
    if ($BaseDir) {
        $displayPath = [System.IO.Path]::GetRelativePath($BaseDir, $Path).Replace('\', '/')
    }

    $sizeText = Format-Bytes (Get-DirectorySizeBytes $Path)
    if ($Reason) {
        Write-Host "[CacheCleanup] remove docker/$displayPath size=$sizeText reason=$Reason"
    } else {
        Write-Host "[CacheCleanup] remove docker/$displayPath size=$sizeText"
    }

    Remove-Item -LiteralPath $Path -Recurse -Force
}

function Remove-StaleBuildKitNewDirs {
    param(
        [string]$ParentDir,
        [string]$ExcludePath = '',
        [string]$BaseDir = '',
        [timespan]$MinAge = ([TimeSpan]::FromHours(24))
    )

    if (-not (Test-Path $ParentDir)) {
        return
    }

    $excludedFullPath = ''
    if ($ExcludePath) {
        $excludedFullPath = [System.IO.Path]::GetFullPath($ExcludePath)
    }

    $staleBeforeUtc = [DateTime]::UtcNow.Subtract($MinAge)

    $staleDirs = Get-ChildItem -LiteralPath $ParentDir -Directory -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -like '*-new' -and (
            -not $excludedFullPath -or
            [System.IO.Path]::GetFullPath($_.FullName) -cne $excludedFullPath
        ) -and
        $_.LastWriteTimeUtc -le $staleBeforeUtc
    }

    foreach ($staleDir in $staleDirs) {
        Remove-BuildKitCacheDirectory -Path $staleDir.FullName -Reason 'stale-new' -BaseDir $BaseDir
    }
}

function Remove-BuildKitSiblingCaches {
    param(
        [string]$ParentDir,
        [string]$CurrentDir,
        [string[]]$Patterns,
        [string]$BaseDir = ''
    )

    if (-not (Test-Path $ParentDir)) {
        return
    }

    $currentFullPath = [System.IO.Path]::GetFullPath($CurrentDir)
    $siblingDirs = Get-ChildItem -LiteralPath $ParentDir -Directory -ErrorAction SilentlyContinue | Where-Object {
        [System.IO.Path]::GetFullPath($_.FullName) -cne $currentFullPath -and
        $_.Name -notlike '*-new'
    }

    foreach ($siblingDir in $siblingDirs) {
        $matchesPattern = $false
        foreach ($pattern in $Patterns) {
            if ($siblingDir.Name -like $pattern) {
                $matchesPattern = $true
                break
            }
        }

        if (-not $matchesPattern) {
            continue
        }

        Remove-BuildKitCacheDirectory -Path $siblingDir.FullName -Reason 'superseded-family-cache' -BaseDir $BaseDir
    }
}

function Resolve-RemoteGitCommit {
    param(
        [string]$Repo,
        [string]$Ref
    )

    if (-not $Ref) {
        throw "Git 引用不能为空。"
    }

    if ($Ref -match '^[0-9a-fA-F]{40}$') {
        return $Ref.ToLowerInvariant()
    }

    if ($Ref.StartsWith('refs/')) {
        $patterns = @("${Ref}^{}", $Ref)
    } else {
        $patterns = @(
            "refs/tags/$Ref^{}",
            "refs/tags/$Ref",
            "refs/heads/$Ref",
            $Ref
        )
    }

    $output = & git ls-remote $Repo @patterns
    if ($LASTEXITCODE -ne 0) {
        throw "执行 git ls-remote 失败：repo=$Repo ref=$Ref"
    }

    $resolvedByName = @{}
    foreach ($line in $output) {
        if (-not $line) {
            continue
        }

        $parts = ($line -split '\s+', 2)
        if ($parts.Count -lt 2) {
            continue
        }

        $resolvedByName[$parts[1]] = $parts[0].ToLowerInvariant()
    }

    foreach ($pattern in $patterns) {
        if ($resolvedByName.ContainsKey($pattern)) {
            return $resolvedByName[$pattern]
        }
    }

    throw "未找到远端引用：repo=$Repo ref=$Ref"
}
