param(
    [ValidateSet('start','stop','webui-token','onebot-token')][string]$Action = 'start',
    [string]$Distro = 'Dafeiyu-Ubuntu',
    [string]$RuntimeUser = 'dafeiyu'
)
$ErrorActionPreference = 'Stop'
$linuxHome = & wsl.exe -d $Distro -u $RuntimeUser --exec printenv HOME
if ($LASTEXITCODE -ne 0) { throw '无法读取专用 Ubuntu 用户目录。' }
$linuxHome = ($linuxHome -join '').Trim()
if ($linuxHome -notmatch '^/[a-zA-Z0-9_./-]+$') { throw 'Ubuntu 用户目录无效。' }
if ($Action -eq 'start') {
    & wsl.exe -d $Distro -u root --exec systemctl start docker
    if ($LASTEXITCODE -ne 0) { throw 'Docker 服务启动失败。' }
    & wsl.exe -d $Distro -u root --exec docker start qq-ai
    if ($LASTEXITCODE -ne 0) { throw 'QQ 容器启动失败。' }
    Write-Host '正在启动大肥鱼。面板将自动打开，请保持此进程运行。'
    & wsl.exe -d $Distro -u $RuntimeUser --exec bash "$linuxHome/deployment/run-panel.sh" | ForEach-Object {
        $line = [string]$_
        if ($line -match '^QQ_CONTROL_URL=(http://127\.0\.0\.1:\d+/#.+)$') {
            Start-Process $Matches[1]
            Write-Host '控制面板已打开。先连接 QQ，再配置回复范围。'
        } else { Write-Host $line }
    }
} elseif ($Action -eq 'stop') {
    & wsl.exe -d $Distro -u $RuntimeUser --exec bash "$linuxHome/deployment/stop-panel.sh"
    & wsl.exe -d $Distro -u root --exec docker stop qq-ai
    Write-Host '大肥鱼与 QQ 桥接已停止。'
} else {
    $result = & wsl.exe -d $Distro -u root --exec python3 "$linuxHome/deployment/read-token.py" $Action --runtime-user $RuntimeUser
    if ($LASTEXITCODE -ne 0) { throw '令牌读取失败。' }
    ($result -join '').Trim() | Set-Clipboard
    Write-Host '令牌已复制到剪贴板，请只粘贴到本机管理页面。'
}