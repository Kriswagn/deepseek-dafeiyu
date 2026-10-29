# deepseek-dafeiyu

基于 [SAKURAfan1023/dafeiyu-bot](https://github.com/SAKURAfan1023/dafeiyu-bot) 的 DeepSeek QQ 聊天机器人部署与改进版本，使用 NapCat / OneBot 连接 QQ，可在 Windows + WSL2 环境运行。

## 目录

- [`dafeiyu-bot/`](dafeiyu-bot/)：完整应用源码、Web 控制面板、测试及可移植部署脚本。
- [原项目使用说明](dafeiyu-bot/README.md)、[操作指南](dafeiyu-bot/docs/USER_GUIDE.md)、[安全说明](dafeiyu-bot/SECURITY.md)。
- [`dafeiyu-deployment/`](dafeiyu-deployment/)：Windows 启停入口、Linux 运行辅助脚本、QQ 容器部署与登录检查。
- [`docs/项目结构与部署复现.md`](docs/项目结构与部署复现.md)：项目结构、环境准备、安装、启动、配置及验证步骤。
- `dafeiyu-wsl/`：本机 WSL 虚拟磁盘，保留在本地并由 Git 忽略。

## 本地改进

- 修复模型在 JSON 模式下成功结束但正文为空时的处理：有限重试保留原有上下文，每次重试仍受调用额度和取消检查约束。
- 增加空闲会话主动消息，支持分别选择好友和群，沿用当前会话的内置性格。
- 主动消息默认关闭；开启后，空闲门槛与随机等待共同控制评估，模型也可选择保持安静。
- 可配置全天时段、至少空闲 60 分钟、每轮最多 5 条及所有选中会话共享的每日 20 条上限。每条发送前核对会话活动和额度，有新聊天时取消后续消息。
- 主动发送账本持久保存，结果未知不重发；暂停、断线和重启不会补发旧任务。
- 增加相关合成测试及控制面板配置校验。记忆继续采用项目已有实现。

实际账号、会话名单、密钥、聊天记忆和运行日志均保存在本机，不包含在仓库中。首次部署仍须自行配置模型凭证、QQ 登录及回复范围。

## 开发验证

在 `dafeiyu-bot/` 目录下运行：

```bash
bash scripts/test.sh
python3 scripts/check-public.py
bash scripts/build-linux.sh
```

macOS 构建使用 `bash scripts/build.sh`。自动测试使用合成账号与本机模拟服务，不向真实联系人发送测试消息。

## 来源与许可

本版本基于上游提交 `cc8170396bc68266077204576f8469e414b5c44c`。保留原作者署名、[MIT 许可证](dafeiyu-bot/LICENSE)以及[第三方素材声明](dafeiyu-bot/THIRD_PARTY_NOTICES.md)；第三方图片等素材按各自声明使用。
