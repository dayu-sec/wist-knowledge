#!/usr/bin/env bash
# 一次性生成知识库内容包的**签名密钥对**（Ed25519）——一把，不做多密钥共存。
#
# 与安装脚本那把签名的关系：**方向相反**，所以是**另一把**钥匙。
#   安装脚本：网关**签**、目标主机验（私钥在网关、公钥下发）；
#   内容包：  发布侧**签**、网关验（私钥在发布 CI、公钥进网关配置）。
#
# 用法：
#   ./scripts/gen-signing-key.sh [输出目录（默认 .）]
#
# 产物：
#   knowledge-signing.pkcs8.pem   私钥 → 放进 wist-knowledge 仓的 CI secret `KNOWLEDGE_SIGNING_KEY`
#   knowledge-signing.pub.pem     公钥 → 可公开；部署侧拷到网关配置目录，并在配置里指它
#
# ⚠️ 在**可信且离线**的机器上跑；私钥别入库、别贴进聊天工具、别放到被管机器上。
#    私钥丢了 = 以后的内容包都签不出来（要重新生成并到每台网关换公钥）。
set -euo pipefail

OUT="${1:-.}"
mkdir -p "${OUT}"
command -v openssl >/dev/null 2>&1 || { echo "需要 openssl" >&2; exit 1; }

openssl genpkey -algorithm ed25519 -out "${OUT}/knowledge-signing.pkcs8.pem"
openssl pkey -in "${OUT}/knowledge-signing.pkcs8.pem" \
  -pubout -out "${OUT}/knowledge-signing.pub.pem"
chmod 600 "${OUT}/knowledge-signing.pkcs8.pem"

echo "私钥 → ${OUT}/knowledge-signing.pkcs8.pem"
echo "        放进 GitHub secret：Settings → Secrets → Actions → 新建 KNOWLEDGE_SIGNING_KEY（内容=整个 PEM）"
echo "公钥 → ${OUT}/knowledge-signing.pub.pem"
echo "        可入库/可公开；部署侧拷成 <网关配置目录>/state/knowledge-signing.pub.pem，"
echo "        并在 wist-gateway.toml 里写 [knowledge] signing_public_key_file = \"state/knowledge-signing.pub.pem\""
