<div align="center" markdown="1">
 <sup>特别感谢:</sup>
 <br>
 <a href="https://github.com/exelban/stats">
  <img width="200" alt="Stats" src="https://raw.githubusercontent.com/exelban/stats/master/Stats/Supporting%20Files/Assets.xcassets/AppIcon.appiconset/icon_256x256.png"/>
 </a>
 <br>
 <a>Mornits 基于 Stats 构建</a>
</div>

---

<p align="center">
  <a href="README.md">English</a> | <b>简体中文</b>
</p>

# Mornits

<a href="https://github.com/4ving/mornits/releases"><p align="center"><img src="https://github.com/4ving/Mornits/blob/main/Mornits/Supporting%20Files/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="120"></p></a>

![Mornits screenshot](https://github.com/user-attachments/assets/cec7f89d-b8fb-4473-b695-4123ad67a003)

常驻菜单栏的 macOS 及远程 Linux 系统监控工具

## 安装方法
### 手动安装
你可以点击 [这里](https://github.com/4ving/mornits/releases/latest/download/Mornits.dmg) 下载最新版本。
下载名为 `Mornits.dmg` 的文件后，打开并将应用拖入 Applications 应用程序文件夹。
**macOS 用户注意：** 如果弹出“无法验证开发者”的警告，请右键点击应用选择“打开”，或前往“系统设置 > 隐私与安全性”点击“仍要打开”。

## 系统要求
Mornits 支持 macOS 10.15 (Catalina) 及以上版本。

## 功能特性
Mornits 是一款可以让你同时监控本地 macOS 和远程 Linux 服务器的应用。

 - 远程服务器监控及聚合数据展示
 - CPU 利用率
 - 内存使用情况
 - 磁盘占用
 - 网络流量
 - GPU 利用率
 - 电池电量状态
 - 风扇控制（未维护）
 - 传感器信息（温度/电压/功率）
 - 蓝牙设备
 - 多时区时钟

## 常见问题 (FAQs)
### 为什么无法连接我的 LXD 服务器？
目前 Mornits 仅支持完整的 Linux 系统服务器。我们会过滤掉虚拟化的磁盘和网卡硬件。通常我们只用它来监控远程物理服务器的状态，对吧？

### 为什么 macOS 要求安装新的帮助程序 (Helper Tool)？
这是因为读取 macOS 系统传感器（如 CPU 温度和风扇转速）需要访问底层的系统管理控制器 (SMC)。以用户级权限运行的标准应用没有权限直接读取这些数据。

### 如何更改菜单栏图标的顺序？
菜单栏图标的顺序由 macOS 决定，而非 Mornits。安装后第一次重启可能会发生位置变化。
如需调整位置（适用于 macOS 10.14 及以上）：
1. 按住 ⌘ (Command 键)。
2. 将图标拖动到菜单栏的目标位置。
3. 松开 ⌘ 键。

### 如何降低 Mornits 的能耗或 CPU 占用？
Mornits 已尽可能优化效率，但定期读取系统数据仍有开销。每个模块都有其“性能成本”。如果你想降低能耗，可以禁用部分模块。最耗能的模块通常是“传感器”和“蓝牙”，禁用它们在某些情况下可降低多达 50% 的 CPU 占用。

### 传感器显示的 CPU/GPU 核心数不正确？
这里的传感器仅代表 CPU/GPU 上的热区（Thermal Zones），与实际的核心数没有直接关系。
例如，Apple Silicon 通常分为能效核心集群和性能核心集群，每个集群包含多个温度传感器。Mornits 只是显示这些值，并不代表特定某个核心的温度。此外，苹果每代芯片都会更换传感器 Key，适配需要时间。

### 应用崩溃了怎么办？
首先确保你使用的是最新版本。如果问题依然存在，请先查看 Issues 列表。如果没有类似的反馈，欢迎提交新的 Issue。

### 为什么我的 Issue 在没有回复的情况下被关闭了？
这通常是因为你的问题是重复的，或者已经有了现成的答案。请搜索已关闭 (Closed) 的 Issues 获取信息。

## 许可证
[MIT License](https://github.com/4ving/mornits/blob/master/LICENSE)