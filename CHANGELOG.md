# 更新日志

本文件记录 `wist-knowledge` 的所有重要变更。格式遵循 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)，
版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。

> 说明：自 0.1.5 起维护本文件。

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
