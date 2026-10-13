# Desktop Translator

macOS 桌面词典 / 翻译小工具：窗口可贴在桌面上，输入英文或中文自动识别方向，查释义、例句、读音，并保存最近查询。

**下载（推荐给普通用户）** → [GitHub Releases（最新版）](https://github.com/yxwvwxy/desktop-translator/releases/latest)

## 系统要求

- macOS **14.0** 或更高
- 联网（查词使用有道 / Google 等在线服务）

## 安装

1. 打开 [Releases](https://github.com/yxwvwxy/desktop-translator/releases/latest)。
2. 下载 **`Desktop-Translator-*-macOS.zip`**。
3. 解压，将 **`Desktop Translator.app`** 拖入「应用程序」文件夹。
4. 首次打开若提示「无法验证开发者」：
   - 在 Finder 中 **按住 Control 键点击** 应用 → **打开** → 再点 **打开**；或  
   - 系统设置 → **隐私与安全性** → 允许打开。

应用使用 ad-hoc 签名，未做 Apple 公证，属正常现象。

## 使用说明

- **Auto**：自动判断英/中（及常见语种）并翻译。
- **Entry**：输入单词或句子；英文错词会显示红色波浪线，右键可改拼写。
- **Translation**：释义与翻译；可点喇叭听读音。
- **Recent**：最近查询；最右侧 **×** 删除单条记录。
- 菜单栏 **Aa** 图标：钉在桌面 / 普通窗口 / 退出。

可选：在桌面 **编辑小组件** 里添加 **Desktop Translator** 小组件快速查词。

## 从源码构建

需要 **Xcode**（含 macOS SDK）：

```bash
git clone https://github.com/yxwvwxy/desktop-translator.git
cd desktop-translator
chmod +x package-app.sh
./package-app.sh
```

会在项目目录生成 `Desktop Translator.app`，并尝试安装到「应用程序」。

仅打包 zip（不安装，与 CI 相同）：

```bash
chmod +x scripts/release-build.sh
./scripts/release-build.sh
# 输出: dist/Desktop-Translator-<version>-macOS.zip
```

## 发版（维护者）

推送版本标签会自动构建并上传到 Release：

```bash
git tag v1.0.0
git push origin v1.0.0
```

## 许可证

若仓库未单独声明许可证文件，使用前请自行确认；欢迎 Issue / PR。
