# Zeabur 部署与 Fork 同步

## 一键部署

最终使用方式是打开已发布的 Zeabur 模板链接、选择项目/地区/域名，然后点击部署。
三个服务、随机凭据、跨服务环境变量引用和持久卷全部由模板创建；不需要逐个添加服务或填写连接串。
以下 CLI 发布步骤仅供本 Fork 的维护者首次建立这个部署入口，普通部署者不需要运行它。

`template.yaml` 一次创建三个服务：从本 Fork 构建的网关、PostgreSQL 18 和 Redis 8。
Zeabur 不直接运行 Docker Compose；模板复用 `deploy/Dockerfile` 的源码构建阶段，
根目录 `zbpack.json` 指定 Dockerfile，最后的 `zeabur` 阶段作为部署镜像。

首次使用前，将本次部署改动提交并合入 `waterpen6/codex-proxy-rs` 的 `main`，
并在 Zeabur 连接 GitHub、授权访问这个仓库。本地修改尚未推送时，远端构建无法使用它们。

从仓库根目录运行官方 CLI（需要 Node.js 与 Zeabur 登录）：

```bash
npx zeabur@latest template deploy -f deploy/zeabur/template.yaml
```

选择项目、地区和域名后，模板会创建服务和持久卷，无需手动填写数据库地址或密码。
第一次要编译 Rust 与前端，耗时取决于构建资源。模板默认一个网关副本，不要横向扩容。
服务启动后，访问所选 HTTPS 域名，用 `admin@cpr.local` 和网关服务说明中的
`Initial admin password` 登录。再添加上游账号与客户端 Key，API Base URL 为 `https://你的域名/v1`。

需要网页上的“一键部署”按钮时，先发布模板：

```bash
npx zeabur@latest template create -f deploy/zeabur/template.yaml
```

CLI 返回真实的 `https://zeabur.com/templates/<模板编号>`，可将它放入 README 作为部署入口。
模板尚未发布，因此仓库没有虚构的模板编号或不可用的部署按钮。发布模板只提供部署入口，
不会替代把源码推送到 GitHub，也不等于运行实例已部署。

再次 Fork 时，修改模板的 `source.repo` 为你的 GitHub 仓库数字 ID，按需修改 `branch`、图标和说明。
该 ID 可从 GitHub 仓库 API 的 `id` 字段取得，不能填写仓库名称代替。

## 配置与数据

| 项目 | 模板行为 |
| --- | --- |
| HTTP | 监听 `0.0.0.0:8080`，Zeabur 域名指向 `web` 端口 |
| 配置文件 | 平台挂载 `/app/deploy/config.yaml`，管理员初始密码由平台随机生成 |
| PostgreSQL | 持久化 `/var/lib/postgresql`，与现有备份工具保持 PostgreSQL 18 一致 |
| Redis | 持久化 `/data`，开启 AOF 与密码认证 |
| 网关 | 持久化 `/app/.runtime`，保留会话密钥、插件运行数据和备份暂存区 |
| 日志 | 普通日志输出到 Zeabur 日志面板；默认关闭文件日志与敏感报文记录 |
| 容器权限 | 启动时初始化挂载目录权限，随后以 UID/GID `10001:10001` 运行业务进程 |

两个数据库服务分别保存平台生成的随机种子 `POSTGRES_SEED` / `REDIS_SEED`，
网关分别通过 `CPR_POSTGRES_SEED` / `CPR_REDIS_SEED` 引用它们。
实际连接密码为种子的 SHA-256 十六进制摘要前 48 位；数据库启动命令与网关入口执行相同转换，
满足项目强制密码格式。种子本身也是凭据，不要公开。连接 URL 不含密码，网关通过现有
`CPR_DATABASE_PASSWORD` / `CPR_REDIS_PASSWORD` 环境变量传入转换结果。

