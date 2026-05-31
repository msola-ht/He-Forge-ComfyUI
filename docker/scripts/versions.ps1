$script:CudaTagsDataPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'data/cuda-tags.json'
$script:PyTorchTagsDataPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'data/pytorch-tags.json'

function Get-CudaTagsDataPath {
    return $script:CudaTagsDataPath
}

function Get-CudaTagsData {
    $dataPath = Get-CudaTagsDataPath
    if (-not (Test-Path $dataPath)) {
        throw "CUDA 镜像标签数据不存在：$dataPath。请运行 python docker/scripts/update-cuda-tags.py 更新。"
    }

    return Get-Content -LiteralPath $dataPath -Raw | ConvertFrom-Json
}

function Get-PyTorchTagsDataPath {
    return $script:PyTorchTagsDataPath
}

function Get-PyTorchTagsData {
    $dataPath = Get-PyTorchTagsDataPath
    if (-not (Test-Path $dataPath)) {
        throw "PyTorch 版本矩阵不存在：$dataPath。请运行 python docker/scripts/update-pytorch-tags.py 更新。"
    }

    return Get-Content -LiteralPath $dataPath -Raw | ConvertFrom-Json
}

function Get-CudaImageVersionOptions {
    param(
        [string]$UbuntuVersion = '22.04'
    )

    $data = Get-CudaTagsData
    $ubuntuNode = $data.ubuntu.$UbuntuVersion
    if (-not $ubuntuNode) {
        return @()
    }

    return @($ubuntuNode)
}

function Get-PyTorchCudaProfileOptions {
    param(
        [string]$TorchVersion = '2.7.0'
    )

    $data = Get-PyTorchTagsData
    $entry = $data.versions.$TorchVersion
    if (-not $entry) {
        return @()
    }

    return @($entry.cuda_profiles)
}

function Resolve-PyTorchIndexUrl {
    param(
        [string]$PyTorchCudaProfile,
        [string]$TorchVersion = '2.7.0'
    )

    Assert-PyTorchCudaProfile -PyTorchCudaProfile $PyTorchCudaProfile -TorchVersion $TorchVersion
    return "https://download.pytorch.org/whl/$PyTorchCudaProfile"
}

function Get-UbuntuVersionOptions {
    $data = Get-CudaTagsData
    return @($data.ubuntu.PSObject.Properties.Name | Sort-Object)
}

function Get-NodeJsVersionOptions {
    return @('22', '24')
}

function Get-TorchVersionOptions {
    $data = Get-PyTorchTagsData
    return @($data.versions.PSObject.Properties.Name | Sort-Object { [version]$_ } -Descending)
}

function Assert-UbuntuVersion {
    param(
        [string]$UbuntuVersion
    )

    if ($UbuntuVersion -notin (Get-UbuntuVersionOptions)) {
        $supportedUbuntuVersions = (Get-UbuntuVersionOptions) -join ', '
        throw "不支持的 UbuntuVersion：$UbuntuVersion。当前支持：$supportedUbuntuVersions"
    }
}

function Assert-CudaImageVersion {
    param(
        [string]$CudaImageVersion,
        [string]$UbuntuVersion
    )

    Assert-UbuntuVersion -UbuntuVersion $UbuntuVersion
    $supportedCudaImageVersions = Get-CudaImageVersionOptions -UbuntuVersion $UbuntuVersion
    if ($CudaImageVersion -notin $supportedCudaImageVersions) {
        $supportedText = $supportedCudaImageVersions -join ', '
        throw "不支持的 CUDA_IMAGE_VERSION：$CudaImageVersion。Ubuntu $UbuntuVersion 当前支持：$supportedText"
    }
}

function Assert-PyTorchCudaProfile {
    param(
        [string]$PyTorchCudaProfile,
        [string]$TorchVersion = '2.7.0'
    )

    $supportedProfiles = Get-PyTorchCudaProfileOptions -TorchVersion $TorchVersion
    if ($PyTorchCudaProfile -notin $supportedProfiles) {
        $supportedText = $supportedProfiles -join ', '
        throw "不支持的 PyTorchCudaProfile：$PyTorchCudaProfile。Torch $TorchVersion 当前支持：$supportedText"
    }
}

function Assert-NodeJsVersion {
    param(
        [string]$NodeJsVersion
    )

    if ($NodeJsVersion -notin (Get-NodeJsVersionOptions)) {
        $supportedNodeJsVersions = (Get-NodeJsVersionOptions) -join ', '
        throw "不支持的 NodeJsVersion：$NodeJsVersion。当前支持：$supportedNodeJsVersions"
    }
}

