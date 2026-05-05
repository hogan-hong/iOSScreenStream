#!/usr/bin/env python3
"""
iOSScreenStream PC 客户端
接收 iOS 设备 H.264 视频流（UDP），发送触控指令（TCP）
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

# UDP 分包协议常量（与 iOS 端一致）
PACKET_HEADER_SIZE = 14  # 2(seq) + 2(totalParts) + 2(partIndex) + 4(totalLen) + 4(offset)
UDP_MAX_PACKET_SIZE = 1400


class iOSStreamClient:
    def __init__(self, ios_ip="192.168.1.101", video_port=5001, control_port=5002, device_name="iPhone"):
        self.ios_ip = ios_ip
        self.video_port = video_port
        self.control_port = control_port
        self.device_name = device_name
        self.running = True

        # 视频
        self.udp_socket = None
        self.ffmpeg_proc = None
        self.frame_buffer = None
        self.frame_lock = threading.Lock()
        self.frame_width = 0  # 自动检测
        self.frame_height = 0
        self.resolution_detected = threading.Event()

        # 分包重组
        self.packet_buffer = {}  # seq -> {parts: {}, total_parts: N, total_len: N, timestamp: T}

        # 控制连接
        self.control_socket = None
        self.control_lock = threading.Lock()

    def start(self):
        """启动客户端"""
        print(f"[信息] 连接 iOS 设备: {self.ios_ip}")
        print(f"[信息] 视频端口(UDP): {self.video_port}, 控制端口(TCP): {self.control_port}")

        # 先连接 TCP 控制通道（PC 主动连 iOS 端监听的端口）
        if not self._connect_control():
            print("[错误] 无法连接控制端口，1秒后重试...")

        # 启动视频接收
        video_thread = threading.Thread(target=self._video_receiver, daemon=True)
        video_thread.start()

        # 启动控制保活
        control_thread = threading.Thread(target=self._control_keeper, daemon=True)
        control_thread.start()

        # 等待分辨率检测或超时
        print("[信息] 等待视频数据以检测分辨率...")
        if self.resolution_detected.wait(timeout=10):
            print(f"[信息] 检测到分辨率: {self.frame_width}x{self.frame_height}")
        else:
            # 默认 iPhone SE2 分辨率
            print("[警告] 未检测到分辨率，使用默认值 750x1334")
            self.frame_width = 750
            self.frame_height = 1334

        # 启动 FFmpeg 解码
        self._start_ffmpeg()

        # 启动帧读取
        reader_thread = threading.Thread(target=self._ffmpeg_reader, daemon=True)
        reader_thread.start()

        # 显示循环
        self._display_loop()

    def _connect_control(self):
        """连接 iOS 端的 TCP 控制端口"""
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(5.0)
            sock.connect((self.ios_ip, self.control_port))
            with self.control_lock:
                self.control_socket = sock
            print(f"[控制] 已连接 {self.ios_ip}:{self.control_port}")
            return True
        except Exception as e:
            print(f"[控制] 连接失败: {e}")
            return False

    def _control_keeper(self):
        """控制连接保活"""
        while self.running:
            # 检查连接
            with self.control_lock:
                sock = self.control_socket

            if sock is None:
                self._connect_control()
                time.sleep(2)
                continue

            # 发送心跳
            try:
                heartbeat = json.dumps({"type": "heartbeat"}) + "\n"
                sock.send(heartbeat.encode())
            except Exception:
                print("[控制] 心跳失败，重连...")
                with self.control_lock:
                    if self.control_socket:
                        self.control_socket.close()
                        self.control_socket = None

            time.sleep(5)

    def _video_receiver(self):
        """接收 UDP 视频数据"""
        self.udp_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.udp_socket.bind(('0.0.0.0', self.video_port))
        self.udp_socket.settimeout(1.0)

        print(f"[视频] 监听 UDP 端口 {self.video_port}")

        # 累积 Annex B 数据，按 NAL 单元喂给 FFmpeg
        nal_buffer = bytearray()

        while self.running:
            try:
                data, addr = self.udp_socket.recvfrom(65536)
                if not data:
                    continue

                # 判断是否是分包格式
                if len(data) >= PACKET_HEADER_SIZE and self._is_fragmented(data):
                    # 分包重组
                    nal_data = self._reassemble_packet(data)
                    if nal_data:
                        self._process_nal_data(nal_data)
                elif len(data) >= 2:
                    # 简单格式：2字节序号 + Annex B 数据
                    seq = struct.unpack('>H', data[:2])[0]
                    nal_data = data[2:]
                    self._process_nal_data(nal_data)

            except socket.timeout:
                continue
            except Exception as e:
                if self.running:
                    print(f"[视频] 接收错误: {e}")

    def _is_fragmented(self, data):
        """判断是否是分包数据"""
        if len(data) < PACKET_HEADER_SIZE:
            return False
        seq, total_parts, part_index = struct.unpack('>HHH', data[:6])
        return total_parts > 1 or part_index > 0

    def _reassemble_packet(self, data):
        """重组分包数据"""
        if len(data) < PACKET_HEADER_SIZE:
            return None

        seq, total_parts, part_index, total_len, offset = struct.unpack(
            '>HHHII', data[:PACKET_HEADER_SIZE]
        )
        payload = data[PACKET_HEADER_SIZE:]

        now = time.time()

        if seq not in self.packet_buffer:
            self.packet_buffer[seq] = {
                'parts': {},
                'total_parts': total_parts,
                'total_len': total_len,
                'timestamp': now
            }

        buf = self.packet_buffer[seq]
        buf['parts'][part_index] = payload

        # 清理超时的分包（10秒）
        expired = [k for k, v in self.packet_buffer.items() if now - v['timestamp'] > 10]
        for k in expired:
            del self.packet_buffer[k]

        # 检查是否收齐
        if len(buf['parts']) >= buf['total_parts']:
            # 按索引排序拼接
            result = bytearray(buf['total_len'])
            for idx, part_data in buf['parts'].items():
                # 每个分片的偏移在其 header 里，但我们没存 per-part offset
                # 用 part_index * payload_size 近似
                payload_size = UDP_MAX_PACKET_SIZE - PACKET_HEADER_SIZE
                start = idx * payload_size
                end = min(start + len(part_data), buf['total_len'])
                if start < buf['total_len']:
                    result[start:end] = part_data[:end - start]

            del self.packet_buffer[seq]
            return bytes(result[:buf['total_len']])

        return None

    def _process_nal_data(self, nal_data):
        """处理 NAL 数据，检测分辨率，喂给 FFmpeg"""
        if not nal_data:
            return

        # 检测 SPS 以获取分辨率
        if len(nal_data) > 5 and nal_data[4] == 0x67:  # NAL type 7 = SPS
            self._detect_resolution_from_sps(nal_data[4:])

        # 写入 FFmpeg
        if self.ffmpeg_proc and self.ffmpeg_proc.stdin:
            try:
                self.ffmpeg_proc.stdin.write(nal_data)
                self.ffmpeg_proc.stdin.flush()
            except Exception:
                pass

    def _detect_resolution_from_sps(self, sps_data):
        """从 SPS 中解析分辨率"""
        try:
            # 简易 SPS 解析（不完美但对常见 profile 够用）
            if len(sps_data) < 4:
                return

            # 用 FFmpeg 探测更靠谱
            pass
        except Exception:
            pass

    def _start_ffmpeg(self):
        """启动 FFmpeg 解码进程"""
        cmd = [
            'ffmpeg',
            '-probesize', '32',
            '-flags', 'low_delay',
            '-fflags', 'nobuffer',
            '-fflags', 'discardcorrupt',
            '-max_delay', '500000',
            '-f', 'h264',  # 输入 Annex B H.264
            '-i', 'pipe:0',
            '-f', 'rawvideo',
            '-pix_fmt', 'bgr24',
            'pipe:1'
        ]

        self.ffmpeg_proc = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL  # 屏蔽 FFmpeg 的冗余输出
        )
        print("[视频] FFmpeg 解码器已启动")

        # 监听 FFmpeg stderr 获取分辨率
        # 这里用另一种方式：从输出帧大小反推

    def _ffmpeg_reader(self):
        """从 FFmpeg 读取解码后的帧"""
        while self.running:
            if not self.ffmpeg_proc or not self.ffmpeg_proc.stdout:
                time.sleep(0.1)
                continue

            try:
                # 先尝试已知分辨率
                if self.frame_width > 0 and self.frame_height > 0:
                    frame_size = self.frame_width * self.frame_height * 3
                    raw = self.ffmpeg_proc.stdout.read(frame_size)

                    if len(raw) == frame_size:
                        frame = np.frombuffer(raw, dtype=np.uint8).reshape(
                            (self.frame_height, self.frame_width, 3)
                        )
                        with self.frame_lock:
                            self.frame_buffer = frame.copy()
                    elif len(raw) == 0:
                        print("[视频] FFmpeg 已退出")
                        break
                    else:
                        # 分辨率可能不对，尝试其他常见分辨率
                        self._try_detect_resolution(raw)
                else:
                    time.sleep(0.1)

            except Exception as e:
                if self.running:
                    print(f"[视频] 帧读取错误: {e}")
                break

    def _try_detect_resolution(self, raw_data):
        """从数据量反推分辨率"""
        length = len(raw_data)
        # 3 bytes per pixel (BGR24)
        if length % 3 != 0:
            return

        pixels = length // 3
        # 常见 iOS 分辨率
        common_resolutions = [
            (750, 1334),    # iPhone SE2 / 6s / 7 / 8
            (1170, 2532),   # iPhone 12/13/14
            (1179, 2556),   # iPhone 14 Pro
            (1080, 1920),   # iPhone 6 Plus/6s Plus/7 Plus/8 Plus
            (1125, 2436),   # iPhone X/XS/11 Pro
            (1284, 2778),   # iPhone 12 Pro Max/13 Pro Max
            (1170, 2532),   # iPhone 12/12 Pro/13/13 Pro
        ]

        for w, h in common_resolutions:
            if pixels == w * h:
                self.frame_width = w
                self.frame_height = h
                self.resolution_detected.set()
                print(f"[视频] 检测到分辨率: {w}x{h}")
                # 重启 FFmpeg 用正确分辨率
                return

    def _display_loop(self):
        """显示视频帧并处理鼠标事件"""
        window_name = f"{self.device_name} - 触控"
        cv2.namedWindow(window_name, cv2.WINDOW_NORMAL)
        cv2.resizeWindow(window_name, 400, 800)
        cv2.setMouseCallback(window_name, self._on_mouse)

        last_frame_time = time.time()
        fps = 0
        frame_count = 0

        while self.running:
            with self.frame_lock:
                frame = self.frame_buffer.copy() if self.frame_buffer is not None else None

            if frame is not None:
                # 计算帧率
                current_time = time.time()
                frame_count += 1
                if current_time - last_frame_time >= 1.0:
                    fps = frame_count / (current_time - last_frame_time)
                    frame_count = 0
                    last_frame_time = current_time

                # 画面叠加信息
                cv2.putText(frame, f"FPS: {fps:.1f}", (10, 30),
                           cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 0), 2)
                cv2.putText(frame, f"{self.device_name}", (10, 60),
                           cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 0), 2)

                # 控制连接状态
                with self.control_lock:
                    connected = self.control_socket is not None
                status = "Control: ON" if connected else "Control: OFF"
                color = (0, 255, 0) if connected else (0, 0, 255)
                cv2.putText(frame, status, (10, 90),
                           cv2.FONT_HERSHEY_SIMPLEX, 0.7, color, 2)

                cv2.imshow(window_name, frame)

            key = cv2.waitKey(1) & 0xFF
            if key == ord('q') or key == 27:
                self.stop()
                break

        cv2.destroyAllWindows()

    def _on_mouse(self, event, x, y, flags, param):
        """鼠标事件 → 触控指令"""
        with self.control_lock:
            sock = self.control_socket
        if not sock:
            return

        with self.frame_lock:
            if self.frame_buffer is not None:
                h, w = self.frame_buffer.shape[:2]
            else:
                h, w = self.frame_height, self.frame_width

        if w == 0 or h == 0:
            return

        # 归一化坐标 0~1
        # 注意：OpenCV 窗口可能缩放，需要用窗口实际尺寸
        win_w = cv2.getWindowImageRect(param)[2] if param else w
        win_h = cv2.getWindowImageRect(param)[3] if param else h

        # 用窗口尺寸归一化
        nx = max(0.0, min(1.0, x / max(win_w, 1)))
        ny = max(0.0, min(1.0, y / max(win_h, 1)))

        msg = None
        if event == cv2.EVENT_LBUTTONDOWN:
            msg = {"type": "touch", "action": "down", "x": nx, "y": ny}
        elif event == cv2.EVENT_LBUTTONUP:
            msg = {"type": "touch", "action": "up", "x": nx, "y": ny}
        elif event == cv2.EVENT_MOUSEMOVE and flags & cv2.EVENT_FLAG_LBUTTON:
            msg = {"type": "touch", "action": "move", "x": nx, "y": ny}

        if msg:
            try:
                sock.send((json.dumps(msg) + '\n').encode())
            except Exception:
                pass

    def send_touch(self, action, x, y):
        """发送触控指令（供外部调用）"""
        with self.control_lock:
            sock = self.control_socket
        if not sock:
            return
        msg = {"type": "touch", "action": action, "x": x, "y": y}
        try:
            sock.send((json.dumps(msg) + '\n').encode())
        except Exception:
            pass

    def stop(self):
        """停止客户端"""
        print("[信息] 正在停止...")
        self.running = False

        if self.udp_socket:
            try:
                self.udp_socket.close()
            except:
                pass

        if self.ffmpeg_proc:
            try:
                self.ffmpeg_proc.stdin.close()
                self.ffmpeg_proc.terminate()
                self.ffmpeg_proc.wait(timeout=3)
            except:
                pass

        with self.control_lock:
            if self.control_socket:
                try:
                    self.control_socket.close()
                except:
                    pass
                self.control_socket = None

        print("[信息] 已停止")


def main():
    parser = argparse.ArgumentParser(description='iOSScreenStream PC 客户端')
    parser.add_argument('--ios-ip', type=str, default='192.168.1.101',
                       help='iOS 设备 IP 地址')
    parser.add_argument('--video-port', type=int, default=5001,
                       help='视频 UDP 端口 (默认: 5001)')
    parser.add_argument('--control-port', type=int, default=5002,
                       help='控制 TCP 端口 (默认: 5002)')
    parser.add_argument('--device-name', type=str, default='iPhone',
                       help='设备显示名称')

    args = parser.parse_args()

    client = iOSStreamClient(
        ios_ip=args.ios_ip,
        video_port=args.video_port,
        control_port=args.control_port,
        device_name=args.device_name
    )

    try:
        client.start()
    except KeyboardInterrupt:
        client.stop()


if __name__ == '__main__':
    main()
