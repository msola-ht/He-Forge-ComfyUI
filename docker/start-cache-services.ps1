param(
    [switch]$SkipEnvUpdate,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ComposeArgs
)

$ErrorActionPreference = 'Stop'

$dockerDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptDir = Join-Path $dockerDir 'scripts'
$envFile = Join-Path $dockerDir '.env'
$envExampleFile = Join-Path $dockerDir '.env.example'
$composeScript = Join-Path $dockerDir 'compose.ps1'

. (Join-Path $scriptDir 'env.ps1')

function Test-TcpEndpoint {
    param(
        [string]$HostName,
        [int]$Port,
        [int]$TimeoutMilliseconds = 1000
    )

    $client = [System.Net.Sockets.TcpClient]::new()
    $asyncResult = $null

    try {
        $asyncResult = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $asyncResult.AsyncWaitHandle.WaitOne($TimeoutMilliseconds, $false)) {
            return $false
        }

        $client.EndConnect($asyncResult)
        return $true
    }
    catch {
        return $false
    }
    finally {
        if ($asyncResult) {
            $asyncResult.AsyncWaitHandle.Dispose()
        }

        $client.Dispose()
    }
}

function Wait-TcpEndpoint {
    param(
        [string]$Label,
        [string]$HostName,
        [int]$Port,
        [int]$TimeoutSeconds = 180,
        [int]$PollIntervalSeconds = 2
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-TcpEndpoint -HostName $HostName -Port $Port) {
            Write-Host "[CacheReady] $Label tcp://$HostName`:$Port"
            return
        }

        Start-Sleep -Seconds $PollIntervalSeconds
    }

    throw "缓存服务 $Label 未在 ${TimeoutSeconds}s 内就绪：tcp://$HostName`:$Port"
}

Ensure-EnvFile -EnvFile $envFile -EnvExampleFile $envExampleFile
$envValues = Read-EnvFile -Path $envFile

$devpiPort = Use-EnvValue -Values $envValues -Name 'DEVPI_PORT' -CurrentValue '3141'
$pyTorchProxyPort = Use-EnvValue -Values $envValues -Name 'PYTORCH_PROXY_PORT' -CurrentValue '3143'
$cacheHost = 'host.docker.internal'

$pipIndexUrl = "http://${cacheHost}:$devpiPort/root/pypi/+simple/"
$pipTrustedHost = $cacheHost
$pyTorchIndexUrlOverride = "http://${cacheHost}:$pyTorchProxyPort/whl/{profile}"

$arguments = @('--profile', 'cache', 'up', '--detach')
if ($ComposeArgs) {
    $arguments += $ComposeArgs
}
$arguments += @('devpi', 'pytorch-proxy')

& $composeScript @arguments
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$localhost = '127.0.0.1'
Wait-TcpEndpoint -Label 'devpi' -HostName $localhost -Port ([int]$devpiPort)
Wait-TcpEndpoint -Label 'pytorch-proxy' -HostName $localhost -Port ([int]$pyTorchProxyPort)

if (-not $SkipEnvUpdate) {
    Remove-EnvValue -Path $envFile -Name 'APT_HTTP_PROXY'
    Remove-EnvValue -Path $envFile -Name 'APT_HTTPS_PROXY'
    Remove-EnvValue -Path $envFile -Name 'APT_CACHE_PORT'
    Remove-EnvValue -Path $envFile -Name 'APT_CACHE_DATA_DIR'
    Set-EnvValue -Path $envFile -Name 'PIP_INDEX_URL' -Value $pipIndexUrl
    Set-EnvValue -Path $envFile -Name 'PIP_TRUSTED_HOST' -Value $pipTrustedHost
    Set-EnvValue -Path $envFile -Name 'PYTORCH_INDEX_URL_OVERRIDE' -Value $pyTorchIndexUrlOverride

    Write-Host "[CacheEnv] Updated docker/.env"
    Write-Host "[CacheEnv] PIP_INDEX_URL=$pipIndexUrl"
    Write-Host "[CacheEnv] PIP_TRUSTED_HOST=$pipTrustedHost"
    Write-Host "[CacheEnv] PYTORCH_INDEX_URL_OVERRIDE=$pyTorchIndexUrlOverride"
}

exit 0