function Assert-TorchVersion {
    param(
        [string]$TorchVersion
    )

    if ($TorchVersion -notin (Get-TorchVersionOptions)) {
        $supportedTorchVersions = (Get-TorchVersionOptions) -join ', '
        throw "不支持的 TorchVersion：$TorchVersion。当前支持：$supportedTorchVersions"
    }
}

function Resolve-PyTorchPackageVersions {
    param(
        [string]$TorchVersion
    )

    Assert-TorchVersion -TorchVersion $TorchVersion
    $data = Get-PyTorchTagsData
    $entry = $data.versions.$TorchVersion
    $xformersVersion = ''
    if ($entry.PSObject.Properties.Name -contains 'xformers' -and $entry.xformers) {
        $xformersVersion = $entry.xformers.version
    }

    return @{
        TorchVersion = $TorchVersion
        TorchVisionVersion = $entry.torchvision
        TorchAudioVersion = $entry.torchaudio
        XformersVersion = $xformersVersion
    }
}

function Resolve-XformersVersion {
    param(
        [string]$TorchVersion,
        [string]$PyTorchCudaProfile
    )

    Assert-PyTorchCudaProfile -PyTorchCudaProfile $PyTorchCudaProfile -TorchVersion $TorchVersion
    $data = Get-PyTorchTagsData
    $entry = $data.versions.$TorchVersion
    if (-not ($entry.PSObject.Properties.Name -contains 'xformers') -or -not $entry.xformers) {
        return ''
    }

    $supportedProfiles = @($entry.xformers.cuda_profiles)
    if ($PyTorchCudaProfile -notin $supportedProfiles) {
        return ''
    }

    return $entry.xformers.version
}

function Resolve-CudaImageSet {
    param(
        [string]$CudaImageVersion,
        [string]$UbuntuVersion,
        [ValidateSet('runtime', 'devel')]
        [string]$Variant = 'runtime'
    )

    Assert-CudaImageVersion -CudaImageVersion $CudaImageVersion -UbuntuVersion $UbuntuVersion
    $ubuntuImageTag = "ubuntu$UbuntuVersion"
    $ubuntuCacheKey = "ubuntu$($UbuntuVersion.Replace('.', ''))"

    return @{
        CudaVersion = $CudaImageVersion
        UbuntuCacheKey = $ubuntuCacheKey
        BuilderCudaImage = "nvidia/cuda:$CudaImageVersion-devel-$ubuntuImageTag"
        RuntimeCudaImage = "nvidia/cuda:$CudaImageVersion-runtime-$ubuntuImageTag"
        DevelCudaImage = "nvidia/cuda:$CudaImageVersion-devel-$ubuntuImageTag"
        FinalCudaImage = "nvidia/cuda:$CudaImageVersion-$Variant-$ubuntuImageTag"
    }
}

function Resolve-ImageTagSuffix {
    param(
        [string]$CudaImageVersion,
        [string]$PyTorchCudaProfile,
        [string]$UbuntuVersion,
        [string]$TorchVersion,
        [string]$PythonVersion = '3.12',
        [ValidateSet('runtime', 'devel')]
        [string]$Variant,
        [ValidateSet('bootstrap', 'final')]
        [string]$BuildStage = 'final'
    )

    Assert-CudaImageVersion -CudaImageVersion $CudaImageVersion -UbuntuVersion $UbuntuVersion
    Assert-TorchVersion -TorchVersion $TorchVersion
    Assert-PyTorchCudaProfile -PyTorchCudaProfile $PyTorchCudaProfile -TorchVersion $TorchVersion

    $safePythonVersion = $PythonVersion.Replace('.', '')
    $tagSuffix = "ubuntu$UbuntuVersion-py$safePythonVersion-$PyTorchCudaProfile-torch$TorchVersion"
    if ($BuildStage -eq 'bootstrap') {
        $tagSuffix = "$tagSuffix-bootstrap-$Variant"
    } else {
        $tagSuffix = "$tagSuffix-$Variant"
    }

    return $tagSuffix
}

function Resolve-CacheKeySuffix {
    param(
        [string]$CudaImageVersion,
        [string]$PyTorchCudaProfile,
        [string]$UbuntuVersion,
        [string]$TorchVersion,
        [string]$PythonVersion,
        [ValidateSet('runtime', 'devel')]
        [string]$Variant
    )

    $tagSuffix = "cuda$CudaImageVersion-$PyTorchCudaProfile-ubuntu$UbuntuVersion-torch$TorchVersion-$Variant"
    $safePythonVersion = $PythonVersion.Replace('.', '')
    return "$tagSuffix-py$safePythonVersion"
}
