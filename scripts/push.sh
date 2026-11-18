#!/usr/bin/env bash
# 推送到 GitHub
#
#   ./scripts/push.sh                 正常推送
#   ./scripts/push.sh --insecure-tls  本机 schannel 无法访问证书吊销服务器时使用
#
# 背景：部分 Windows 环境下 schannel 因取不到 CRL/OCSP 而报
#   CRYPT_E_NO_REVOCATION_CHECK (0x80092012)
# 此时可加 --insecure-tls 临时关闭证书校验。安全的长期解法是给 git 配一份
# ca-bundle.crt 并改用 openssl 后端，或用官方 Git for Windows 安装包。

set -euo pipefail

if [ "${1:-}" = "--insecure-tls" ]; then
    export GIT_SSL_NO_VERIFY=1
    echo "[警告] 已关闭 TLS 证书校验，仅限本机调试使用"
fi

git push origin main
git push origin --tags
echo "[完成] 已推送 main 与全部 tag"
