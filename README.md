# iOSScreenStream

Low-latency iOS screen streaming with reverse touch control for jailbroken devices.

## Features

- **Low-latency**: Uses IOSurface + VideoToolbox hardware H.264 encoding
- **Touch control**: Full touch event injection via TCP (using TrollVNC's STHIDEventGenerator)
- **Efficient**: UDP multicast for video, TCP for control
- **Settings UI**: Built-in preference panel in iOS Settings
- **GitHub Actions**: Pre-built deb packages available

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  iOS Device (Jailbroken)                                    │
│  ┌──────────────┐    H.264 NAL    ┌──────────────────────┐│
│  │ IOSurface    │ ───────────────►│  PC (Python Client)  ││
│  │ Screen       │    UDP          │  FFmpeg Decoding      ││
│  │ Capture      │                 │  Window Display       ││
│  └──────────────┘                 └──────────┬───────────┘│
│         │                                     │             │
│  ┌──────▼──────┐    Touch Events  ┌──────────▼───────────┐│
│  │ VideoToolbox│ ◄─────────────── │  Mouse Click         ││
│  │ H.264       │    TCP           │  Coordinate Mapping  ││
│  │ Encoder     │                  └──────────────────────┘│
│  └──────────────┘                                         │
└─────────────────────────────────────────────────────────────┘
```

## Requirements

### iOS Side
- Jailbroken iOS device (iOS 14-15, unc0ver)
- **TrollVNC must be installed** (provides STHIDEventGenerator for touch injection)
- Theos for building (if building from source)

### PC Side
- Python 3.8+
- FFmpeg (for decoding)
- numpy, opencv-python

## Download Pre-built Package

### GitHub Actions (Recommended)

1. Go to the [Actions](https://github.com/hogan-hong/iOSScreenStream/actions) tab
2. Click on the latest workflow run
3. Download the `iOSScreenStream` artifact
4. Or use the "Release" workflow for a downloadable release

### Manual Build

```bash
cd tweak
make package
```

## Installation

1. Copy the `.deb` file to your iOS device
2. Install via Filza File Manager or terminal:
   ```bash
   dpkg -i com.yourname.iosscreenstream_1.0.0-1_iphoneos-arm.deb
   ```
3. **Important**: Make sure TrollVNC is already installed

## Configuration

After installation, go to **Settings > iOSScreenStream** to configure:

| Setting | Default | Description |
|---------|---------|-------------|
| 启用服务 | YES | Enable/disable streaming |
| 电脑 IP 地址 | 192.168.1.100 | Your PC's IP |
| 视频端口 (UDP) | 5001 | UDP port for video stream |
| 控制端口 (TCP) | 5002 | TCP port for touch control |
| 帧率 (FPS) | 30 | Target frame rate |
| 码率 (kbps) | 2000 | Video bitrate |

## Running the PC Client

```bash
cd pc
pip install -r requirements.txt

# Single device
python stream_client.py --ios-ip 192.168.1.101 --video-port 5001 --control-port 5002

# Multiple devices
python multi_client.py --devices 5
```

## Multi-Device Setup

For 5 devices, configure each iPhone with different ports:

| Device | Video Port | Control Port |
|--------|-----------|-------------|
| iPhone 1 | 5001 | 5002 |
| iPhone 2 | 5003 | 5004 |
| iPhone 3 | 5005 | 5006 |
| iPhone 4 | 5007 | 5008 |
| iPhone 5 | 5009 | 5010 |

## Protocol

### Video Stream (UDP)
- H.264 NAL units in length-prefixed format (4 bytes length + NAL data)
- Each device uses its own UDP port

### Control Stream (TCP)
- JSON messages, one per line
- Touch events: `{"type": "touch", "action": "down|up|move", "x": 0-1, "y": 0-1}`
- Coordinates normalized 0-1 relative to screen

## Building from Source

### Prerequisites

- macOS with Xcode
- [Theos](https://github.com/roothide/theos)
- iOS SDK 14.5+

### Build Steps

```bash
# Clone the repository
git clone https://github.com/hogan-hong/iOSScreenStream.git
cd iOSScreenStream

# The build workflow will automatically:
# 1. Checkout TrollVNC for STHIDEventGenerator headers
# 2. Set up Theos and iOS SDKs
# 3. Build the package
```

### GitHub Actions (No Local Build Required)

Simply push to main branch or use workflow_dispatch to trigger a build.

## Based on

- Screen capture code from [TrollVNC](https://github.com/hogan-hong/TrollVNC) by 82Flex
- Touch injection via TrollVNC's STHIDEventGenerator

## License

GPL-2.0 (same as TrollVNC)
