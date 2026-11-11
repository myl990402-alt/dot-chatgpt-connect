# 配置说明

`config.local.json` 相对于项目目录查找；也可用 `-ConfigPath` 指定完整路径。未知配置项和越界超时会报错。

| 配置项 | 默认值 | 用途 |
| --- | --- | --- |
| proxyMode | auto | auto／explicit／direct |
| proxyUrl | 空 | explicit 模式下的 HTTP 或 HTTPS 代理地址 |
| appPath | 空 | 通常由 Windows 应用包自动发现；特殊安装可填写完整 exe 路径 |
| timeoutSeconds | 10 | 每个诊断请求的超时，允许 1–60 秒 |
| codexConfigPath | 空 | 优先使用 `$env:CODEX_HOME/config.toml`，否则当前用户 `.codex/config.toml` |

原始“五次重连修复”的配置是：

```toml
[features]
respect_system_proxy = true
```

已有 `[features]` 时只添加或修改其中的键，不要重复创建表。它是实验特性，旧版或后续版本可能不支持；可用本机 `codex features list` 核对是否存在。工具不自动下载安装 CLI，也不修改其他 Codex 设置。管理员管理的配置可能覆盖个人设置。

修改预览：`pwsh -File .\Connect.ps1 -Action EnableCodexProxy -WhatIf`。

自动编辑器仅支持简单、明确的 TOML 形式；遇到重复键、重复表、行内表、带引号的表名、多行字符串或其他复杂形式时会拒绝修改，请手动编辑并验证 TOML。原文件备份和恢复元数据保存在项目私有 `data/`，发布时排除该目录。

启动代理使用 `HTTP_PROXY`、`HTTPS_PROXY`、`ALL_PROXY`、`NO_PROXY`、`NODE_USE_ENV_PROXY` 和应用 `--proxy-server` 参数。这些只在启动进程的环境中设置；客户端是否采用这些设置取决于它的运行时版本，应以实际日志和功能验收为准。

参考：[OpenAI 管理配置](https://learn.chatgpt.com/docs/enterprise/managed-configuration)、[Node.js 代理配置](https://nodejs.org/learn/http/enterprise-network-configuration)。
