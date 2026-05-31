function Get-CudaProfileMap {
    return @{
        cu128 = @{
            CudaVersion = '12.8.2'
        }
        cu126 = @{
            CudaVersion = '12.6.3'
        }
    }
}

function Get-CudaProfileOptions {
    return @('cu128', 'cu126')
}

function Get-UbuntuVersionOptions {
    return @('22', '24')
}

function Get-NodeJsVersionOptions {
    return @('22', '24')
}

function Get-TorchVersionOptions {
    return @('2.7.1', '2.7.0', '2.6.0')
}

function Resolve-CudaVersion {
    param(
        [string]$CudaProfile
    )

    $cudaProfileMap = Get-CudaProfileMap
    if (-not $cudaProfileMap.ContainsKey($CudaProfile)) {
        $supportedCudaProfiles = (Get-CudaProfileOptions) -join ', '
        throw "Unsupported CudaProfile: $CudaProfile. Supported: $supportedCudaProfiles"
    }

    return $cudaProfileMap[$CudaProfile].CudaVersion
}

function Assert-UbuntuVersion {
    param(
        [string]$UbuntuVersion
    )

    if ($UbuntuVersion -notin (Get-UbuntuVersionOptions)) {
        $supportedUbuntuVersions = (Get-UbuntuVersionOptions) -join ', '
        throw "Unsupported UbuntuVersion: $UbuntuVersion. Supported: $supportedUbuntuVersions"
    }
}

function Assert-NodeJsVersion {
    param(
        [string]$NodeJsVersion
    )

    if ($NodeJsVersion -notin (Get-NodeJsVersionOptions)) {
        $supportedNodeJsVersions = (Get-NodeJsVersionOptions) -join ', '
        throw "Unsupported NodeJsVersion: $NodeJsVersion. Supported: $supportedNodeJsVersions"
    }
}

function Assert-TorchVersion {
    param(
        [string]$TorchVersion
    )

    if ($TorchVersion -notin (Get-TorchVersionOptions)) {
        $supportedTorchVersions = (Get-TorchVersionOptions) -join ', '
        throw "Unsupported TorchVersion: $TorchVersion. Supported: $supportedTorchVersions"
    }
}

function Resolve-CudaImageSet {
    param(
        [string]$CudaProfile,
        [string]$UbuntuVersion,
        [ValidateSet('runtime', 'devel')]
        [string]$Variant = 'runtime'
    )

    Assert-UbuntuVersion -UbuntuVersion $UbuntuVersion
    $cudaVersion = Resolve-CudaVersion -CudaProfile $CudaProfile
    $ubuntuImageTag = "ubuntu$UbuntuVersion.04"

    return @{
        CudaVersion = $cudaVersion
        BuilderCudaImage = "nvidia/cuda:$cudaVersion-devel-$ubuntuImageTag"
        RuntimeCudaImage = "nvidia/cuda:$cudaVersion-runtime-$ubuntuImageTag"
        DevelCudaImage = "nvidia/cuda:$cudaVersion-devel-$ubuntuImageTag"
        FinalCudaImage = "nvidia/cuda:$cudaVersion-$Variant-$ubuntuImageTag"
    }
}
