function Select-Option {
    param(
        [string]$Label,
        [string]$CurrentValue,
        [string[]]$Options
    )

    if (-not $Options -or $Options.Count -eq 0) {
        throw "${Label} 没有可用选项，请先更新本地版本数据。"
    }

    if ($CurrentValue -notin $Options) {
        $previousValue = $CurrentValue
        $CurrentValue = $Options[0]
        Write-Host ""
        Write-Host "${Label} 当前值 [$previousValue] 不在可选列表中，已临时切换为 [$CurrentValue]"
    }

    Write-Host ""
    Write-Host "$Label"
    for ($index = 0; $index -lt $Options.Count; $index++) {
        $marker = if ($Options[$index] -eq $CurrentValue) { '*' } else { ' ' }
        Write-Host ("  {0}. [{1}] {2}" -f ($index + 1), $marker, $Options[$index])
    }

    $answer = Read-Host "请选择 1-$($Options.Count)，或直接回车保留 [$CurrentValue]"
    if (-not $answer) {
        return $CurrentValue
    }

    $selectedIndex = 0
    if (-not [int]::TryParse($answer, [ref]$selectedIndex)) {
        throw "${Label} 选择无效：$answer"
    }

    if ($selectedIndex -lt 1 -or $selectedIndex -gt $Options.Count) {
        throw "${Label} 选择超出范围：$answer"
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
        default { throw "无效的是/否输入：$answer" }
    }
}

function Select-BuildStage {
    param(
        [string]$CurrentValue
    )

    if (-not $CurrentValue) {
        $CurrentValue = 'final'
    }

    return Select-Option -Label '构建阶段' -CurrentValue $CurrentValue -Options @('bootstrap', 'final')
}

function Show-VersionConfig {
    param(
        [hashtable]$Config
    )

    Write-Host ""
    Write-Host "当前版本配置"
    Write-Host "  IMAGE_NAME=$($Config.ImageName)"
    Write-Host "  CUDA_IMAGE_VERSION=$($Config.CudaImageVersion)"
    Write-Host "  PYTORCH_CUDA_PROFILE=$($Config.PyTorchCudaProfile)"
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

    $Config.UbuntuVersion = Select-Option -Label 'Ubuntu 版本' -CurrentValue $Config.UbuntuVersion -Options (Get-UbuntuVersionOptions)
    $Config.CudaImageVersion = Select-Option -Label 'CUDA 镜像版本' -CurrentValue $Config.CudaImageVersion -Options (Get-CudaImageVersionOptions -UbuntuVersion $Config.UbuntuVersion)
    $Config.TorchVersion = Select-Option -Label 'Torch 版本' -CurrentValue $Config.TorchVersion -Options (Get-TorchVersionOptions)
    $Config.PyTorchCudaProfile = Select-Option -Label 'PyTorch CUDA 源' -CurrentValue $Config.PyTorchCudaProfile -Options (Get-PyTorchCudaProfileOptions -TorchVersion $Config.TorchVersion)
    $Config.NodeJsVersion = Select-Option -Label 'Node.js 版本' -CurrentValue $Config.NodeJsVersion -Options (Get-NodeJsVersionOptions)
    $Config.PythonVersion = Select-TextValue -Label 'Python 版本前缀' -CurrentValue $Config.PythonVersion
    $Config.ComfyUIRef = Select-TextValue -Label 'ComfyUI 引用（分支、标签或提交）' -CurrentValue $Config.ComfyUIRef
    $Config.ImageName = Select-TextValue -Label '镜像名称' -CurrentValue $Config.ImageName

    return $Config
}
