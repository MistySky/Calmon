# 代码签名与日历授权继承（自签名）

## 1. 问题

此前应用为 **ad-hoc 签名**（`Signature=adhoc`、`TeamIdentifier=not set`）。ad-hoc 没有证书，macOS 隐私（TCC）只能用**二进制哈希 cdhash** 作为身份：

```
designated => cdhash H"a0b1f347…"
```

每次重新构建/发版，二进制变化导致 cdhash 变化，系统视作一个**全新应用**，于是日历授权每次升级都被重新询问。

## 2. 方案：自签名代码签名证书

生成并使用一张自签名代码签名证书 **`CalMon Self-Signed`**，让应用的代码要求基于**证书**而非 cdhash，从而跨版本稳定、授权可复用。

- 证书 SHA-1：`349E8A9EA8645DFEFC587EF5DDAA1FB23B447473`
- 证书 SHA-256：`7CAEBCEBC45203924E7306E92EABDB93A826A9494C352D105FBC40A4E65D9F5C`
- 私钥只存在于构建机（本机登录钥匙串），DMG 仅含公钥/证书。

### 生成与导入（构建机一次性）

```sh
openssl req -x509 -newkey rsa:2048 -nodes -keyout calmon.key -out calmon.crt -days 3650 \
  -subj "/CN=CalMon Self-Signed" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false"
security import calmon.crt -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign -T /usr/bin/security
security import calmon.key -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign -T /usr/bin/security
```

### 工程接线

`CalMon.xcodeproj` 的应用 target（Debug 与 Release）：
`CODE_SIGN_IDENTITY = "CalMon Self-Signed"`，`CODE_SIGN_STYLE = Manual`，Debug 关闭 Hardened Runtime、Release 启用。测试 target 仍用 `-`（ad-hoc）。

### 结果

```
$ codesign -dv -r- build/Build/Products/Release/CalMon.app
flags=0x10000(runtime)
designated => identifier "com.calmon.CalMon" and certificate leaf = H"349e8a9ea8645dfefc587ef5ddaa1fb23b447473"
```

代码要求由证书决定，**跨版本不变**：首次授权后，覆盖升级（同一证书签名的 1.4、1.5…）应复用同一 TCC 记录，不再重复请求日历权限。entitlements 不变（`app-sandbox=false`、`personal-information.calendars=true`）。

## 3. 限制与注意

- **证书未被系统信任**（`CSSMERR_TP_NOT_TRUSTED`）。因此 Gatekeeper 首次打开仍可能提示“无法验证开发者”；右键 → 打开，或 `xattr -dr com.apple.quarantine /Applications/CalMon.app`。这不是授权问题，是分发信任问题。
- 应用**未公证**（无 Developer ID）。要同时消除 Gatekeeper 提示需 Apple Developer ID + 公证。
- 自签名身份只对本机/本钥匙串有意义；换机器构建需重新生成并导入证书（届时是新的证书身份，授权需重新授予一次）。
- 私钥不要外泄或提交仓库；本仓库不包含 `calmon.key` / `calmon.crt`。
- ad-hoc 的旧版（≤1.3）与本证书签名的版本属于**不同身份**，从旧版升级到 1.4 会重新授权一次；此后从 1.4 起再升级应复用。

## 4. 验证

- `codesign -dv -r-` 显示基于证书的 designated requirement（见上），Hardened Runtime 存在，entitlements 完整。
- 74/74 测试通过；Debug/Release 均构建成功，无 Swift 警告。
- **已由用户实机确认（2026-09-16）**：用户将 1.4 升级到 1.5（`brew upgrade --cask mistysky/cnapps/calmon`），设置 → 系统日历权限仍显示“已授权”，**未再弹出日历授权请求**，节日读取正常。即稳定自签名身份在本机实现了跨版本授权继承。（此前 ad-hoc 的 1.2/1.3 → 1.4 会重授一次，属身份切换；自 1.4 起继承生效。）
