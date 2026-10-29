# 时尚百货城 · iOS IPA（GitHub Actions 构建）

Windows 无法编译 iOS（必须 macOS + Xcode），所以用 **GitHub Actions 的 macos-15 机器**构建。
仓库里只有壳工程（几十 KB，纯 Swift），**游戏资源不进 git**——资源由你上传到一个 Release，构建时由 Actions 下载合并后打进 App。

> ⚠️ **资源必须用原图**（`www_orig.tar`，2.2G）。服务器 `/www/wwwroot/dl/www.tar`（1.4G）是 pngquant 压过的版本，
> 透明通道被破坏，iOS 会像之前 Android 一样**画面白屏/白边**。已为你重新生成原图包，别用那个 1.4G 的。

---

## 零、为什么资源要分块

- 游戏服务器出网只有 ~12KB/s，GitHub 的美国构建机**根本拉不动**任何来自该服务器的资源。
- GitHub 单文件上限 2GB，且 Actions artifact 存储对免费账户很小。
- 所以：资源在你本地切成 **95MB** 小块 → 上传到 Release `assets-v1`（或仓库 `assets/` 目录）→ Actions 下载后 `cat` 合并 → 同样把成品 IPA 切块上传到 Release `ipa-v1`。
- 为什么是 95MB：GitHub 对 **git 里的单个文件有 100MB 硬红线**，超过会被拒绝；95MB 既能走 Release 拖拽上传，也能走 git push，两边都不踩线。

---

## 一、建仓库并推壳工程

### ⚠️ 强烈建议：单独新建一个空仓库，不要复用已有仓库

GitHub 免费账号可以建**无限个**仓库。如果你已有仓库里放了别的游戏的东西（例如
`game_web.tar.part.*`、`gameos_repo_v1.2.1`、另一份 `ios_un-signed.yml`），**不要往里塞本工程**，原因：

1. 仓库里已有几 G 的分块文件，Actions 每次 checkout 都要把它们全拉下来 → 极慢甚至超时
2. 两份 workflow 并存，容易搞混跑错
3. 仓库体积暴增，后续 clone / push 都很痛苦

→ 新建空仓库 `shiguang-ios`（Private 即可），只放本工程的 `ios/` + `.github/`，干干净净。

推上去两种方式任选：

**方式 A（有 git 的机器上执行）：**
```bash
cd 本目录
git init
git add ios .github README.md
git commit -m "ios shell: 时尚百货城"
git branch -M main
git remote add origin git@github.com:<你的账号>/<仓库名>.git
git push -u origin main
```

**方式 B（无需 git，网页拖拽）：**
在空仓库页面点 **uploading an existing file**，把本目录下的 `ios/` 和 `.github/` 两个文件夹整体拖进去提交。
（注意 `.github` 是隐藏目录，拖拽时确认它被带上，否则 Actions 不会触发。）

---

## 二、上传资源分块到 Release `assets-v1`

资源包已在本机：`E:\WorkBuddy\2026-10-29-app\out\www.tar`（**原图，2.2G**）。
已切成小块：`E:\WorkBuddy\2026-10-29-app\out\www_chunks\www.tar.00` … `www.tar.23`（**共 24 块**，95MB×23 + 末块 58MB）

**任选一种上传方式**（workflow 两种都支持，会自动识别）：

**方式 A：Release（推荐，不占 git 仓库体积）**
```bash
gh release create assets-v1 E:\WorkBuddy\2026-10-29-app\out\www_chunks\www.tar.* \
  --title "Game assets" --notes "raw assets chunks"
```
没有 `gh` 就在 GitHub 网页：Releases → **Create a new release** → tag 填 `assets-v1` → 把 `www_chunks` 里 24 个文件拖进去 → Publish release。

**方式 B：直接放仓库 `assets/` 目录**
用网页 Add file 或 git 把 24 个块上传到仓库根目录的 `assets/` 文件夹下（文件名保持 `www.tar.00`…`www.tar.23` 不变）。95MB 未超 git 100MB 红线，可直接 push。

---

## 三、跑构建

推完壳工程 + 传完资源块后，**手动触发**（workflow 已改成只手动触发，避免你上传分块时每次 push 都启动一次 macOS 构建白烧额度）：

`Actions` → `Build iOS IPA` → `Run workflow` → 选 `main` 分支 → 绿色按钮确认

流程会自动：
1. 装 xcodegen，生成 `Shell.xcodeproj`
2. 从 Release `assets-v1` 下载所有 `www.tar.*` 分块 → `cat` 合并 → 解压到 `ios/Shell/www`
3. `xcodebuild` 无签名编译（Release / iphoneos，约 20-40 分钟）
4. 打成 `Shiguang-unsigned.ipa`，切成 200MB 块上传到 Release `ipa-v1`

---

## 四、取回 IPA

到 Release **`ipa-v1`** 下载全部 `Shiguang-unsigned.ipa.*` 分块，合并：

```bash
# Mac / Linux
cat Shiguang-unsigned.ipa.* > Shiguang-unsigned.ipa
```
```powershell
# Windows (PowerShell)
cmd /c copy /b Shiguang-unsigned.ipa.* Shiguang-unsigned.ipa
```

合并后的 `.ipa` 就是成品，可直接拿去网盘分发（和 APK 一样）。

---

## 五、安装到 iPhone

产物是**未签名 IPA**，iPhone 不能直接装，需签名（任选其一）：

| 方式 | 说明 |
|---|---|
| Sideloadly / AltStore | 用自己的 Apple ID 免费签名，7 天有效，可续签 |
| 爱思助手 / 沙漏 | 一键 IPA 签名后安装（免费证书 7 天） |
| 企业证书 / 超级签 | 商用分发，一年有效，需买证书服务 |
| Apple 开发者账号（$99/年） | Xcode/fastlane 出正式签名 IPA，可长期安装、上 TestFlight |

签名时 Bundle ID 用 `com.xingchen.bhc`；若被占用改成 `com.xingchen.bhc2`（同时改 `ios/project.yml` 的 `PRODUCT_BUNDLE_IDENTIFIER`）。

---

## 六、说明

- App 启动后用内置本地 HTTP 服务（127.0.0.1:18888）加载 `Shell/www` 的资源，**静态资源不经过服务器**；只有登录/存档走 `http://36.134.112.211:19090`。
- 桌面图标名与加载提示均为「**时尚百货城**」（`Info.plist` 的 `CFBundleDisplayName` + `ShellViewController.swift`）。
- 若构建只想验证能否编过、不想传资源：删掉 workflow 里 "Download & merge asset chunks" 那步即可，App 会退化为直连 `http://36.134.112.211:66/` 在线加载（但这带宽下玩不了，仅用于验证编译）。
- Apple 审核不允许纯 WebView 壳上架 App Store；自签/企业签自用没问题。
