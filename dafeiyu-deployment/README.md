# 部署脚本

完整流程见 [项目结构与部署复现](../docs/项目结构与部署复现.md)。这些脚本不含真实 QQ 号和 API Key。

| 文件 | 用途 |
|---|---|
| `Start.cmd` / `Stop.cmd` | Windows 启动与停止入口 |
| `Dafeiyu.ps1` | 调用专用 WSL；支持 `-Distro`、`-RuntimeUser`，控制地址只传入本机浏览器 |
| `Copy-WebUI-Token.cmd` | 将 NapCat 管理页面所需令牌复制到剪贴板 |
| `Copy-OneBot-Token.cmd` | 将大肥鱼连接页面所需令牌复制到剪贴板 |
| `install-runtime.sh` | 新环境安装 Linux 辅助脚本，建立源码链接，首次生成私有配置 |
| `run-panel.sh` / `stop-panel.sh` | Linux 面板生命周期与单实例锁 |
| `get-panel-url.py` / `read-token.py` | 由启动器内部捕获控制地址或令牌；不要公开其标准输出 |
| `provision-qq.sh` | 创建并启动固定摘要的 amd64 NapCat 容器，校验内部发行包 |
| `check-login.py` | 只输出 QQ 登录阶段，不输出二维码或令牌 |
| `Refresh-WslService.ps1` | 磁盘位置被手动移动后的修复工具；新部署通常不需要 |
| `DeepSeek空正文修复.patch` | 早期修复的参考补丁，当前源码已包含，不能重复应用 |

WSL 路径备份、诊断结果及其他本机状态已由根目录 `.gitignore` 排除。`Refresh-WslService.ps1` 的 `-RestartWslService` 会影响整个 WSL 后台，应先保存其他 WSL 任务；它不是普通启动步骤。
