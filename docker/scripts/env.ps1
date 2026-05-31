function Read-EnvFile {
    param(
        [string]$Path
    )

    $values = @{}

    if (-not (Test-Path $Path)) {
        return $values
    }

    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()

        if (-not $trimmed -or $trimmed.StartsWith('#')) {
            continue
        }

        $parts = $trimmed.Split('=', 2)
        if ($parts.Count -ne 2) {
            continue
        }

        $values[$parts[0].Trim()] = $parts[1].Trim()
    }

    return $values
}

function Use-EnvValue {
    param(
        [hashtable]$Values,
        [string]$Name,
        [string]$CurrentValue
    )

    if ($Values.ContainsKey($Name) -and $Values[$Name]) {
        return $Values[$Name]
    }

    return $CurrentValue
}

function Ensure-EnvFile {
    param(
        [string]$EnvFile,
        [string]$EnvExampleFile
    )

    if (-not (Test-Path $EnvFile) -and (Test-Path $EnvExampleFile)) {
        Copy-Item -LiteralPath $EnvExampleFile -Destination $EnvFile
    }
}

function Set-EnvValue {
    param(
        [string]$Path,
        [string]$Name,
        [string]$Value
    )

    $lines = @()
    if (Test-Path $Path) {
        $lines = @(Get-Content -LiteralPath $Path)
    }

    $updated = $false
    $newLines = foreach ($line in $lines) {
        if ($line -match "^\s*$([regex]::Escape($Name))=") {
            $updated = $true
            "$Name=$Value"
        } else {
            $line
        }
    }

    if (-not $updated) {
        $newLines += "$Name=$Value"
    }

    Set-Content -LiteralPath $Path -Value $newLines -Encoding utf8
}

function Save-VersionConfig {
    param(
        [string]$Path,
        [string]$ImageName,
        [string]$CudaImageVersion,
        [string]$PyTorchCudaProfile,
        [string]$UbuntuVersion,
        [string]$MiniforgeInstallerUrl,
        [string]$PythonVersion,
        [string]$ComfyUIRepo,
        [string]$ComfyUIRef,
        [string]$NodeJsVersion,
        [string]$TorchVersion
    )

    Set-EnvValue -Path $Path -Name 'IMAGE_NAME' -Value $ImageName
    Set-EnvValue -Path $Path -Name 'CUDA_IMAGE_VERSION' -Value $CudaImageVersion
    Set-EnvValue -Path $Path -Name 'PYTORCH_CUDA_PROFILE' -Value $PyTorchCudaProfile
    Set-EnvValue -Path $Path -Name 'UBUNTU_VERSION' -Value $UbuntuVersion
    Set-EnvValue -Path $Path -Name 'MINIFORGE_INSTALLER_URL' -Value $MiniforgeInstallerUrl
    Set-EnvValue -Path $Path -Name 'PYTHON_VERSION' -Value $PythonVersion
    Set-EnvValue -Path $Path -Name 'COMFYUI_REPO' -Value $ComfyUIRepo
    Set-EnvValue -Path $Path -Name 'COMFYUI_REF' -Value $ComfyUIRef
    Set-EnvValue -Path $Path -Name 'NODEJS_VERSION' -Value $NodeJsVersion
    Set-EnvValue -Path $Path -Name 'TORCH_VERSION' -Value $TorchVersion
}

function Get-VersionConfig {
    param(
        [hashtable]$Values,
        [hashtable]$Defaults
    )

    return @{
        ImageName = Use-EnvValue -Values $Values -Name 'IMAGE_NAME' -CurrentValue $Defaults.ImageName
        CudaImageVersion = Use-EnvValue -Values $Values -Name 'CUDA_IMAGE_VERSION' -CurrentValue $Defaults.CudaImageVersion
        PyTorchCudaProfile = Use-EnvValue -Values $Values -Name 'PYTORCH_CUDA_PROFILE' -CurrentValue (Use-EnvValue -Values $Values -Name 'CUDA_PROFILE' -CurrentValue $Defaults.PyTorchCudaProfile)
        UbuntuVersion = Use-EnvValue -Values $Values -Name 'UBUNTU_VERSION' -CurrentValue $Defaults.UbuntuVersion
        MiniforgeInstallerUrl = Use-EnvValue -Values $Values -Name 'MINIFORGE_INSTALLER_URL' -CurrentValue $Defaults.MiniforgeInstallerUrl
        PythonVersion = Use-EnvValue -Values $Values -Name 'PYTHON_VERSION' -CurrentValue $Defaults.PythonVersion
        ComfyUIRepo = Use-EnvValue -Values $Values -Name 'COMFYUI_REPO' -CurrentValue $Defaults.ComfyUIRepo
        ComfyUIRef = Use-EnvValue -Values $Values -Name 'COMFYUI_REF' -CurrentValue $Defaults.ComfyUIRef
        NodeJsVersion = Use-EnvValue -Values $Values -Name 'NODEJS_VERSION' -CurrentValue $Defaults.NodeJsVersion
        TorchVersion = Use-EnvValue -Values $Values -Name 'TORCH_VERSION' -CurrentValue $Defaults.TorchVersion
    }
}

function Merge-BoundVersionConfig {
    param(
        [hashtable]$Config,
        [hashtable]$BoundParameters
    )

    $parameterMap = @{
        ImageName = 'ImageName'
        CudaImageVersion = 'CudaImageVersion'
        PyTorchCudaProfile = 'PyTorchCudaProfile'
        UbuntuVersion = 'UbuntuVersion'
        MiniforgeInstallerUrl = 'MiniforgeInstallerUrl'
        PythonVersion = 'PythonVersion'
        ComfyUIRepo = 'ComfyUIRepo'
        ComfyUIRef = 'ComfyUIRef'
        NodeJsVersion = 'NodeJsVersion'
        TorchVersion = 'TorchVersion'
    }

    foreach ($parameterName in $parameterMap.Keys) {
        if ($BoundParameters.ContainsKey($parameterName)) {
            $Config[$parameterMap[$parameterName]] = $BoundParameters[$parameterName]
        }
    }

    return $Config
}
