#!/usr/bin/env python3
"""
iOSScreenStream Multi-Device Client
Launches multiple stream clients for 5+ iOS devices.
"""

import subprocess
import time
import argparse
import signal
import sys

# Default device configurations
DEFAULT_DEVICES = [
    {"name": "iPhone-1", "video_port": 5001, "control_port": 5002, "x": 0, "y": 0},
    {"name": "iPhone-2", "video_port": 5003, "control_port": 5004, "x": 600, "y": 0},
    {"name": "iPhone-3", "video_port": 5005, "control_port": 5006, "x": 0, "y": 600},
    {"name": "iPhone-4", "video_port": 5007, "control_port": 5008, "x": 600, "y": 600},
    {"name": "iPhone-5", "video_port": 5009, "control_port": 5010, "x": 300, "y": 1200},
]

def launch_client(device, device_index):
    """Launch a single stream client"""
    cmd = [
        sys.executable,
        'stream_client.py',
        '--video-port', str(device['video_port']),
        '--control-port', str(device['control_port']),
        '--device-name', device['name']
    ]
    
    proc = subprocess.Popen(cmd)
    return proc

def main():
    parser = argparse.ArgumentParser(description='iOSScreenStream Multi-Device Client')
    parser.add_argument('--devices', type=int, default=5,
                       help='Number of devices (default: 5)')
    parser.add_argument('--layout', type=str, default='grid',
                       help='Layout: grid or horizontal')
    
    args = parser.parse_args()
    
    devices = DEFAULT_DEVICES[:args.devices]
    
    print(f"[MultiClient] Starting {len(devices)} device(s)...")
    
    processes = []
    for i, device in enumerate(devices):
        proc = launch_client(device, i)
        processes.append(proc)
        time.sleep(0.5)  # Stagger launch
        
    print(f"[MultiClient] All {len(devices)} clients running")
    print("[MultiClient] Press Ctrl+C to stop all clients")
    
    try:
        # Wait for all processes
        for proc in processes:
            proc.wait()
    except KeyboardInterrupt:
        print("[MultiClient] Stopping all clients...")
        for proc in processes:
            proc.terminate()
        for proc in processes:
            proc.wait()
            
    print("[MultiClient] All clients stopped")


if __name__ == '__main__':
    main()