重启或重新部署时保留种子和卷。已有 PostgreSQL 数据时，修改种子不会改变数据库内用户密码，
会导致认证失败；轮换需先按原部署文档修改数据库用户密码，再同步种子和重启依赖服务。
管理员密码在应用内修改；`CPR_ADMIN_PASSWORD` 仅初始化账号，保留平台生成值，
不要把包含引号或换行的自定义文本直接插入配置模板。

数据库连接使用项目内网地址，不需要开启数据库的公网 TCP 转发。只对网关绑定公网域名。
网关的 `/healthz` 返回 204 表示应用及依赖健康，不代表上游模型调用已验证。
部署后还需确认实际账号调用、SSE 与 WebSocket 是否可用。

## 升级

在 Zeabur 将 Git 服务连接到本 Fork 的 `main`。代码更新后通过平台重新构建部署，
并确认项目设置中的 Git 自动部署是否启用。不要使用容器内自更新替代平台部署：
容器可写层中的二进制变化会在下一次重新部署时消失，模板关闭了应用自行请求重启。
平台终止宽限期应覆盖 HTTP drain 与后台任务关停的总预算（默认合计 60 秒，建议至少 75 秒）。

备份 PostgreSQL 和网关卷后再升级；上游跨大版本升级仍须阅读迁移说明。
更新模板定义不会自动改写已有实例的变量或配置文件，已有实例需按变化调整后重新部署。

## 上游同步

本仓库 Fork 自 `zyycn/codex-proxy-rs`。GitHub 的 Fork 关系不会自动同步代码，
上游新增提交也不会自动进入你的 `main`。原有工作流负责质量检查、发布和安全扫描，没有上游同步任务。
外部 GitHub App 或其他账号自动化是否存在，需要仓库所有者在设置中另行确认。

手动同步：打开 GitHub 仓库首页，选择 **Sync fork → Update branch**。存在冲突时需手动解决，
不要使用丢弃本 Fork 提交的选项。保留 Zeabur 部署改动需要正常合并上游，不能重置成上游分支。

本次新增 `.github/workflows/sync-upstream.yml`，默认关闭定时同步，可按以下步骤启用：

1. 将工作流合入本 Fork 的默认分支 `main`，在 **Actions** 页面启用 Fork 的工作流。
2. 在 **Settings → Secrets and variables → Actions → Variables** 添加
   `ENABLE_UPSTREAM_SYNC`，值为 `true`。
3. 工作流每天北京时间 10:17 尝试合并上游 `main`；也可从 **Actions → Sync upstream → Run workflow** 手动运行。
4. 查看运行结果。冲突、分支保护或权限不足会使任务失败，保留现有分支，不强推、不丢弃本地定制提交。

默认使用 `GITHUB_TOKEN` 和 `contents: write`。它产生的更新通常不会触发其他 GitHub Actions，
也不能保证 Zeabur 收到自动部署事件；若需要后续 CI/自动部署，配置名为 `UPSTREAM_SYNC_TOKEN` 的
仓库 Secret，使用仅授权本仓库的 fine-grained PAT，授予 Contents 读写；同步涉及工作流文件时还需
Workflows 读写权限。组织策略与分支保护仍然生效，首次同步后检查 CI 和 Zeabur 部署记录。
不要把 Token 写进 YAML 或提交到 Git。PAT 到期需要续期。

该方案开启后会直接合并上游；开启 Zeabur 自动部署时也可能自动更新运行服务。
希望先审阅升级内容时，保持定时同步关闭并手动同步。GitHub 定时任务可能延迟，
公开仓库长期无活动时也可能被停用，可在 Actions 页面重新启用。

## 官方参考

- [Zeabur 模板格式](https://zeabur.com/docs/en-US/template/template-format)
- [Zeabur Dockerfile 部署](https://zeabur.com/docs/en-US/deploy/methods/dockerfile)
- [GitHub 同步 Fork](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/working-with-forks/syncing-a-fork)
