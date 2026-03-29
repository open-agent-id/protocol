#!/bin/bash
set -euo pipefail

# ============================================================
# OAID 主网部署脚本
# ============================================================
#
# 你只需要填下面 2 个值，其他都已经配好了。
#
# ============================================================

# ────────────────────────────────────────────────────────────
# 【填这里】Deployer 私钥
#
# 这是谁？  就是你的 MetaMask 钱包 0x4079...eF3
# 怎么拿？  MetaMask → 账户详情 → 导出私钥
# 用途？    付 gas 部署合约（一次性的，部署完就没权限了）
# ────────────────────────────────────────────────────────────
export DEPLOYER_PRIVATE_KEY="填你的MetaMask私钥"

# ────────────────────────────────────────────────────────────
# 【填这里】Relayer 钱包地址
#
# 这是谁？  你刚才 cast wallet new 创建的新钱包
# 填什么？  填【地址】（0x开头，不是私钥！）
# 用途？    Registry Server 用来批量注册 agent 上链
# 注意：    私钥不填这里，以后配到服务器 .env 里
# ────────────────────────────────────────────────────────────
export RELAYER_ADDRESS="填cast wallet new输出的地址"

# ============================================================
# 以下不用改
# ============================================================

# Safe 多签地址（已创建）
export SAFE_A="0x14Fc953d3B2A5810E6dAd7aBe00dc6C9b55D21DE"   # 2/5 日常管理
export SAFE_B="0x0Af1C084C9F63F7c0b63B4e1ce19Ea8aD9d95272"   # 3/5 关键操作

# Base Mainnet USDC
export USDC_ADDRESS="0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"

# Base Mainnet RPC
RPC_URL="https://mainnet.base.org"

# ============================================================
# 预检查
# ============================================================
echo ""
echo "=== OAID 主网部署 ==="
echo ""

if [ "$DEPLOYER_PRIVATE_KEY" = "填你的MetaMask私钥" ]; then
    echo "❌ 请先编辑此脚本，填入 DEPLOYER_PRIVATE_KEY"
    echo "   MetaMask → 账户详情 → 导出私钥"
    exit 1
fi

if [ "$RELAYER_ADDRESS" = "填cast wallet new输出的地址" ]; then
    echo "❌ 请先编辑此脚本，填入 RELAYER_ADDRESS"
    echo "   就是你 cast wallet new 创建的那个新地址"
    exit 1
fi

DEPLOYER=$(~/.foundry/bin/cast wallet address "$DEPLOYER_PRIVATE_KEY" 2>/dev/null)
echo "Deployer (MetaMask):  $DEPLOYER"
echo "Relayer (新建钱包):    $RELAYER_ADDRESS"
echo "Safe A (2/5 日常):    $SAFE_A"
echo "Safe B (3/5 关键):    $SAFE_B"
echo "USDC:                 $USDC_ADDRESS"
echo ""

# 检查余额
BALANCE=$(~/.foundry/bin/cast balance "$DEPLOYER" --rpc-url "$RPC_URL" -e 2>/dev/null)
echo "Deployer 余额: $BALANCE ETH (Base)"
echo ""

echo "即将部署 5 个合约到 Base Mainnet，然后把管理权转给 Safe"
echo ""
read -p "确认部署? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "已取消"
    exit 0
fi

# ============================================================
# 部署
# ============================================================
echo ""
echo "正在部署..."
echo ""

~/.foundry/bin/forge script script/DeployMainnet.s.sol \
    --rpc-url "$RPC_URL" \
    --broadcast \
    --slow \
    -vvv

echo ""
echo "============================================================"
echo "  ✅ 部署完成！"
echo ""
echo "  接下来:"
echo ""
echo "  1. 去 app.safe.global 用 Safe A 发起两笔交易:"
echo "     a) 调用 AgentRegistry 的 acceptAdmin()"
echo "     b) 调用 TrustPayment 的 acceptAdmin()"
echo "     (需要 2 个钱包签名)"
echo ""
echo "  2. 记录上面输出的合约地址"
echo ""
echo "  3. ⚠️  立即删除此脚本中的私钥！"
echo "     运行: rm script/deploy-mainnet.sh"
echo "============================================================"
