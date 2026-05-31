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
        [string]$CacheNewDir
    )

    $cacheExists = Test-Path $CacheDir
    $cacheNewExists = Test-Path $CacheNewDir
    $cacheSize = Format-Bytes (Get-DirectorySizeBytes $CacheDir)
    $cacheNewSize = Format-Bytes (Get-DirectorySizeBytes $CacheNewDir)

    $cacheName = Split-Path -Leaf $CacheDir
    $cacheNewName = Split-Path -Leaf $CacheNewDir

    Write-Host "[$Label] docker/$cacheName exists=$cacheExists size=$cacheSize"
    Write-Host "[$Label] docker/$cacheNewName exists=$cacheNewExists size=$cacheNewSize"
}
