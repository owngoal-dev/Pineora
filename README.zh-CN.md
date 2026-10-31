<p align="center">
  <img src="Preferences/Resources/Pineora@3x.png" alt="Pineora 图标" width="80" height="80">
</p>

<h1 align="center">Pineora</h1>

<p align="center">为越狱 iOS 设备提供主屏幕图标主题。</p>

<p align="center"><a href="README.md">English</a> · 简体中文</p>

## 功能

- 启用、停用和拖动排序主题，按优先级组合使用。
- 解析 `.theme` 中的 `IconBundles`、`Bundles` 等常见图标布局。
- 图标蒙版、角标样式，以及时钟和日历主题资源支持。
- iOS 26 文件夹预览图标适配；设置提供简体中文、英语、日语和韩语。

## 使用与兼容性

安装后进入 **设置 → Pineora**，选择主题并调整顺序，再点 **应用更改**。主题搜索目录会显示在设置中；本仓库不附带主题包。

依赖 `mobilesubstrate` 和 `preferenceloader`。构建目标为 iOS 16.0+，提供 rootless 和 roothide 配置；当前开发设备为 iOS 26.0.1，iOS 16/17/18 的兼容路径仍需在对应系统实机验证。

## 构建与目录

使用 [Apelin](https://github.com/owngoal-dev/Apelin) 构建，配置见 [apelin-project.json](apelin-project.json)。在自己的设备上需绑定本机已注册且相互兼容的工具链与 SDK；当前开发配置使用 CLT 15.3 / iOS 17.4 SDK。rootless 与 roothide 包需分别构建。

- `Sources/`：主题解析、渲染和 SpringBoard 钩子。
- `Preferences/`、`PreferenceLoader/`：设置面板与入口。
- `Research/`：研究记录、兼容性调查、探针及回归测试源码。
- `Tools/`：设置图标生成工具。

## 许可

本项目原创代码采用 [MIT License](LICENSE)。`Research/` 中涉及的第三方资料及图标中的 Apple SF Symbols 不因本许可证而获得重新授权，仍受各自权利与许可条款约束。Pineora 不隶属于 SnowBoard，也不代表其作者。
