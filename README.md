# CT-EBAZ4205 · ZYNQ-7010 多运动目标颜色识别与追踪系统

基于 EBAZ4205（XC7Z010-1CLG400I）+ 教学扩展板 + OV5640 + VGA，**纯 PL 逻辑**实现的多运动目标检测与颜色识别追踪系统。

## 功能

- OV5640 实时采集 640×480@30fps（DVP + SCCB，开启 AWB/AEC）
- 4×4 块级运动检测（帧差）+ 五色分类（红/绿/蓝/黄/紫）+ 块内投票降噪
- 块级单遍连通域标记（并查集），可分离**同色多目标**
- 同屏最多 16 个目标，框色 = 目标颜色，带目标 ID
- 单色持续追踪（质心匹配 + 丢失保持 0.5s）
- 按键控制：key1/key2 切换追踪颜色、key3 单色追踪开关、key4 五色全框选开关
- VGA 640×480@60 叠加显示 + OSD（图例/模式/ID/帧率）

## 目录

```
docs/       需求规格书、架构、接口表、测试报告
rtl/        RTL 源码（按 ov5640 / imgproc / video / ctrl 分层）
sim/        testbench 与图像激励
constr/     XDC 约束
scripts/    建工程、综合、仿真脚本
```

## 文档

- [01 需求规格书](docs/01_需求规格书.md)
- [02 架构与模块划分](docs/02_架构与模块划分.md)
- [03 上板调试记录](docs/03_上板调试记录.md)
- [04 Git 版本回档手册](docs/04_Git版本回档手册.md)

## 环境

Vivado 2017.4，Part `xc7z010clg400-1`，PL 时钟 50MHz（N18）。

## 仓库

- 远端：<https://github.com/xsg1203/fpga-git-starter>
- SSH：`git@github.com:xsg1203/fpga-git-starter.git`（**推荐**，origin 已配置为此地址）
- 推送：`./scripts/push.sh`
- HTTPS 备用：`./scripts/push.sh --https`；若本机 TLS 取不到吊销列表再加 `--insecure-tls`

### 为什么用 SSH

本机 22 端口被拒（`Connection refused`），`~/.ssh/config` 已将 `github.com` 指向 GitHub 官方 443 接入点：

```
Host github.com
    HostName ssh.github.com
    Port 443
    User git
    IdentityFile ~/.ssh/id_ed25519_github
    IdentitiesOnly yes
```

SSH 不经过 TLS 握手，因此不会触发 Windows schannel 的 `CRYPT_E_NO_REVOCATION_CHECK (0x80092012)`；同时也免去了每次推送输入 PAT。验证命令：`ssh -T git@github.com`，应返回 `Hi xsg1203!`。

## 版本策略

每个里程碑一个 commit + tag，详见需求规格书 §8。

| tag | 内容 |
|---|---|
| `v0.1-spec` | 需求规格书、工程骨架 |
| `v0.2-m2` | 架构文档 + M2 采集直显（OV5640 → 320×240 帧缓存 → VGA） |

回档到某个里程碑：`git checkout v0.2-m2`（或 `git switch -c tmp v0.2-m2` 另开分支查看）。
