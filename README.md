<p align="center">
  <img src="Preferences/Resources/Pineora@3x.png" alt="Pineora icon / 图标" width="80" height="80">
</p>

<h1 align="center">Pineora</h1>

<p align="center">主屏幕图标主题 · Home Screen icon theming for jailbroken iOS</p>

<p align="center"><a href="#zh-cn">简体中文</a> · <a href="#english">English</a></p>

<a id="zh-cn"></a>

## 简体中文

### 功能

- 启用、停用和拖动排序主题，按优先级组合使用。
- 解析 `.theme` 中的 `IconBundles`、`Bundles` 等常见图标布局。
- 图标蒙版、角标样式，以及时钟和日历主题资源支持。
- iOS 26 文件夹预览图标适配；设置提供简体中文、英语、日语和韩语。

### 使用与兼容性

安装后进入 **设置 → Pineora**，选择主题并调整顺序，再点 **应用更改**。主题搜索目录会显示在设置中；本仓库不附带主题包。

依赖 `mobilesubstrate` 和 `preferenceloader`。构建目标为 iOS 16.0+，提供 rootless 和 roothide 配置；当前开发设备为 iOS 26.0.1，iOS 16/17/18 的兼容路径仍需在对应系统实机验证。

### 构建与目录

使用 [Apelin](https://github.com/owngoal-dev/Apelin) 构建，配置见 [apelin-project.json](apelin-project.json)。在自己的设备上需绑定本机已注册且相互兼容的工具链与 SDK；当前开发配置使用 CLT 15.3 / iOS 17.4 SDK。rootless 与 roothide 包需分别构建。

- `Sources/`：主题解析、渲染和 SpringBoard 钩子。
- `Preferences/`、`PreferenceLoader/`：设置面板与入口。
- `Research/`：研究记录、兼容性调查、探针及回归测试源码。
- `Tools/`：设置图标生成工具。

### 许可

本项目原创代码采用 [MIT License](LICENSE)。`Research/` 中涉及的第三方资料及图标中的 Apple SF Symbols 不因本许可证而获得重新授权，仍受各自权利与许可条款约束。Pineora 不隶属于 SnowBoard，也不代表其作者。

---

<a id="english"></a>

## English

### Features

- Enable, disable, and reorder themes to combine them by priority.
- Read common `.theme` icon layouts, including `IconBundles` and `Bundles`.
- Support for icon masks, badge styling, and clock and calendar theme resources.
- iOS 26 folder preview icon adaptations; settings in Simplified Chinese, English, Japanese, and Korean.

### Usage & Compatibility

After installation, open **Settings → Pineora**, select and reorder themes, then tap **Apply Changes**. Theme search directories are shown in settings. No theme packs are included in this repository.

Requires `mobilesubstrate` and `preferenceloader`. The deployment target is iOS 16.0+, with rootless and roothide build configurations. The current development device runs iOS 26.0.1; compatibility paths for iOS 16/17/18 still need testing on devices running those versions.

### Building & Layout

Build with [Apelin](https://github.com/owngoal-dev/Apelin) using [apelin-project.json](apelin-project.json). Bind the project to a compatible toolchain and SDK registered on your own device; the current development configuration uses CLT 15.3 / the iOS 17.4 SDK. Build rootless and roothide packages separately.

- `Sources/`: theme parsing, rendering, and SpringBoard hooks.
- `Preferences/`, `PreferenceLoader/`: settings pane and its entry.
- `Research/`: research notes, compatibility investigations, probes, and regression test sources.
- `Tools/`: settings icon generator.

### License

Original project code is licensed under the [MIT License](LICENSE). Third-party material referenced in `Research/` and Apple SF Symbols used in the icon are not relicensed by this license and remain subject to their respective rights and license terms. Pineora is not affiliated with SnowBoard and does not represent its authors.
