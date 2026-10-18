# 更新日志

本文件记录 `wist-knowledge` 的所有重要变更。格式遵循 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)，
版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。

> 说明：自 0.1.5 起维护本文件。

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
