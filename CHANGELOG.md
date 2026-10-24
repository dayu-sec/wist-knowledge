# 更新日志

本文件记录 `wist-knowledge` 的所有重要变更。格式遵循 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)，
版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。

> 说明：自 0.1.5 起维护本文件。

## [0.5.2] - 2026-10-24

### 新增

- **`linux-docker-container-stdout`（ComputeWorkload，`active`）**：纯 Docker 主机（没有 kubelet）
  的容器 stdout。来源 `/var/lib/docker/containers/*/*-json.log*`，
  `match = path_exists:/var/lib/docker/containers`，`requires_privilege = root`。
  与 `linux-container-stdout` 是**两个载体、同一批语义**（13/15/16 仍是同一类，归类在数据面）。

  **正文原样**：这里不解析 docker 的 JSON 信封（`{"log":…,"stream":…,"time":…}`），
  解码归数据面（与 CRI 头同一层）。所以本单元**不需要新读法、也不需要新能力轴**，
  旧 agentd 照样能执行 —— 代价是正文暂时是原始 JSON 行，等数据面规则落地才好看。

- `catalog_version` 10 → 11（目录 / 包 / 模板同步）；`linux-workload` 包加入该单元。

### 升级注意

- ⚠ **k8s + cri-dockerd 的主机会重复采集**：那类机器上 kubelet 的 pod 日志路径指向 docker
  的 json 文件，两个单元的 `match` 会同时命中。否定条件（`not_path_exists:`）落地前，
  这类集群先不要把机器纳入 `linux-workload` 包。纯 Docker 主机（无 kubelet）不受影响。
- 日志量取决于容器数量与活跃度；单轮读取量仍受 `max_read_bytes_per_tick` 限制，
  首次授权从 `tail` 开始（不回放历史）。

## [0.5.1] - 2026-10-24

### 新增 / 变更（§6.6 G2 + G3）

- **新增 `linux-container-stdout`（ComputeWorkload，`active`）**：来源 `/var/log/containers/*.log`，
  `match = path_exists:/var/log/containers`。13 business / 15 gateway / 16 k8s_pod 是**同一批
  容器 stdout** 的三种归类 —— 只建一个单元（拆两条 active 会重复采，G5），归类在数据面按正文分派。
  `filters` 默认留空（= 全采）：namespace 白名单是部署结论，需要时改这一条来源即可。
- **`linux-compute-workload` 去掉 `/var/log/pods/*`**：旧形态与容器单元重叠，且 `0.log` / `1.log`
  与轮转产物在同一目录（D4）。仍保持 `draft`（slurm / nvidia 面未验收）。
- **`linux-db-service` 翻 `active`（W4）**：Postgres csvlog（`/var/log/postgresql/*.csv`，
  `multiline = "postgres_csv"`）与 MySQL slow log（`/var/log/mysql/*slow*.log`，
  `multiline = "mysql_slow"`）。删掉旧的全目录 glob（会与上面两条重叠）。
  事实门从 `installed:*` 改为 `path_exists:/var/log/{postgresql,mysql,redis,mongodb}`：
  包清单探针还没实现（`packages` 恒空），用 `installed:` 会让这个面永远展不开。
  redis / mongodb 来源收窄到 `*.log`（不把轮转产物当新文件重读）。
- **`auth.log` / `secure` 配 `drop_if_contains`**：`pam_unix(cron:session)`、`systemd-logind`、
  `pam_unix(systemd-user:session)`（§6 W4 指定）。
- `catalog_version` 9 → 10（目录 / 包 / 模板同步）；`linux-workload` 包加入容器单元。

### 升级提示

- 现场滚动顺序：**contracts → 网关 → agentd → web → 本目录包**。
  - 老网关收到新 agentd 的能力上报会 `deny_unknown_fields` **整份拒收**，所以网关先升；
  - `drop_if_contains` 是**减法**：agent 不支持或没报能力时，网关**去掉这个字段继续采**
    （auth 仍然可用，只是噪音行会上送；不会再出现整份 spec 拒收）；
  - `filters` 与新**读法**不同：前者不支持就裁源（范围结论不能被忽略），后者不支持时旧
    agent 会按“一行一条”读（csvlog / slow 记录会被切碎）；旧**网关**不认识新读法会整份目录拒载。
  - 所以推荐的机队前置是 agentd ≥ 0.9.1；至少要 0.9.0-alpha（上报能力）。目录包最后发。
- `systemd-logind` 子串会连带丢掉“New session …”这类会话事件（子串过滤分不出噪音与正事）。
  若现场需要保留会话事件，把这条换成更长的子串（如 `systemd-logind: New seat`）。

## [0.5.0] - 2026-10-23

### 变更

- **内核日志（`KernelSystem`）改为 journald 唯一来源**：`linux-kernel-system` 的来源从
  `/var/log/kern.log` + `/var/log/messages` 改为 `Exporter journalctl-kernel`
  （`journalctl -k -p 4 -o json`，采集端靠游标续读，周期 60s）。
  理由：文件是 rsyslog 的派生副本，**没有 `PRIORITY` / `_TRANSPORT`**，保留期也和 journal
  不同步；两个源并存必然重复 + 漂移，不存在稳定的“优先”中间态。
