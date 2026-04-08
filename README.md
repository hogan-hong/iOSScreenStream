# iOSScreenStream

Low-latency iOS screen streaming with reverse touch control for jailbroken devices.

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
│  │ H.264       │    TCP          │  Coordinate Mapping  ││
│  │ Encoder     │                 └──────────────────────┘│
│  └──────────────┘                                         │
│         │                                                  │
│  ┌──────▼──────┐    Touch         ┌──────────────────────┐│
│  │ STHIDEvent  │ ◄─────────────── │  Touch Injection    ││
│  │ Generator   │                 │  (Same as TrollVNC)  ││
│  └─────────────┘                 └──────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

## Features

- **Low-latency**: Uses IOSurface + VideoToolbox hardware H.264 encoding
- **Multi-device**: Supports multiple iOS devices simultaneously
- **Touch control**: Full touch event injection via TCP
- **Efficient**: UDP multicast for video, TCP for control

## Requirements

### iOS Side
- Jailbroken iOS device (iOS 14-15, unc0ver)
- Theos for building
- Dependencies from TrollVNC (same screen capture APIs)

### PC Side
- Python 3.8+
- FFmpeg (for decoding)
- numpy, opencv-python

## Quick Start

### 1. Build iOS Tweak

```bash
cd tweak
make package
# Install resulting .deb to your iOS device
```

### 2. Configure iOS Tweak

Edit `/Library/PreferenceLoader/Preferences/iOSScreenStream.plist`:
- Set `ServerIP` to your PC's IP
- Set `VideoPort` (default: 5001)
- Set `ControlPort` (default: 5002)
- Enable `Enabled` to start streaming

### 3. Run PC Client

```bash
cd pc
pip install -r requirements.txt
python stream_client.py --video-port 5001 --control-port 5002 --device-name "iPhone-1"
```

## Protocol

### Video Stream (UDP)
- H.264 NAL units sent via raw UDP
- Each packet: 4 bytes length (big-endian) + NAL data
- PPS/SPS sent on connect before I-frame

### Control Stream (TCP)
- JSON messages, one per line
- Touch events: `{"type": "touch", "action": "down|up|move", "x": 0-1, "y": 0-1}`
- Coordinates normalized 0-1 relative to screen

## Based on

This project uses screen capture code from [TrollVNC](https://github.com/hogan-hong/TrollVNC) by 82Flex.

## License

GPL-2.0 (same as TrollVNC)
