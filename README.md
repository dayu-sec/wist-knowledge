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

版本（各自在文件内声明）：`catalog_version = 3`（目录 / 包 / 模板）、`template_version = 1`、
`policy_version = 1`（发现策略）、`purpose_version = 2`（用途规则）。**改内容要 bump 对应版本**——
已授权的工作锁在它展开时那一版目录上（`standing_work.catalog_version`），换版不追改在跑的工作；
用途规则那个版本是**建议的归因锚**（见网关侧 `docs/design/knowledge-content-management.md` §8.2）。

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

## 发布

本仓按**组件**走（不是制品）：只在 `main` 开发与发布，**tag 就是 `v<version>`，不带 `-alpha` / `-beta` 通道后缀**。
（制品的通道后缀见 `wist-gateway` / `wist-agentd` 那类仓。）

**打 tag 即出可下载包**（`.github/workflows/release.yml`，tag `v*.*.*` 触发）：

1. bump `version.txt`（版本权威；gx 仓里就是 `gx adm v_patch` / `v_feat`）→ commit / push
2. 打 tag 并推送：`v<version>`（gx 仓里是 `gx adm v_tag`）

产物（GitHub Release 附件 + workflow artifact，保留 7 天）：

- `wist-knowledge-<version>.tar.gz` —— 顶层一层同名目录，内含五份数据 + `manifest.json`
  （`version` / `created_at` / `commit` / `content_versions` / 每份文件的 sha256）
- `wist-knowledge-<version>.tar.gz.sha256`
- `wist-knowledge-<version>.tar.gz.sig` —— **仅在 CI secret `KNOWLEDGE_SIGNING_KEY` 配了时**产出

### 签名（一把钥匙，与安装脚本那套同一简单度）

签的是 **sha256 摘要的十六进制文本**（与 `.sha256` 里那串同一段字节），Ed25519，base64 一行。
私钥**只在** CI secret `KNOWLEDGE_SIGNING_KEY`，不进仓、不进网关；网关侧只配公钥。

**当前生效的签名公钥就在本仓**：`keys/knowledge-signing.pub.pem`（公钥是公开信息）。
部署侧拿它去配网关（`[knowledge] signing_public_key_file`），任何人都能拿它**本地复核**一个包：

```bash
# 拿 release 附件与仓库里的公钥，手工验一遍（不依赖网关）。
# 注意 `tr -d '\n'`：签名时用的是 `printf '%s'`（**不带换行**），awk/echo 会多补一个换行就验不过了。
awk '{print $1}' wist-knowledge-<版本>.tar.gz.sha256 | tr -d '\n' > /tmp/msg
base64 -d < wist-knowledge-<版本>.tar.gz.sig > /tmp/sig.bin
openssl pkeyutl -verify -pubin -inkey keys/knowledge-signing.pub.pem \
  -rawin -in /tmp/msg -sigfile /tmp/sig.bin                            # → Signature Verified Successfully
```

换钥匙（很少发生）：重跑 `gen-signing-key.sh` → 私钥更新 secret → **新公钥入库替换 `keys/`** →
各网关换掉那份公钥文件并重启。**换锚要挨个动网关**，所以别轻易换。

```bash
./scripts/gen-signing-key.sh ./keys      # 只需一次：生成一对钥匙
#  私钥 → GitHub secret KNOWLEDGE_SIGNING_KEY（内容 = 整个 PEM）
#  公钥 → 入库为 keys/knowledge-signing.pub.pem（可公开）
#         部署侧拷成 <网关配置目录>/state/knowledge-signing.pub.pem，
#         并在 wist-gateway.toml 里写 [knowledge] signing_public_key_file = "state/knowledge-signing.pub.pem"
```

配了公钥的网关会**拒收未签名/验不过**的包；没配就只记 sha256。
私钥丢了 = 以后的新包都签不出来（要重生成并到**每台**网关换公钥）—— 所以把它存在只有发布流程能取到的地方。

本地预览与自测：`./scripts/package.sh --dry-run`（版本取自 `version.txt`；显式传 `--version` 必须与它
**完全相同**，否则拒掉——防“打了 tag 却忘了 bump”的漂移）。

为什么打成包、而不是让网关读本仓目录：形态对齐既有「Agent 安装包」——管理面录入 / 离线投放 /
版本历史 / 内容寻址。**网关侧的导入流程还没做**（生效版本指针、签名、schema 兼容校验、旧版共存），
见后续设计稿。
