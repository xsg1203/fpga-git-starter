#!/usr/bin/env bash
# 推送到 GitHub
#
#   ./scripts/push.sh                 默认走 SSH（推荐）
#   ./scripts/push.sh --https         临时改用 HTTPS 推送
#   ./scripts/push.sh --https --insecure-tls
#                                     本机 schannel 取不到证书吊销列表时，HTTPS 才需要
#
# 为什么默认 SSH：
#   本机 22 端口被运营商/防火墙拒绝（Connection refused），因此 ~/.ssh/config 里
#   把 github.com 指向了官方 443 接入点 ssh.github.com:443。
#   SSH 不走 TLS 握手，天然规避 Windows schannel 的
#   CRYPT_E_NO_REVOCATION_CHECK (0x80092012) 问题。

set -euo pipefail

MODE="ssh"
INSECURE=0
for a in "$@"; do
    case "$a" in
        --https) MODE="https" ;;
        --insecure-tls) INSECURE=1 ;;
        *) echo "未知参数：$a"; echo "用法：$0 [--https [--insecure-tls]]"; exit 1 ;;
    esac
done

SSH_URL="git@github.com:xsg1203/fpga-git-starter.git"
HTTPS_URL="https://github.com/xsg1203/fpga-git-starter.git"

if [ "$MODE" = "ssh" ]; then
    URL="$SSH_URL"
    # 预检：SSH 认证不通就直接报错，不用等 git 超时。
    # 注意 GitHub 的 ssh -T 认证成功时退出码是 1（不开 shell），故不能只看退出码。
    OUT="$(ssh -T -o BatchMode=yes -o ConnectTimeout=10 git@github.com 2>&1 || true)"
    if ! printf '%s' "$OUT" | grep -q "successfully authenticated"; then
        echo "[错误] SSH 认证失败："
        printf '%s\n' "$OUT" | head -3
        echo "       检查 ~/.ssh/id_ed25519_github 是否已添加到 GitHub，"
        echo "       以及 ~/.ssh/config 中 github.com 是否指向 ssh.github.com:443。"
        exit 1
    fi
    echo "[SSH] $(printf '%s' "$OUT" | head -1)"
else
    URL="$HTTPS_URL"
    if [ "$INSECURE" = "1" ]; then
        export GIT_SSL_NO_VERIFY=1
        echo "[警告] 已关闭 TLS 证书校验，仅限本机调试使用"
    fi
fi

if [ "$MODE" = "ssh" ]; then
    # origin 本身即 SSH 地址，用 remote 名推送可同时刷新 origin/main 追踪引用
    echo "[推送] origin ($URL)"
    git push origin main
    git push origin --tags
else
    echo "[推送] $URL"
    git push "$URL" main
    git push "$URL" --tags
fi
echo "[完成] 已推送 main 与全部 tag"
