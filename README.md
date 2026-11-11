# dot ChatGPT Connect

Windows 上的 ChatGPT／Codex／Dot 代理诊断与启动工具。用于排查 Codex 启动时反复重连、Dot 显示电脑在线但桌面请求没有响应、快捷方式点击后没有反应等问题。

这是独立的社区辅助工具，与 OpenAI 无隶属关系。当前为 **0.1.0 实验版本**。诊断可以验证 TLS／HTTP 可达；Dot 登录会话、WebSocket 长连接和实际文件读取仍需独立验收。

## 快速使用

需要 Windows 10/11、PowerShell **7.4+**、Windows 自带的 `curl.exe`，以及已安装并登录的 ChatGPT 桌面应用。使用你有权使用的网络与代理。

1. 安装 PowerShell 7：`winget install --id Microsoft.PowerShell --exact`，然后打开新的 PowerShell 终端。
2. 将本项目解压到固定目录，启动自己的代理软件。
3. 在项目目录运行 `pwsh -NoProfile -File .\Connect.ps1 -Action Diagnose`。
4. 针对“首次五次重连”现象，运行 `pwsh -NoProfile -File .\Connect.ps1 -Action EnableCodexProxy`。
5. 完全退出 ChatGPT，再双击 `start.cmd`。已有进程不会继承新启动参数。
6. 按 [验收步骤](docs/VERIFICATION.md) 测试 Dot。

创建桌面图标：`pwsh -NoProfile -File .\Connect.ps1 -Action InstallShortcut`。图标名为 **dot ChatGPT**。移动项目目录或卸载该 PowerShell 后，需要重新创建快捷方式。

不要使用 Windows PowerShell 5.1 的 `powershell.exe` 代替 `pwsh.exe`。工具不会更改执行策略；如有组织策略限制，请按管理员允许的方式运行，不要关闭策略。下载文件被标记为来自互联网时，先审查来源和源码，再依照自己的执行策略处理文件阻止状态。

## 两项修复分别做什么

| 症状 | 对应处理 | 验证范围 |
| --- | --- | --- |
| Codex 重启后首次反复重连，通常显示到第 5 次 | 在现有 `config.toml` 的 `[features]` 中设置 `respect_system_proxy = true` | 让原生 Codex 运行时尝试使用系统代理；需重启实测 |
| Dot 在线，但本地创建／读取请求失败 | 诊断三个相关服务，并以进程级 HTTP／HTTPS 与 Node 代理环境启动应用 | 启动环境调整；不保证账户、授权、WebSocket 或桌面接口已经恢复 |
| 快捷方式无反应 | 使用 PowerShell 7、显示错误、动态查找安装位置、已有应用立即打开 | 不再使用隐藏的长时间退出等待 |

**“五次重连修复”不是将重试次数改成五次。** 原方案的改动只有 `respect_system_proxy`。本工具不会改变客户端内部重试上限，不会自动重复创建对话，也不会循环重启应用。

## 适配自己的代理

默认 `auto` 优先识别 Windows 手动系统代理，然后检查 `HTTPS_PROXY`／`HTTP_PROXY`，否则使用直连／系统 VPN 路由。不会假设端口一定是 7897。

复制 `config.example.json` 为 `config.local.json`。例如使用自己的 HTTP 代理端口：

```json
{
  "proxyMode": "explicit",
  "proxyUrl": "http://127.0.0.1:7897",
  "appPath": "",
  "timeoutSeconds": 10,
  "codexConfigPath": ""
}
```

TUN／全隧道 VPN 用户可选择 `"proxyMode": "direct"`，测试系统路由；这不会关闭 VPN。PAC 自动配置需要自己解析出实际代理地址，再使用 explicit。当前不支持 SOCKS-only 和带账号密码的代理 URL。

工具不读取 Clash 订阅、节点凭据、ChatGPT 登录令牌或聊天记录。报告只记录服务域名、状态码、耗时、curl 错误码。可分享报告仍应先自行检查。

## 回退与限制

`EnableCodexProxy` 只编辑指定特性，修改前保存原文件。若配置已经为 true，不产生改动。运行 `RestoreCodexProxy` 可回退本工具的最后一次修改；如果之后又编辑了配置，会拒绝覆盖。

进程级代理只影响本次启动的应用及其子进程。完全退出后用原来的应用入口启动，即不再使用本工具传入的参数。工具不会改动系统代理、VPN、TUN、证书、防火墙和账户权限。

当前不包含后台守护、账户登录、自动授予 Dot 权限或长时间稳定性保证。官方内部服务地址可能变化，可按新版本调整源码中的诊断地址。其他平台尚未支持。

## 开发与发布

离线测试：`pwsh -NoProfile -File .\tests\Run.ps1`。测试只改临时目录，不触碰真实配置。

发布时只提交源码、文档、示例配置和图标。`config.local.json`、`data/`、原始日志、快捷方式均不应提交；`data/` 里的配置备份可能含原配置中的敏感信息。不要把整个 Codex 配置目录或本机历史记录上传 GitHub。

详见 [配置说明](docs/CONFIGURATION.md)、[网络排查](docs/NETWORK.md)、[验收步骤](docs/VERIFICATION.md) 和 [发布清单](docs/RELEASE.md)。源码及原创图标采用 MIT 许可证。
