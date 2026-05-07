# iOSScreenStream

越狱 iOS 设备低延迟屏幕流传输与反向触控

## 功能

- **低延迟**：IOSurface + VideoToolbox 硬件 H.264 编码
- **反向触控**：PC 端鼠标点击 → TCP 指令 → iOS 注入触摸事件（基于 TrollVNC 的 STHIDEventGenerator）
- **高效传输**：UDP 视频流 + TCP 控制指令，分包防丢
- **设置面板**：iOS 设置内建偏好面板
- **自动构建**：GitHub Actions 自动编译 deb 包

## 架构

```
┌────────────────────────────────────────────────────────┐
│  iOS 设备（越狱）                                       │
│                                                        │
│  ┌──────────────┐   H.264 Annex B   ┌──────────────┐  │
│  │ IOSurface    │ ───────────────►  │  PC 客户端    │  │
│  │ 屏幕捕获     │   UDP 分包传输     │  FFmpeg 解码  │  │
│  │              │                   │  窗口显示      │  │
│  └──────────────┘                   └──────┬───────┘  │
│         ▲                                  │          │
│  ┌──────┴──────┐   触控指令(TCP)  ┌────────▼───────┐  │
│  │ STHIDEvent  │ ◄────────────── │  鼠标点击      │  │
│  │ 触摸注入     │   PC → iOS      │  坐标映射      │  │
│  └─────────────┘                  └───────────────┘  │
│                                                        │
│  iOS 端 TCP 监听 ← PC 主动连入                          │
└────────────────────────────────────────────────────────┘
```

## 环境要求

### iOS 端
- 越狱 iOS 设备（iOS 14+）
- **必须安装 TrollVNC**（提供 STHIDEventGenerator 触摸注入）

### PC 端
- Python 3.8+
- FFmpeg
- numpy, opencv-python

## 下载安装

1. 从 [Releases](https://github.com/hogan-hong/iOSScreenStream/releases) 下载最新 `.deb` 文件
2. 拷贝到 iOS 设备并安装：
   ```bash
   dpkg -i com.hogan.iosscreenstream_1.3.0_iphoneos-arm.deb
   ```
3. 注销或重启 SpringBoard 使插件生效

## 配置

安装后，进入 **设置 > iOSScreenStream** 配置：

| 设置项 | 默认值 | 说明 |
|--------|--------|------|
| 启用服务 | 是 | 开启/关闭流传输 |
| 电脑 IP 地址 | 192.168.1.100 | 电脑的 IP |
| 视频端口 (UDP) | 5001 | UDP 视频流端口 |
| 控制端口 (TCP) | 5002 | TCP 控制监听端口 |
| 帧率 (FPS) | 30 | 目标帧率 |
| 码率 (kbps) | 2000 | 视频码率 |

修改设置后注销 SpringBoard 生效。

## 项目结构

```
tweak/
├── Makefile                  # Theos 构建配置
├── control                   # Debian 包元数据
├── Filter.plist              # Cydia Substrate 过滤器
├── entry.plist               # PreferenceLoader 入口配置
├── src/                      # Tweak 源码
│   ├── StreamTweak.mm        # 主入口
│   ├── ScreenCapturer.mm     # IOSurface 屏幕捕获
│   ├── VideoEncoder.mm       # VideoToolbox H.264 编码
│   ├── StreamServer.mm       # UDP/TCP 服务器
│   └── TouchController.mm   # 触摸事件注入
├── prefs/
│   └── ISSPrefsRootListController.mm  # 设置面板控制器
├── prefs_bundle_resources/
│   ├── Info.plist            # PreferenceBundle 信息（注意大写 I）
│   ├── Root.plist            # 设置项定义
│   ├── icon@2x.png           # 设置列表图标 @2x
│   └── icon@3x.png           # 设置列表图标 @3x
└── include/                  # 头文件
    ├── Preferences/           # PSListController 等私有框架头文件
    ├── IOKitSPI.h            # IOKit 私有接口
    ├── IOSurfaceSPI.h        # IOSurface 私有接口
    ├── STHIDEventGenerator.h # 触摸注入头文件
    └── UIScreen+Private.h    # UIScreen 私有接口
```

## 更新日志

### v1.3.0 (2025-05-07)
- **修复**：设置页面空白问题（Theos strip 移除了 ObjC 方法元数据，导致 PSListController 无法加载）
  - 设置 `iOSScreenStreamPrefs_STRIP = 0` 禁止 strip
  - 添加 `-ObjC` 链接器标志保留 ObjC 类信息
- **修复**：设置列表缺少图标（添加 icon@2x.png、icon@3x.png）
- **修复**：Info.plist 大小写问题（`info.plist` → `Info.plist`，iOS NSBundle 区分大小写）
- **修复**：部署目标不匹配（minos 14.5 → 14.0，兼容 iOS 14.2 设备）
- **修复**：设置页面基类错误（`PSListItemsController` → `PSListController`）
- **修复**：PreferenceBundle 未链接 Preferences.framework
- **修复**：CI 在大小写不敏感 APFS 上构建导致 Info.plist 文件名错误
- **修复**：bundle 内存在多余的 Resources/ 子目录
- **改进**：统一版本号至 1.3.0（之前 Makefile/control/Info.plist 版本不一致）
- **改进**：更新 README 项目文档

### v1.1.0
- 初始发布版本
- IOSurface 屏幕捕获 + VideoToolbox H.264 编码
- UDP 视频流传输 + TCP 反向触控
- 基础设置面板

## 编译

需要 macOS + Xcode + Theos 环境：

```bash
export THEOS=/path/to/theos
cd tweak
make package
```

## License

MIT
