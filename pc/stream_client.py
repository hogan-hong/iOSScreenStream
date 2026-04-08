#!/usr/bin/env python3
"""
iOSScreenStream PC Client - Fixed Version
Receives H.264 video from iOS device via UDP and displays it.
Sends touch events back to iOS device via TCP.
"""

import argparse
import socket
import struct
import threading
import json
import subprocess
import sys
import time
import numpy as np
import cv2

class iOSStreamClient:
    def __init__(self, ios_ip="192.168.1.101", video_port=5001, control_port=5002, device_name="iPhone"):
        self.ios_ip = ios_ip
        self.video_port = video_port
        self.control_port = control_port
        self.device_name = device_name
        self.running = True
        
        # Video receiving
        self.udp_socket = None
        self.ffmpeg_proc = None
        self.frame_buffer = None
        self.frame_lock = threading.Lock()
        self.frame_width = 1179
        self.frame_height = 2556
        
        # Control connection
        self.control_socket = None
        self.touch_window_name = f"{device_name} - Touch Control"
        
    def start(self):
        """Start the stream client"""
        # Start video receiver
        video_thread = threading.Thread(target=self._video_receiver)
        video_thread.daemon = True
        video_thread.start()
        
        # Start control connection
        control_thread = threading.Thread(target=self._control_sender)
        control_thread.daemon = True
        control_thread.start()
        
        # Display loop
        self._display_loop()
        
    def _video_receiver(self):
        """Receive H.264 video via UDP and decode with FFmpeg"""
        self.udp_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.udp_socket.bind(('0.0.0.0', self.video_port))
        self.udp_socket.settimeout(1.0)
        
        print(f"[Video] Listening on UDP port {self.video_port}")
        
        # FFmpeg pipeline for decoding H.264 NAL units
        # Use length-prefixed format instead of Annex B
        ffmpeg_cmd = [
            'ffmpeg', '-flags', 'low_delay',
            '-fflags', 'nobuffer', '-fflags', 'discardcorrupt',
            '-max_delay', '500000',
            '-framerate', '30',
            '-an', '-i', 'pipe:0',
            '-f', 'rawvideo', '-pix_fmt', 'bgr24', 'pipe:1'
        ]
        
        self.ffmpeg_proc = subprocess.Popen(
            ffmpeg_cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        
        # Start FFmpeg output reader
        output_thread = threading.Thread(target=self._ffmpeg_reader)
        output_thread.daemon = True
        output_thread.start()
        
        buffer = b''
        while self.running:
            try:
                data, addr = self.udp_socket.recvfrom(65536)
                if data:
                    buffer += data
                    
                    # Process complete frames (4 bytes length prefix)
                    while len(buffer) >= 4:
                        frame_len = struct.unpack('>I', buffer[:4])[0]
                        if len(buffer) >= 4 + frame_len:
                            nal_data = buffer[4:4+frame_len]
                            self.ffmpeg_proc.stdin.write(nal_data)
                            self.ffmpeg_proc.stdin.flush()
                            buffer = buffer[4+frame_len:]
                        else:
                            break
            except socket.timeout:
                continue
            except Exception as e:
                if self.running:
                    print(f"[Video] Error: {e}")
                break
                
    def _ffmpeg_reader(self):
        """Read decoded frames from FFmpeg"""
        while self.running:
            try:
                # Read raw frame (BGR24)
                frame_size = self.frame_width * self.frame_height * 3
                raw = self.ffmpeg_proc.stdout.read(frame_size)
                
                if len(raw) == frame_size:
                    frame = np.frombuffer(raw, dtype=np.uint8).reshape((self.frame_height, self.frame_width, 3))
                    with self.frame_lock:
                        self.frame_buffer = frame.copy()
                else:
                    # Try to detect resolution
                    break
            except Exception as e:
                if self.running:
                    print(f"[Video] Frame read error: {e}")
                break
                
    def _display_loop(self):
        """Display video frames and capture mouse events"""
        cv2.namedWindow(self.touch_window_name, cv2.WINDOW_NORMAL)
        cv2.resizeWindow(self.touch_window_name, 400, 800)
        cv2.setMouseCallback(self.touch_window_name, self._on_mouse)
        
        last_frame_time = time.time()
        fps = 0
        frame_count = 0
        
        while self.running:
            with self.frame_lock:
                frame = self.frame_buffer
                
            if frame is not None:
                # Calculate FPS
                current_time = time.time()
                frame_count += 1
                if current_time - last_frame_time >= 1.0:
                    fps = frame_count / (current_time - last_frame_time)
                    frame_count = 0
                    last_frame_time = current_time
                
                # Add FPS overlay
                cv2.putText(frame, f"FPS: {fps:.1f}", (10, 30),
                           cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 255, 0), 2)
                cv2.putText(frame, f"Device: {self.device_name}", (10, 70),
                           cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 255, 0), 2)
                cv2.putText(frame, f"iOS: {self.ios_ip}", (10, 110),
                           cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 255, 0), 2)
                
                # Show connection status
                if self.control_socket:
                    cv2.putText(frame, "Control: Connected", (10, 150),
                               cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 255, 0), 2)
                else:
                    cv2.putText(frame, "Control: Disconnected", (10, 150),
                               cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 0, 255), 2)
                
                cv2.imshow(self.touch_window_name, frame)
                
            key = cv2.waitKey(1) & 0xFF
            if key == ord('q') or key == 27:
                self.stop()
                break
                
        cv2.destroyAllWindows()
        
    def _on_mouse(self, event, x, y, flags, param):
        """Handle mouse events for touch simulation"""
        if not self.control_socket:
            return
            
        with self.frame_lock:
            if self.frame_buffer is not None:
                height, width = self.frame_buffer.shape[:2]
            else:
                height, width = self.frame_height, self.frame_width
        
        # Normalize coordinates to 0-1
        nx = max(0.0, min(1.0, x / width))
        ny = max(0.0, min(1.0, y / height))
        
        msg = None
        if event == cv2.EVENT_LBUTTONDOWN:
            msg = {"type": "touch", "action": "down", "x": nx, "y": ny}
        elif event == cv2.EVENT_LBUTTONUP:
            msg = {"type": "touch", "action": "up", "x": nx, "y": ny}
        elif event == cv2.EVENT_MOUSEMOVE and flags & 1:  # Left button held
            msg = {"type": "touch", "action": "move", "x": nx, "y": ny}
            
        if msg:
            try:
                self.control_socket.send((json.dumps(msg) + '\n').encode())
            except Exception as e:
                print(f"[Control] Send error: {e}")
                
    def _control_sender(self):
        """Maintain TCP connection to iOS device for touch control"""
        while self.running:
            try:
                self.control_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                self.control_socket.settimeout(5.0)
                self.control_socket.connect((self.ios_ip, self.control_port))
                print(f"[Control] Connected to {self.ios_ip}:{self.control_port}")
                
                # Keep-alive loop
                while self.running:
                    try:
                        time.sleep(5)
                    except:
                        break
                        
            except Exception as e:
                print(f"[Control] Connection to {self.ios_ip}:{self.control_port} failed: {e}")
                time.sleep(2)
            finally:
                if self.control_socket:
                    self.control_socket.close()
                    self.control_socket = None
                    
    def stop(self):
        """Stop the client"""
        print("[Client] Stopping...")
        self.running = False
        
        if self.udp_socket:
            self.udp_socket.close()
        if self.ffmpeg_proc:
            self.ffmpeg_proc.stdin.close()
            self.ffmpeg_proc.terminate()
        if self.control_socket:
            self.control_socket.close()


def main():
    parser = argparse.ArgumentParser(description='iOSScreenStream PC Client')
    parser.add_argument('--ios-ip', type=str, default='192.168.1.101',
                       help='iOS device IP address')
    parser.add_argument('--video-port', type=int, default=5001,
                       help='UDP port for video stream (default: 5001)')
    parser.add_argument('--control-port', type=int, default=5002,
                       help='TCP port for control (default: 5002)')
    parser.add_argument('--device-name', type=str, default='iPhone',
                       help='Device name for display')
    parser.add_argument('--width', type=int, default=1179,
                       help='iOS screen width in pixels')
    parser.add_argument('--height', type=int, default=2556,
                       help='iOS screen height in pixels')
    
    args = parser.parse_args()
    
    client = iOSStreamClient(
        ios_ip=args.ios_ip,
        video_port=args.video_port,
        control_port=args.control_port,
        device_name=args.device_name
    )
    client.frame_width = args.width
    client.frame_height = args.height
    
    try:
        client.start()
    except KeyboardInterrupt:
        client.stop()


if __name__ == '__main__':
    main()
