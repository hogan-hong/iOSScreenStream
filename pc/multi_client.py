#!/usr/bin/env python3
"""
iOSScreenStream 多设备客户端
同时启动多个流客户端，连接多台 iOS 设备
"""

import subprocess
import time
import argparse
import sys

# 默认设备配置
DEFAULT_DEVICES = [
    {"name": "iPhone-1", "ios_ip": "192.168.1.101", "video_port": 5001, "control_port": 5002},
    {"name": "iPhone-2", "ios_ip": "192.168.1.102", "video_port": 5003, "control_port": 5004},
    {"name": "iPhone-3", "ios_ip": "192.168.1.103", "video_port": 5005, "control_port": 5006},
    {"name": "iPhone-4", "ios_ip": "192.168.1.104", "video_port": 5007, "control_port": 5008},
    {"name": "iPhone-5", "ios_ip": "192.168.1.105", "video_port": 5009, "control_port": 5010},
]


def launch_client(device):
    """启动单个流客户端"""
    cmd = [
        sys.executable,
        'stream_client.py',
        '--ios-ip', device['ios_ip'],
        '--video-port', str(device['video_port']),
        '--control-port', str(device['control_port']),
        '--device-name', device['name']
    ]

    proc = subprocess.Popen(cmd)
    return proc


def main():
    parser = argparse.ArgumentParser(description='iOSScreenStream 多设备客户端')
    parser.add_argument('--devices', type=int, default=5,
                       help='设备数量 (默认: 5)')
    parser.add_argument('--ip-prefix', type=str, default='192.168.1.',
                       help='IP 前缀 (默认: 192.168.1.)')
    parser.add_argument('--ip-start', type=int, default=101,
                       help='起始 IP 末位 (默认: 101)')

    args = parser.parse_args()

    # 生成设备列表
    devices = []
    for i in range(args.devices):
        ip_end = args.ip_start + i
        devices.append({
            "name": f"iPhone-{i+1}",
            "ios_ip": f"{args.ip_prefix}{ip_end}",
            "video_port": 5001 + i * 2,
            "control_port": 5002 + i * 2,
        })

    print(f"[多设备] 启动 {len(devices)} 台设备...")
    for d in devices:
        print(f"  {d['name']}: {d['ios_ip']} 视频:{d['video_port']} 控制:{d['control_port']}")

    processes = []
    for i, device in enumerate(devices):
        proc = launch_client(device)
        processes.append(proc)
        time.sleep(0.5)  # 错开启动

    print(f"[多设备] {len(devices)} 个客户端已启动")
    print("[多设备] 按 Ctrl+C 停止所有客户端")

    try:
        for proc in processes:
            proc.wait()
    except KeyboardInterrupt:
        print("\n[多设备] 正在停止所有客户端...")
        for proc in processes:
            proc.terminate()
        for proc in processes:
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
        print("[多设备] 所有客户端已停止")


if __name__ == '__main__':
    main()
