function Select-Option {
    param(
        [string]$Label,
        [string]$CurrentValue,
        [string[]]$Options
    )

    Write-Host ""
    Write-Host "$Label"
    for ($index = 0; $index -lt $Options.Count; $index++) {
        $marker = if ($Options[$index] -eq $CurrentValue) { '*' } else { ' ' }
        Write-Host ("  {0}. [{1}] {2}" -f ($index + 1), $marker, $Options[$index])
    }

    $answer = Read-Host "Select 1-$($Options.Count), or press Enter to keep [$CurrentValue]"
    if (-not $answer) {
        return $CurrentValue
    }

    $selectedIndex = 0
    if (-not [int]::TryParse($answer, [ref]$selectedIndex)) {
        throw "Invalid selection for ${Label}: $answer"
    }

    if ($selectedIndex -lt 1 -or $selectedIndex -gt $Options.Count) {
        throw "Invalid selection for ${Label}: $answer"
    }

    return $Options[$selectedIndex - 1]
}

function Select-TextValue {
    param(
        [string]$Label,
        [string]$CurrentValue
    )

    Write-Host ""
    $answer = Read-Host "$Label [$CurrentValue]"
    if (-not $answer) {
        return $CurrentValue
    }

    return $answer
}

function Select-YesNo {
    param(
        [string]$Label,
        [bool]$DefaultValue
    )

    $defaultText = if ($DefaultValue) { 'Y/n' } else { 'y/N' }
    $answer = Read-Host "$Label [$defaultText]"

    if (-not $answer) {
        return $DefaultValue
    }

    switch ($answer.ToLowerInvariant()) {
        'y' { return $true }
        'yes' { return $true }
        'n' { return $false }
        'no' { return $false }
        default { throw "Invalid yes/no answer: $answer" }
    }
}

function Select-BuildStage {
    param(
        [string]$CurrentValue
    )

    if (-not $CurrentValue) {
        $CurrentValue = 'final'
    }

    return Select-Option -Label 'Build stage' -CurrentValue $CurrentValue -Options @('bootstrap', 'final')
}

function Show-VersionConfig {
    param(
        [hashtable]$Config
    )

    Write-Host ""
    Write-Host "Current version configuration"
    Write-Host "  IMAGE_NAME=$($Config.ImageName)"
    Write-Host "  CUDA_PROFILE=$($Config.CudaProfile)"
    Write-Host "  UBUNTU_VERSION=$($Config.UbuntuVersion)"
    Write-Host "  TORCH_VERSION=$($Config.TorchVersion)"
    Write-Host "  NODEJS_VERSION=$($Config.NodeJsVersion)"
    Write-Host "  PYTHON_VERSION=$($Config.PythonVersion)"
    Write-Host "  COMFYUI_REF=$($Config.ComfyUIRef)"
}

function Edit-VersionConfig {
    param(
        [hashtable]$Config
    )

    $Config.CudaProfile = Select-Option -Label 'CUDA profile' -CurrentValue $Config.CudaProfile -Options (Get-CudaProfileOptions)
    $Config.UbuntuVersion = Select-Option -Label 'Ubuntu version' -CurrentValue $Config.UbuntuVersion -Options (Get-UbuntuVersionOptions)
    $Config.TorchVersion = Select-Option -Label 'Torch version' -CurrentValue $Config.TorchVersion -Options (Get-TorchVersionOptions)
    $Config.NodeJsVersion = Select-Option -Label 'Node.js version' -CurrentValue $Config.NodeJsVersion -Options (Get-NodeJsVersionOptions)
    $Config.PythonVersion = Select-TextValue -Label 'Python version prefix' -CurrentValue $Config.PythonVersion
    $Config.ComfyUIRef = Select-TextValue -Label 'ComfyUI ref' -CurrentValue $Config.ComfyUIRef
    $Config.ImageName = Select-TextValue -Label 'Image name' -CurrentValue $Config.ImageName

    return $Config
}
