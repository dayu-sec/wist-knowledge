# 更新日志

本文件记录 `wist-knowledge` 的所有重要变更。格式遵循 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)，
版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。

> 说明：自 0.1.5 起维护本文件。

## [0.5.5] - 2026-10-25

### 变更（面拆分：容器 stdout 独立成 `ContainerWorkload`）

- **新增面 `ContainerWorkload`**（Linux）：容器 stdout（13 business / 15 gateway / 16 k8s_pod）。
  两个容器单元 `linux-container-stdout` / `linux-docker-container-stdout` 从 `ComputeWorkload`
  迁入，并被 `linux-base` 基线包引用 —— **所有 Linux 模板（含 `LinuxHost`）都带上它**。
  以前它们只在 `linux-workload`（compute/data 模板）里，只跑业务容器的纯 Docker 主机
  **拿不到容器面**。
- **`ComputeWorkload` 回归「作业与加速卡」**（`slurm/*` + `dmesg:nvidia-xid`，仍是 `draft`）：
  展示名从「作业、加速卡与容器」改为「作业与加速卡」。
- **`purpose_version` 3 → 4**：**撤回** 0.5.4 加的 `dockerd` / `containerd` → `LinuxCompute` 判据。
  面拆分后不再需要，而且把业务容器主机标成“计算节点”本身是错的。
- `catalog_version` 12 → 13。

### 升级注意

- 本包要求**网关 ≥ 0.20.5-alpha**（面词表加了一项）。
- ⚠ **已授权 `ComputeWorkload` 的站点：那台机的容器采集会停** —— 单元已经属于新面，
  旧授权里没有它。激活后需要**重新授权 `ContainerWorkload`**（或整机重新授权）。
  这是本次升级唯一的操作步骤。
- 激活后 `catalog_version = 13`、`purpose_version = 4` 可确认新包生效。

## [0.5.4] - 2026-10-24

### 新增

- **容器主机的用途规则**（`purpose_version` 2 → 3）：新增 `dockerd` / `containerd` 两条
  `LinuxCompute` 判据（各 15 分）。以前一台**只跑业务容器**的机器（无 k8s、无数据库守护进程）
  一条规则都不命中 → 落 `LinuxHost` 基线 → 而 `linux-host` 模板不带 `linux-workload` →
  容器 stdout 单元**根本派不到**。权重压在 40 以下：同机跑数据库时仍归 `LinuxData`
  （它的模板本来就包含 `linux-workload`），不会被抢成计算类。

### 变更

- `linux-docker-container-stdout` 的注释补上**已知限制**：`not_path_exists` 是整机级开关。
  `k8s(containerd) + 独立 dockerd` 的混跑主机、以及 `/var/log/containers` 残留目录的主机，
  会少采 / 不采 docker 容器 stdout。逃生口：人工授权直接点名该单元
  （`spec=linux-docker-container-stdout`，不再保证去重）。
- 目录注释订正：`match` 可用 kind 补上 `not_path_exists`；`FileGlob` 是**任意层** glob
  （`*` 不跨目录、`**` 不支持）；容器身份已进帧（M1），不再是“等帧字段落地”。

### 升级注意

- 本包要求**网关 ≥ 0.20.3-alpha**：不认识 `not_path_exists` 的旧网关会把 docker 单元
  整条不展开（保守，不会重采）。对 agentd 的要求不变（该单元只需按 glob 读文件）。
- 已激活过知识包的站点：录入并激活 0.5.4 后**重新授权**一次，用途建议与模板展开才会用新规则。
  `catalog_version` 保持 12（单元内容未变），可以用 `purpose_version = 3` 确认新包生效。

## [0.5.3] - 2026-10-24

### 变更

- **`linux-docker-container-stdout` 加否定条件**：
  `match = "path_exists:/var/lib/docker/containers;not_path_exists:/var/log/containers"`。
  `k8s + cri-dockerd` 的主机上 kubelet 把 pod 日志路径指向 docker 的 json 文件，两个容器单元
  会同时命中 → 同一份日志采两遍。现在有 `/var/log/containers` 的机器交给
  `linux-container-stdout`，docker 单元不再展开。
- `catalog_version` 11 → 12（目录 / 包 / 模板同步）。

### 升级注意

- **旧网关不认识 `not_path_exists:`** → 该单元整条不展开（保守：不会重复采，但纯 Docker
  主机上容器 stdout 会暂时采不到）。所以升级顺序是 **网关 → agentd → 知识库包**，
  与之前一致。
- ⚠ **重新授权前先确认 agent 已探测过 `/var/log/containers`**：否定条件靠三态求值，
  “没探过”等于“无法判定”。这条路径从 0.5.1 的 k8s 单元起就在探测白名单里，
  所以通常升级后直接重新授权即可；如果刚升级完 agent，先等一轮策略拉取（≤ 5 分钟）
  并把 `probed_paths` 确认下来—— spec 在**授权那一刻**固化，缺了就得再授权一次。

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
