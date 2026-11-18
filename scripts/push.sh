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
    # 预检：SSH 认证不通就直接报错，不用等 git 超时
    if ! ssh -T -o BatchMode=yes -o ConnectTimeout=10 git@github.com >/dev/null 2>&1; then
        # GitHub 认证成功时返回 1（不支持 shell），连接失败才需要真的退出
        if ! ssh -o BatchMode=yes -o ConnectTimeout=10 git@github.com 2>&1 | grep -q "successfully authenticated"; then
            echo "[错误] SSH 认证失败。检查 ~/.ssh/id_ed25519_github 是否已添加到 GitHub，"
            echo "       以及 ~/.ssh/config 中 github.com 是否指向 ssh.github.com:443。"
            exit 1
        fi
    fi
else
    URL="$HTTPS_URL"
    if [ "$INSECURE" = "1" ]; then
        export GIT_SSL_NO_VERIFY=1
        echo "[警告] 已关闭 TLS 证书校验，仅限本机调试使用"
    fi
fi

echo "[推送] $URL"
git push "$URL" main
git push "$URL" --tags
echo "[完成] 已推送 main 与全部 tag"
