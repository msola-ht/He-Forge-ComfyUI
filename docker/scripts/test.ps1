function Invoke-DockerTestCommand {
    param(
        [string]$Name,
        [string]$ImageTag,
        [string[]]$Command,
        [switch]$Gpu
    )

    Write-Host ""
    Write-Host "[Test] $Name"

    $arguments = @('run', '--rm')
    if ($Gpu) {
        $arguments += @('--gpus', 'all')
    }

    $arguments += $ImageTag
    $arguments += $Command

    & docker @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "镜像自检失败：$Name，退出码：$LASTEXITCODE"
    }
}

function Invoke-ImageSmokeTest {
    param(
        [string]$ImageTag,
        [ValidateSet('bootstrap', 'final')]
        [string]$BuildStage
    )

    Write-Host ""
    Write-Host "[Test] 开始镜像自检：$ImageTag（$BuildStage）"

    Invoke-DockerTestCommand -Name 'Python 版本' -ImageTag $ImageTag -Command @('python', '--version')
    Invoke-DockerTestCommand -Name 'Node.js 版本' -ImageTag $ImageTag -Command @('node', '-v')
    Invoke-DockerTestCommand -Name 'npm 版本' -ImageTag $ImageTag -Command @('npm', '-v')
    Invoke-DockerTestCommand -Name 'uv 版本' -ImageTag $ImageTag -Command @('uv', '--version')
    Invoke-DockerTestCommand -Name 'ComfyUI 种子目录与 Miniforge 路径' -ImageTag $ImageTag -Command @(
        'bash',
        '-lc',
        'test -f /root/ComfyUI-seed/main.py && test -f /root/ComfyUI/main.py && test -d /root/miniforge && echo "ComfyUI seed and Miniforge OK"'
    )

    if ($BuildStage -eq 'final') {
        Invoke-DockerTestCommand -Name 'PyTorch CUDA 可用性' -ImageTag $ImageTag -Gpu -Command @(
            'python',
            '-c',
            'import torch, torchvision, torchaudio; print("torch=" + torch.__version__); print("torchvision=" + torchvision.__version__); print("torchaudio=" + torchaudio.__version__); import xformers; print("xformers=" + xformers.__version__); print("cuda_available=" + str(torch.cuda.is_available())); assert torch.cuda.is_available(), "CUDA is not available"; print("gpu=" + torch.cuda.get_device_name(0))'
        )
        Invoke-DockerTestCommand -Name 'ComfyUI Python 导入' -ImageTag $ImageTag -Command @(
            'python',
            '-c',
            'import comfy.options; print("comfy_import=ok")'
        )
        Invoke-DockerTestCommand -Name '内置 custom nodes 插件' -ImageTag $ImageTag -Command @(
            'bash',
            '-lc',
            'test -d /root/ComfyUI/custom_nodes/comfyui-manager && test -d /root/ComfyUI/custom_nodes/ComfyUI-DD-Translation && echo "custom_nodes=ok"'
        )
        Invoke-DockerTestCommand -Name '已有目录补齐缺失插件' -ImageTag $ImageTag -Command @(
            'bash',
            '-lc',
            'mkdir -p /tmp/existing-comfyui/custom_nodes && cp /root/ComfyUI-seed/main.py /tmp/existing-comfyui/main.py && COMFYUI_HOME=/tmp/existing-comfyui /usr/local/bin/entrypoint.sh true && test -d /tmp/existing-comfyui/custom_nodes/comfyui-manager && test -d /tmp/existing-comfyui/custom_nodes/ComfyUI-DD-Translation && echo "existing_dir_sync=ok"'
        )
    }

    Write-Host ""
    Write-Host "[Test] 镜像自检通过：$ImageTag"
}