- **`match = "path_exists:/run/systemd/journal"`**：非 systemd 主机上该面不展开（不派空活），
  **不做文件回退**。
- `catalog_version` 8 → 9（目录 / 包 / 模板同步）。

### 升级提示

- ⚠ **发布顺序：contracts → agentd → 网关 → 本目录包**。
  - 旧 agentd 不认识 `journalctl-kernel`，会把该单元如实报 `unsupported`（不静默）；
  - 旧网关不认识这个 ID，会把「`active` 但无可执行来源」当成装载错误 —— **整份目录加载失败**，
    所以不要在网关升级前把这份包推下去。
- 升级后首轮会回看最近 5 分钟（首个游标），之后按游标续读。游标被 journal vacuum 后
  journalctl **不会报错**（实测 systemd 259，会静默从起点重读）；agentd 在带游标**超时**时
  会清掉游标、下一轮从 `--since` 重读（`event=ExporterCursorReset`）。

## [0.4.0] - 2026-10-22

### 变更

- **`linux-auditd-exec` → `linux-audit-log`**：来源从导出器 `auditd-execve` 换成整文件
  `/var/log/audit/audit.log`（`match = "path_exists:/var/log/audit/audit.log"`）。
  8 个 `host_audit_*` 由数据面按 `type=` 分派，采集端不按 type 丢行；避免同一批 EXECVE
  从文件和 `ausearch` 两路重复。`auditd-execve` 导出器 ID 仍保留在词表，但目录不再引用。
- **`linux-auth-session` 增加 `path_exists:/var/log/auth.log|/var/log/secure` 门控**：
  两条路径都不存在的机器不再派空活；单条不存在的路径由网关派活时按探测事实裁掉。
- `catalog_version` 7 → 8（目录 / 包 / 模板同步）。

### 升级提示

- 建议先升级到带「按探测事实裁剪来源」的网关；旧网关仍会把不存在的路径当来源下发，
  该 input 每轮报一次 `ProcessingFailed`（不丢数据，但会持续报错）。
- 旧 agentd 不受影响：`audit.log` 是显式路径，`FileGlob` 本来就能 tail。

## [0.3.0] - 2026-10-18

### 变更

- **`linux-privilege-exec` 拆成两个采集单元**（同一 `PrivilegeExecution` 面）：
  - `linux-sudo-log`：来源 `/var/log/sudo.log`，`match = "path_exists:/var/log/sudo.log"`。
    RHEL 系默认有这个文件，Debian 系需要 sudoers 里配 `logfile` —— 没有就不派，
    避免「已授权却什么都没采到」。
  - `linux-auditd-exec`：来源是导出器 `auditd-execve`，`match = ""`（导出器自己处理没装的情况）。
    之前这两个来源混在同一个单元里，`match` 只能全有或全无。

- **采集单元开始使用 `path_exists` 三态门控**：`match` 可用 `path_exists:<绝对路径>`，
  探测范围由本文件的 `path_exists` 条件推导（网关下发给 agentd 实探）。
  「没探测过」（无法判定）与「探测过不存在」（不满足）从此可区分。

- `catalog_version` 6 → 7（目录 / 包 / 模板同步）。

### 升级提示

- **需要先升级网关（≥ 0.14.0）与 agentd（≥ 0.5.0）**：旧网关不认 `path_exists` 条件
  （装载即拒），旧 agentd 不会探路径 —— 那时该单元会永远停在「无法判定」。
  顺序：网关 → agentd → 本包 → 激活。

## [0.2.0] - 2026-10-18

### 新增

- **采集面词表入目录（`[[families]]`）**：18 个面的 `id` / `platforms` / 中英文名称与说明。
  网关从包里装载词表，**新增采集面只改这里、不再发网关**；文案改动同样不发版。
  `catalog_version` 5 → 6（目录 / 包 / 模板同步）。

### 升级提示

- **本版起需要先升级网关（≥ 0.13.0）**：旧网关的目录结构是 `deny_unknown_fields`，
  遇到 `[[families]]` 会拒载整包。顺序：网关 → 本包 → 激活。

## [0.1.6] - 2026-10-14

### 变更

- **制品推送到 COS 时自带 sha256**：上传的每个对象带自定义元数据 `x-cos-meta-artifact-sha256`
  （COS 只存 MD5 ETag，GitHub 资产摘要过不来）；可用 `coscli stat`（HEAD）读回。`x-cos-meta-`
  是 COS 对自定义元数据的强制前缀。

## [0.1.5] - 2026-10-13

### 变更

- **发布时可选把制品推送到腾讯云 COS**：打 tag 时新增 `upload-cos` job，把 `dist/*` 制品上传到
  `cos://<桶>/wist-knowledge/<tag>/` 与 `.../latest/`（未配置 `COS_BUCKET` 时自动跳过，不影响发布）。
