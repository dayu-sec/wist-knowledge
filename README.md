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

## 现状（待定项）

- 本目录当前是 `wist-design/jumo/model/content/`（模型仓）那份的**副本**。网关侧的装载约定与测试仍指向旧路径
  （`wist-gateway/src/app/content.rs` 的 `../../wist-design/jumo/model/content`；`infra/config.rs` 的注释）。
  **待定**：
  1. 把**创作源迁到本目录**（并更新网关测试与注释，避免两份真相）；还是
  2. 保留模型仓为创作源，本目录只作**发布制品/装载素材**（下游拷贝）。
- 管理 / 发布方案（版本化内容制品 + 管理面录入与切换 + 签名 + schema 兼容校验 + 旧版共存 + 离线投放）见后续设计稿；
  形态对齐既有「Agent 安装包」（`agent_install_package` + `_history` + 管理面录入 + `import-package.sh` 离线投放），
  额外需要：**生效版本指针**、**签名**、**schema 兼容校验**、**旧版共存**（因为网关是*消费者*，不是仓库）。
