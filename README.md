# wist-knowledge

wist 的**知识库**——网关装载后用于：采集单元 / 包 / 工作模板、用途推断、发现方向策略。
（这些是**人审定**的知识（代码里称「策展数据」），区别于 agent 自动上报的「事实」。）

## 文件

| 文件 | 网关配置段 | 作用 |
| --- | --- | --- |
| `catalog.toml` | `[content] catalog_file` | 采集单元目录（`sources` / `match` / `rule_ref` / 就绪度） |
| `packs.toml` | `[content] packs_file` | 采集包（基线包 ⊕ 特性包） |
| `templates.toml` | `[content] templates_file` | 常驻工作模板（按 `machine_class` 组合包）——**决定「系统类型」建议** |
| `purpose-rules.toml` | `[purpose] rules_file` | 用途推断规则 |
| `aspect-policies.toml` | `[discovery] policies_file` | 发现方向策略（下发给 agent） |

版本：`catalog_version = 2`、`template_version = 1`（在文件内声明）。**改内容要 bump 版本**——已授权的工作
锁在它展开时那一版目录上（`standing_work.catalog_version`），换版不追改在跑的工作。

## 创作源

本仓就是**创作源**（2026-09 起从 `wist-design/jumo/model/content/` 迁来）：改内容只改这里。
网关侧只**读**——部署时把这几份拷进它的配置目录（如 `content/`），不在代码里内嵌默认副本
（内嵌就有两份真相，改内容必然漂移）。

仓外引用数据的位置：

| 位置 | 用途 |
| --- | --- |
| `wist-gateway/src/app/{content,purpose,discovery_policy}.rs`、`src/api/tests.rs` | 用**真实数据**跑装载/推断/下发；**缺数据即失败**（不再静默跳过）。定位：`WIST_KNOWLEDGE_DIR` 优先，否则 `<网关仓>/../wist-knowledge` |
| `wist-gateway-stack/dev/svc.sh` | 开发态把三件套拷进 `~/.wist-gateway/content`（`WIST_KNOWLEDGE_DIR` 可覆盖源目录） |

网关的 `cargo test` 除了本仓，还读**模型仓 `wist-design`**（`jumo/model/static/.../families.mju`，校验采集面闭集一致），
定位：`WIST_DESIGN_DIR` 优先，否则 `<网关仓>/../wist-design`（本地开发仓组里它在上一级）。
CI 把两个仓都 checkout 成网关仓的同级目录（见 `wist-gateway/.github/workflows/build-and-test.yml`）。

## 制品与发布

**打 tag 即出可下载制品**（`.github/workflows/release.yml`，tag `v*.*.*` 触发）：

1. bump `version.txt`（版本权威；gx 仓里就是 `gx adm v_patch` / `v_feat`）→ commit / push
2. 打 tag 并推送：`v<version>`，制品通道加后缀（`v0.1.0-alpha` / `-beta`；gx 仓里就是 `gx adm tag_alpha` / `tag_beta`）

产物（GitHub Release 附件 + workflow artifact，保留 7 天）：

- `wist-knowledge-<version>.tar.gz` —— 顶层一层同名目录，内含五份数据 + `manifest.json`
  （`version` / `created_at` / `commit` / `content_versions` / 每份文件的 sha256）
- `wist-knowledge-<version>.tar.gz.sha256`

本地预览与自测：`./scripts/package.sh --dry-run`（版本取自 `version.txt`；显式传 `--version` 只接受
`version.txt` 本身或 `<它>-alpha` / `-beta` 这类通道后缀，否则拒掉——防“打了 tag 却忘了 bump”的漂移）。

为什么打成制品、而不是让网关读本仓目录：形态对齐既有「Agent 安装包」——管理面录入 / 离线投放 /
版本历史 / 内容寻址。**网关侧的导入流程还没做**（生效版本指针、签名、schema 兼容校验、旧版共存），
见后续设计稿。
