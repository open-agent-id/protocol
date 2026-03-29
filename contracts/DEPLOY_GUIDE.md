# OAID 主网部署指南

## 你需要的东西

```
角色图：

┌──────────────────┐
│  Deployer        │ ← 你的 MetaMask 钱包 (0x4079...eF3)
│  (一次性)         │    付 gas 部署合约，部署完就没权限了
│  需要: 私钥       │    已有 0.006 ETH 在 Base 上 ✅
└──────────────────┘

┌──────────────────┐
│  Relayer         │ ← 你用 cast wallet new 创建的新钱包
│  (长期运行)       │    给 Registry Server 用，自动批量上链
│  需要: 地址+私钥  │    以后充 0.001 ETH 就够（现在不急）
└──────────────────┘

┌──────────────────┐
│  Safe A (2/5)    │ ← 已创建 ✅ 0x14Fc...21DE
│  (日常管理)       │    管 Registry admin + TrustPayment admin
└──────────────────┘

┌──────────────────┐
│  Safe B (3/5)    │ ← 已创建 ✅ 0x0Af1...5272
│  (关键操作)       │    管 Beacon owner（钱包代码升级）
└──────────────────┘
```

## 第 1 步：编辑部署脚本

```bash
cd protocol/contracts
nano script/deploy-mainnet.sh
```

填 2 个值：

| 变量 | 填什么 | 怎么拿 |
|------|--------|--------|
| `DEPLOYER_PRIVATE_KEY` | MetaMask 的**私钥** | MetaMask → 点头像 → 账户详情 → 显示私钥 |
| `RELAYER_ADDRESS` | 新钱包的**地址** | cast wallet new 输出的 Address（不是私钥！） |

## 第 2 步：运行部署

```bash
bash script/deploy-mainnet.sh
```

脚本会：
1. 检查你的余额够不够
2. 让你确认（y/n）
3. 部署 5 个合约
4. 自动把管理权转给 Safe

部署大约 1-2 分钟。

## 第 3 步：Safe 接受管理权

部署脚本只是**发起**了转移，Safe 还需要**接受**。

1. 打开 https://app.safe.global
2. 连接钱包，选 Safe A (`0x14Fc...21DE`)
3. New Transaction → Transaction Builder
4. 第一笔：
   - To: `<脚本输出的 AgentRegistry 地址>`
   - ABI: 输入 `acceptAdmin()`
   - 提交
5. 第二笔：
   - To: `<脚本输出的 TrustPayment 地址>`
   - ABI: 输入 `acceptAdmin()`
   - 提交
6. 用 2 个钱包签名确认

## 第 4 步：记录合约地址

部署脚本会输出类似：

```
[1/6] AgentWallet implementation:  0xAAAA...
[2/6] UpgradeableBeacon:           0xBBBB...
[3/6] AgentWalletFactory:          0xCCCC...
      WALLET_BYTECODE_HASH:        0xDDDD...
[4/6] AgentRegistry:               0xEEEE...
[5/6] TrustPayment:                0xFFFF...
```

把这些地址记下来，下一步配置服务器要用。

## 第 5 步：删除私钥

```bash
rm script/deploy-mainnet.sh
```

⚠️ **部署完立即删除脚本**，里面有你的私钥。

## 第 6 步：配置 Registry Server

把新合约地址更新到服务器 `.env`：

```env
DEFAULT_CHAIN=base
CHAIN_RPC_URL=https://mainnet.base.org   # 或 Alchemy RPC
FACTORY_ADDRESS=<第3步的 AgentWalletFactory 地址>
WALLET_BYTECODE_HASH=<第3步的 WALLET_BYTECODE_HASH>
REGISTRY_CONTRACT_ADDRESS=<第4步的 AgentRegistry 地址>
TRUST_PAYMENT_ADDRESS=<第5步的 TrustPayment 地址>
USDC_ADDRESS=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
RELAYER_PRIVATE_KEY=<cast wallet new 的私钥>
```

## 第 7 步：给 Relayer 充 ETH

Relayer 钱包需要少量 ETH 付 gas（批量注册上链用）：
- 从 MetaMask 发 0.001 ETH 到 Relayer 地址（Base 网络）
- 够用很久（100 万 agent 才花 $100 gas）

## 完成！

```
部署完的状态：

Internet → Cloudflare → VPS (Registry Server)
                              │
                              ├─ Neon (数据库)
                              ├─ Base Mainnet (合约)
                              │   ├─ AgentRegistry (admin = Safe A)
                              │   ├─ TrustPayment (admin = Safe A)
                              │   ├─ UpgradeableBeacon (owner = Safe B)
                              │   ├─ AgentWalletFactory
                              │   └─ AgentWallet (implementation)
                              └─ Relayer 钱包 (自动批量上链)
```
