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
- 越狱 iOS 设备（iOS 14-15，unc0ver）
- **必须安装 TrollVNC**（提供 STHIDEventGenerator 触摸注入）
- Theos（从源码编译时需要）

### PC 端
- Python 3.8+
- FFmpeg
- numpy, opencv-python

## 下载预编译包

### GitHub Actions（推荐）

1. 进入 [Actions](https://github.com/hogan-hong/iOSScreenStream/actions) 标签页
2. 点击最新的工作流运行
3. 下载 `iOSScreenStream` 产物

### 手动编译

```bash
cd tweak
make package
```

## 安装

1. 将 `.deb` 文件拷贝到 iOS 设备
2. 通过 Filza 或终端安装：
   ```bash
   dpkg -i com.hogan.iosscreenstream_1.1.0-1_iphoneos-arm.deb
   ```
3. **注意**：确保 TrollVNC 已安装

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

修改设置后点击「应用更改」即可生效，无需重启。

## 运行 PC 客户端

```bash
cd pc
pip install -r requirements.txt

# 单台设备
python stream_client.py --ios-ip 192.168.1.101 --video-port 5001 --control-port 5002

# 多台设备
python multi_client.py --devices 5 --ip-prefix 192.168.1. --ip-start 101
```

### PC 客户端操作

- **鼠标左键按下** → 触摸按下
- **鼠标左键释放** → 触摸抬起
- **鼠标左键拖动** → 触摸移动
- **按 Q 或 ESC** → 退出

## 多设备配置

5 台设备示例：

| 设备 | IP | 视频端口 | 控制端口 |
|------|-----|---------|---------|
| iPhone-1 | 192.168.1.101 | 5001 | 5002 |
| iPhone-2 | 192.168.1.102 | 5003 | 5004 |
| iPhone-3 | 192.168.1.103 | 5005 | 5006 |
| iPhone-4 | 192.168.1.104 | 5007 | 5008 |
| iPhone-5 | 192.168.1.105 | 5009 | 5010 |

每台 iPhone 的 iOSScreenStream 设置对应不同的端口。

## 协议

### 视频流 (UDP)
- H.264 Annex B 格式 NAL 单元
- 关键帧包含 SPS/PPS
- 大包自动分片（≤1400字节/包），带头部：序号+总分包数+分包索引+总长度+偏移

### 控制流 (TCP)
- JSON 消息，换行符分隔
- 触控事件：`{"type": "touch", "action": "down|up|move", "x": 0-1, "y": 0-1}`
- 心跳：`{"type": "heartbeat"}`
- 坐标归一化到 0~1（相对于屏幕）

## 从源码编译

### 前置条件

- macOS + Xcode
- [Theos](https://github.com/roothide/theos)
- iOS SDK 14.5+

### 编译步骤

```bash
# 克隆仓库
git clone https://github.com/hogan-hong/iOSScreenStream.git
cd iOSScreenStream

# 编译（GitHub Actions 会自动处理 TrollVNC 依赖）
cd tweak
make package
```

### GitHub Actions（免本地编译）

推送到 main 分支或手动触发 workflow_dispatch 即可。

## 基于

- 屏幕捕获代码来自 [TrollVNC](https://github.com/hogan-hong/TrollVNC) by 82Flex
- 触摸注入使用 TrollVNC 的 STHIDEventGenerator

## 许可证

GPL-2.0（与 TrollVNC 一致）
