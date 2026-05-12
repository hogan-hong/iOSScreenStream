#!/usr/bin/env python3
"""
iOSScreenStream PC 客户端
接收 iOS 设备 H.264 视频流（UDP），通过 TrollVNC 发送触控指令（VNC 协议）
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

# 尝试导入 vncdotool（如果安装了）
try:
    from vncdotool import api
    VNC_AVAILABLE = True
except ImportError:
    VNC_AVAILABLE = False

# UDP 分包协议常量（与 iOS 端一致）
PACKET_HEADER_SIZE = 14  # 2(seq) + 2(totalParts) + 2(partIndex) + 4(totalLen) + 4(offset)
UDP_MAX_PACKET_SIZE = 1400


class VNCClientVNCDoTool:
    """VNC 客户端 - 使用 vncdotool 库发送触控事件"""
    
    def __init__(self, host, port):
        self.host = host
        self.port = port
        self.client = None
        self.connected = False
        self.width = 1920
        self.height = 1080
        
    def connect(self):
        """连接到 VNC 服务器"""
        if not VNC_AVAILABLE:
            print(f"[VNC] vncdotool 库未安装，请运行: pip install vncdotool")
            return False
        
        try:
            print(f"[VNC] 使用 vncdotool 连接到 {self.host}:{self.port}...")
            self.client = api.connect(f"{self.host}:{self.port}")
            self.connected = True
            
            # 获取屏幕尺寸
            screen = self.client.screen
            self.width = screen.width
            self.height = screen.height
            
            print(f"[VNC] 连接成功！分辨率: {self.width}x{self.height}")
            return True
        except Exception as e:
            print(f"[VNC] 连接失败: {e}")
            import traceback
            traceback.print_exc()
            self.connected = False
            return False
    
    def send_pointer_event(self, x, y, button_mask):
        """发送触控事件"""
        if not self.connected or not self.client:
            return False
        
        try:
            # button_mask: 0=松开, 1=按下
            if button_mask == 1:
                # 鼠标按下
                self.client.mouseMove(x, y)
                self.client.mousePress(button=1)  # 左键
                # print(f"[VNC] 鼠标按下 at ({x}, {y})")
            else:
                # 鼠标抬起或移动
                self.client.mouseMove(x, y)
                self.client.mouseRelease(button=1)  # 左键
                # print(f"[VNC] 鼠标抬起 at ({x}, {y})")
            return True
        except Exception as e:
            print(f"[VNC] 发送触控事件失败: {e}")
            self.connected = False
            return False
    
    def disconnect(self):
        """断开连接"""
        if self.client:
            try:
                self.client.disconnect()
            except:
                pass
            self.client = None
        self.connected = False


class VNCClient:
    """VNC 客户端 - 通过 VNC 协议与 TrollVNC 通信发送触控事件"""
    
    def __init__(self, host, port=5900):
        self.host = host
        self.port = port
        self.socket = None
        self.connected = False
        self.width = 1920
        self.height = 1080
        self.version = 3.8
        
    def connect(self):
        """连接到 VNC 服务器"""
        try:
            print(f"[VNC] 连接到 {self.host}:{self.port}...")
            self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            # 移除超时，因为 ServerInit 可能需要较长时间
            self.socket.connect((self.host, self.port))
            print(f"[VNC] TCP 连接已建立")
            
            # VNC 协议握手
            print(f"[VNC] 开始协议握手...")
            self._handshake()
            print(f"[VNC] 握手完成")
            
            print(f"[VNC] 开始认证...")
            self._authenticate()
            print(f"[VNC] 认证完成")
            
            print(f"[VNC] 开始初始化...")
            self._initialize()
            print(f"[VNC] 初始化完成")
            
            self.connected = True
            print(f"[VNC] 连接成功！")
            return True
        except Exception as e:
            print(f"[VNC] 连接失败: {e}")
            import traceback
            traceback.print_exc()
            if self.socket:
                try:
                    self.socket.close()
                except:
                    pass
                self.socket = None
            self.connected = False
            return False
    
    def _handshake(self):
        """VNC 握手 - Protocol Version"""
        # 接收服务器版本
        data = b''
        while len(data) < 12:
            chunk = self.socket.recv(12 - len(data))
            if not chunk:
                raise Exception("VNC 握手失败: 连接关闭")
            data += chunk
        server_version = data.decode()
        print(f"[VNC] 服务器版本: {server_version}")
        
        # 发送客户端版本
        client_version = f"RFB {self.version:03.6f}\n".encode()
        self.socket.send(client_version)
        
        # 接收安全类型
        sec_types_data = b''
        while len(sec_types_data) < 2:
            chunk = self.socket.recv(2 - len(sec_types_data))
            if not chunk:
                raise Exception("VNC 握手失败: 连接关闭")
            sec_types_data += chunk
        
        num_types = sec_types_data[0]
        types = sec_types_data[1:1+num_types]
        print(f"[VNC] 支持的安全类型: {list(types)}")
        
        # 发送选择的安全类型（选择 1 = None）
        if 1 in types:
            self.socket.send(bytes([1]))
        elif 0 in types:  # Invalid
            self.socket.send(bytes([0]))
            reason = self.socket.recv(8)
            raise Exception(f"VNC 握手失败: {reason}")
        else:
            raise Exception(f"不支持的安全类型: {types}")
    
    def _authenticate(self):
        """VNC 认证"""
        # 安全类型 1 (None) 无需认证
        pass
    
    def _initialize(self):
        """VNC 初始化"""
        # 发送 ClientInit 消息
        # ClientInit: shared flag (1 byte) + padding (3 bytes)
        # 尝试使用 shared=0 (不共享)，有些服务器更倾向于这个
        try:
            # 方法 1：shared=1（共享）
            self.socket.send(struct.pack('>Bxxx', 1))
            print(f"[VNC] 发送 ClientInit (shared=1)")
        except:
            pass
        
        # 接收 ServerInit
        try:
            # framebuffer width (2 bytes)
            fb_width_data = self._recv_exact(2)
            framebuffer_width = struct.unpack('>H', fb_width_data)[0]
            print(f"[VNC] Framebuffer width: {framebuffer_width}")
            
            # framebuffer height (2 bytes)
            fb_height_data = self._recv_exact(2)
            framebuffer_height = struct.unpack('>H', fb_height_data)[0]
            print(f"[VNC] Framebuffer height: {framebuffer_height}")
            
            # 像素格式（16字节）
            pixel_format_data = self._recv_exact(16)
            print(f"[VNC] 收到像素格式")
            
            # 服务器名称长度（4字节）
            name_length_data = self._recv_exact(4)
            name_length = struct.unpack('>I', name_length_data)[0]
            print(f"[VNC] 服务器名称长度: {name_length}")
            
            # 服务器名称
            if name_length > 0:
                server_name_data = self._recv_exact(name_length)
                server_name = server_name_data.decode()
            else:
                server_name = ""
            
            self.width = framebuffer_width
            self.height = framebuffer_height
            print(f"[VNC] 屏幕分辨率: {self.width}x{self.height}")
            print(f"[VNC] 服务器名称: {server_name}")
            
            # 设置像素格式
            self._set_pixel_format()
            # 设置编码
            self._set_encodings()
            # 请求 FramebufferUpdate
            self._request_framebuffer_update()
            
        except Exception as e:
            print(f"[VNC] 接收 ServerInit 失败: {e}")
            raise
    
    def _recv_exact(self, n):
        """精确接收 n 字节数据"""
        data = b''
        while len(data) < n:
            chunk = self.socket.recv(n - len(data))
            if not chunk:
                raise Exception(f"连接关闭: 需要接收 {n} 字节，只收到 {len(data)} 字节")
            data += chunk
        return data
    
    def _request_framebuffer_update(self):
        """请求 Framebuffer Update（完成握手）"""
        try:
            # FramebufferUpdateRequest message: 1 byte (type) + 1 byte (incremental) + 2 bytes (x) + 2 bytes (y) + 2 bytes (width) + 2 bytes (height)
            # type=3 (FramebufferUpdateRequest), incremental=0 (不增量更新)
            message = struct.pack('>BBHHHH', 3, 0, 0, 0, self.width, self.height)
            self.socket.send(message)
            print(f"[VNC] 已请求 FramebufferUpdate")
        except Exception as e:
            print(f"[VNC] 请求 FramebufferUpdate 失败: {e}")
    
    def _set_pixel_format(self):
        """设置像素格式（使用 32-bit RGB）"""
        try:
            # SetPixelFormat message: 1 byte (type) + 3 bytes (padding) + 16 bytes (format)
            message = struct.pack('>Bxxx', 0)  # type=0 (SetPixelFormat)
            
            # Pixel format (16 bytes)
            # bits-per-pixel, depth, big-endian, true-color
            format_data = struct.pack('>BBBB', 32, 24, 0, 1)
            
            # red-max, green-max, blue-max
            format_data += struct.pack('>HHH', 255, 255, 255)
            
            # red-shift, green-shift, blue-shift
            format_data += struct.pack('>BBB', 16, 8, 0)
            
            # padding[3]
            format_data += b'\x00\x00\x00'
            
            message += format_data
            self.socket.send(message)
            print(f"[VNC] 已设置像素格式")
        except Exception as e:
            print(f"[VNC] 设置像素格式失败: {e}")
    
    def _set_encodings(self):
        """设置支持的编码（只使用 Raw）"""
        try:
            # SetEncodings message: 1 byte (type) + 1 byte (padding) + 2 bytes (num-encodings)
            encodings = [0]  # 0 = Raw encoding
            message = struct.pack('>BBH', 2, 0, len(encodings))  # type=2 (SetEncodings)
            
            # 每个编码 4 bytes (int32)
            for enc in encodings:
                message += struct.pack('>I', enc)
            
            self.socket.send(message)
            print(f"[VNC] 已设置编码: Raw")
        except Exception as e:
            print(f"[VNC] 设置编码失败: {e}")
    
    def send_pointer_event(self, x, y, button_mask):
        """发送 VNC PointerEvent（触控事件）"""
        if not self.connected or not self.socket:
            return False
        
        try:
            # VNC PointerEvent: 1 byte (button_mask) + 2 bytes (x) + 2 bytes (y)
            # button_mask: 1=左键按下, 2=中键, 4=右键, 8=向上滚轮, 16=向下滚轮
            message = struct.pack('>BHH', button_mask, int(x), int(y))
            self.socket.send(message)
            return True
        except Exception as e:
            print(f"[VNC] 发送触控事件失败: {e}")
            self.connected = False
            return False
    
    def disconnect(self):
        """断开连接"""
        if self.socket:
            try:
                self.socket.close()
            except:
                pass
            self.socket = None
        self.connected = False


class iOSStreamClient:
    def __init__(self, ios_ip="192.168.1.101", video_port=5001, control_port=5002, 
                 device_name="iPhone", vnc_port=5900, enable_vnc_control=True):
        self.ios_ip = ios_ip
        self.video_port = video_port
        self.control_port = control_port
        self.device_name = device_name
        self.running = True

        # VNC 客户端（用于触控控制）
        self.enable_vnc_control = enable_vnc_control
        self.vnc_port = vnc_port
        
        # 优先使用 vncdotool 库（更稳定），如果不可用则使用自定义实现
        if enable_vnc_control:
            if VNC_AVAILABLE:
                self.vnc_client = VNCClientVNCDoTool(ios_ip, vnc_port)
                self.vnc_implementation = "vncdotool"
            else:
                print("[VNC] vncdotool 未安装，使用自定义 VNC 实现")
                self.vnc_client = VNCClient(ios_ip, vnc_port)
                self.vnc_implementation = "custom"
        else:
            self.vnc_client = None
            self.vnc_implementation = None

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
        self.reassembly_timeout = 2.0  # 分包重组超时（秒），超时丢弃

        # FFmpeg 写入队列（避免阻塞 UDP 接收线程）
        self._ffmpeg_queue = []
        self._ffmpeg_queue_lock = threading.Lock()
        self._ffmpeg_queue_event = threading.Event()

        # SPS/PPS 跟踪（未收到关键帧前持续请求）
        self._sps_received = False
        self._keyframe_request_count = 0
        self._max_keyframe_requests = 30  # 最多请求30次（约15秒）

        # 控制连接
        self.control_socket = None
        self.control_lock = threading.Lock()
        
        # 帧新鲜度检测
        self.last_frame_time = 0  # 上次收到新帧的时间
        self.video_stalled = False

    def start(self):
        """启动客户端"""
        print(f"[信息] 连接 iOS 设备: {self.ios_ip}")
        print(f"[信息] 视频端口(UDP): {self.video_port}, 控制端口(TCP): {self.control_port}")
        
        # 连接 VNC 服务器（用于触控控制）
        if self.enable_vnc_control and self.vnc_client:
            if self.vnc_client.connect():
                print(f"[信息] TrollVNC 触控控制已启用")
            else:
                print(f"[警告] TrollVNC 连接失败，触控控制不可用")

        # 先连接 TCP 控制通道（PC 主动连 iOS 端监听的端口）
        if not self._connect_control():
            print("[错误] 无法连接控制端口，1秒后重试...")

        # 启动视频接收
        video_thread = threading.Thread(target=self._video_receiver, daemon=True)
        video_thread.start()

        # 启动控制保活
        control_thread = threading.Thread(target=self._control_keeper, daemon=True)
        control_thread.start()

        # 立即启动 FFmpeg 解码（不等分辨率检测，让 FFmpeg 自己从流中检测）
        print("[信息] 启动 FFmpeg 解码器...")
        self._start_ffmpeg()

        # 从 FFmpeg stderr 读取分辨率
        res_thread = threading.Thread(target=self._ffmpeg_resolution_detector, daemon=True)
        res_thread.start()

        # 启动帧读取
        reader_thread = threading.Thread(target=self._ffmpeg_reader, daemon=True)
        reader_thread.start()

        # 启动 FFmpeg 写入线程（从队列取 NAL 写入 FFmpeg stdin）
        writer_thread = threading.Thread(target=self._ffmpeg_writer, daemon=True)
        writer_thread.start()

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
            # 连接成功后立即请求关键帧，确保视频流从 IDR 帧开始
            self._request_keyframe()
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
        # 设置 SO_REUSEADDR，避免关闭后端口 TIME_WAIT 导致二次启动灰屏
        self.udp_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.udp_socket.bind(('0.0.0.0', self.video_port))
        self.udp_socket.settimeout(1.0)

        print(f"[视频] 监听 UDP 端口 {self.video_port}")

        # 调试计数
        _dbg_count = 0
        _dbg_first5 = []

        while self.running:
            try:
                data, addr = self.udp_socket.recvfrom(65536)
                if not data:
                    continue

                _dbg_count += 1
                if _dbg_count <= 20:
                    print(f"[DEBUG] UDP包#{_dbg_count} 来自{addr} 长度={len(data)} 前20字节={data[:20].hex()}")
                elif _dbg_count == 21:
                    print(f"[DEBUG] 已收到{_dbg_count}个UDP包，后续不再打印...")

                # 统一 14 字节头格式：seq(2) + totalParts(2) + partIndex(2) + totalLen(4) + offset(4)
                if len(data) >= PACKET_HEADER_SIZE:
                    seq, total_parts, part_index, total_len, offset = struct.unpack(
                        '>HHHII', data[:PACKET_HEADER_SIZE]
                    )
                    payload = data[PACKET_HEADER_SIZE:]
                    
                    if _dbg_count <= 20:
                        print(f"[DEBUG] 解析头: seq={seq} totalParts={total_parts} partIndex={part_index} totalLen={total_len} offset={offset} payloadLen={len(payload)}")
                    
                    if total_parts == 1:
                        # 小包，直接取 payload
                        self._process_nal_data(payload)
                    else:
                        # 大包，需重组
                        nal_data = self._reassemble_packet(seq, total_parts, part_index, total_len, offset, payload)
                        if nal_data:
                            self._process_nal_data(nal_data)
                else:
                    # 兼容旧格式：2字节序号 + 数据
                    if len(data) >= 2:
                        nal_data = data[2:]
                        self._process_nal_data(nal_data)

            except socket.timeout:
                continue
            except Exception as e:
                if self.running:
                    print(f"[视频] 接收错误: {e}")

    def _reassemble_packet(self, seq, total_parts, part_index, total_len, offset, payload):
        """重组分包数据"""
        now = time.time()

        if seq not in self.packet_buffer:
            self.packet_buffer[seq] = {
                'parts': {},
                'total_parts': total_parts,
                'total_len': total_len,
                'timestamp': now
            }

        buf = self.packet_buffer[seq]
        buf['parts'][part_index] = (offset, payload)

        if not hasattr(self, '_reassemble_dbg_count'):
            self._reassemble_dbg_count = 0
        self._reassemble_dbg_count += 1
        if self._reassemble_dbg_count <= 10:
            print(f"[DEBUG] 重组 seq={seq} part={part_index}/{total_parts} offset={offset} payloadLen={len(payload)} 已收={len(buf['parts'])}个")

        # 清理超时的分包（缩短到2秒，避免积压占用内存）
        expired = [k for k, v in self.packet_buffer.items() if now - v['timestamp'] > self.reassembly_timeout]
        for k in expired:
            del self.packet_buffer[k]

        # 检查是否收齐
        if len(buf['parts']) >= buf['total_parts']:
            # 按 offset 排序拼接
            result = bytearray(buf['total_len'])
            for idx in sorted(buf['parts'].keys()):
                off, part_data = buf['parts'][idx]
                end = min(off + len(part_data), buf['total_len'])
                if off < buf['total_len']:
                    result[off:end] = part_data[:end - off]

            del self.packet_buffer[seq]
            print(f"[DEBUG] 重组完成 seq={seq} totalLen={buf['total_len']}")
            return bytes(result[:buf['total_len']])

        return None

    def _process_nal_data(self, nal_data):
        """处理 NAL 数据，检测分辨率，喂给 FFmpeg"""
        if not nal_data or len(nal_data) < 5:
            return

        # 检测 NAL 类型
        # 跳过 Annex B start code (00 00 00 01) 找到 NAL header
        nal_offset = 0
        if nal_data[0:4] == b'\x00\x00\x00\x01':
            nal_offset = 4
        elif nal_data[0:3] == b'\x00\x00\x01':
            nal_offset = 3
        
        if nal_offset >= len(nal_data):
            return

        nal_type_byte = nal_data[nal_offset]
        h264_nal_type = (nal_type_byte >> 0) & 0x1F

        # 调试：前20次打印 NAL 信息
        if not hasattr(self, '_nal_dbg_count'):
            self._nal_dbg_count = 0
        self._nal_dbg_count += 1
        if self._nal_dbg_count <= 20:
            print(f"[DEBUG] NAL#{self._nal_dbg_count} 长度={len(nal_data)} NAL_type={h264_nal_type} 前20字节={nal_data[:20].hex()}")

        # 检测 SPS/PPS/IDR
        if h264_nal_type == 7:  # SPS
            self._sps_received = True
            print(f"[视频] 收到 SPS (序列参数集)，长度={len(nal_data)}")
        elif h264_nal_type == 8:  # PPS
            print(f"[视频] 收到 PPS (图像参数集)，长度={len(nal_data)}")
        elif h264_nal_type == 5:  # IDR 关键帧
            print(f"[视频] 收到 IDR 关键帧，长度={len(nal_data)}")
        elif h264_nal_type == 1:  # P 帧
            # 未收到 SPS/PPS 时丢弃 P 帧（FFmpeg 无法解码）
            if not self._sps_received:
                if self._nal_dbg_count <= 30:
                    print(f"[视频] 丢弃 P 帧（尚未收到 SPS/PPS），请求关键帧...")
                # 持续请求关键帧直到收到
                self._request_keyframe_periodic()
                return

        # 检测 SPS 以获取分辨率
        if h264_nal_type == 7:
            self._detect_resolution_from_sps(nal_data[nal_offset:])
        elif h264_nal_type in (0x20, 0x21):  # HEVC VPS/SPS
            self._detect_resolution_from_hevc_sps(nal_data[nal_offset:])

        # 异步写入 FFmpeg（避免阻塞 UDP 接收线程）
        with self._ffmpeg_queue_lock:
            self._ffmpeg_queue.append(nal_data)
        self._ffmpeg_queue_event.set()

    def _request_keyframe_periodic(self):
        """持续请求关键帧，直到收到 SPS/PPS 或达到最大请求次数"""
        if self._sps_received:
            return
        if self._keyframe_request_count >= self._max_keyframe_requests:
            if self._keyframe_request_count == self._max_keyframe_requests:
                print(f"[警告] 已请求关键帧{self._max_keyframe_requests}次仍未收到 SPS/PPS")
            self._keyframe_request_count += 1
            return
        self._keyframe_request_count += 1
        if self._keyframe_request_count <= 5 or self._keyframe_request_count % 10 == 0:
            print(f"[控制] 请求关键帧 (第{self._keyframe_request_count}次)")
        self._request_keyframe()

    def _detect_resolution_from_sps(self, sps_data):
        """从 H.264 SPS 中解析分辨率（简易版）"""
        pass  # FFmpeg 自动探测更可靠

    def _detect_resolution_from_hevc_sps(self, sps_data):
        """从 HEVC SPS 中解析分辨率（简易版）"""
        pass  # FFmpeg 自动探测更可靠

    def _start_ffmpeg(self):
        """启动 FFmpeg 解码进程"""
        cmd = [
            'ffmpeg',
            '-probesize', '32768',  # 需要足够大以包含 SPS/PPS
            '-analyzeduration', '1000000',  # 1秒分析时长，加速启动
            '-flags', 'low_delay',
            '-fflags', 'nobuffer',
            '-fflags', 'discardcorrupt',
            '-max_delay', '500000',
            '-f', 'h264',  # 输入 Annex B H.264
            '-i', 'pipe:0',
            '-f', 'rawvideo',
            '-pix_fmt', 'bgr24',
            '-vf', 'fps=30',  # 稳定输出帧率
            'pipe:1'
        ]

        self.ffmpeg_proc = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        print("[视频] FFmpeg 解码器已启动")

    def _ffmpeg_resolution_detector(self):
        """从 FFmpeg stderr 检测分辨率"""
        if not self.ffmpeg_proc or not self.ffmpeg_proc.stderr:
            return
        try:
            # FFmpeg 在开始解码时会输出流信息到 stderr
            # 格式如: Stream #0:0: Video: h264, ... 750x1334, ...
            # 策略：先读完一整块数据再匹配，避免 750x133 这种部分匹配
            import re
            buf = b''
            while self.running and self.ffmpeg_proc.stderr:
                chunk = self.ffmpeg_proc.stderr.read(1)
                if not chunk:
                    break
                buf += chunk
                # 等 'x' 后面至少读够4位数字再尝试匹配
                text = buf.decode('utf-8', errors='ignore')
                # 在 Stream 行的上下文中找分辨率：必须有逗号或空格跟在后面
                m = re.search(r'(\d{3,4})x(\d{3,4})[\s,\[]', text)
                if m and not self.resolution_detected.is_set():
                    w, h = int(m.group(1)), int(m.group(2))
                    # 验证：宽高至少 100，且乘积合理
                    if w >= 100 and h >= 100 and w * h < 10000000:
                        self.frame_width = w
                        self.frame_height = h
                        self.resolution_detected.set()
                        print(f"[信息] FFmpeg 检测到分辨率: {w}x{h}")
                        return
                # 限制 buf 大小
                if len(buf) > 8192:
                    buf = buf[-4096:]
        except Exception as e:
            print(f"[视频] 分辨率检测异常: {e}")

        # 如果从 stderr 没检测到，用默认值
        if not self.resolution_detected.is_set():
            self.frame_width = 750
            self.frame_height = 1334
            self.resolution_detected.set()
            print("[警告] 未从 FFmpeg 检测到分辨率，使用默认值 750x1334")

    def _ffmpeg_reader(self):
        """从 FFmpeg 读取解码后的帧"""
        consecutive_errors = 0
        max_consecutive_errors = 5
        
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
                        consecutive_errors = 0
                        frame = np.frombuffer(raw, dtype=np.uint8).reshape(
                            (self.frame_height, self.frame_width, 3)
                        )
                        with self.frame_lock:
                            self.frame_buffer = frame.copy()
                    elif len(raw) == 0:
                        print("[视频] FFmpeg 已退出")
                        break
                    else:
                        consecutive_errors += 1
                        if consecutive_errors <= max_consecutive_errors:
                            # 分辨率可能不对，尝试其他常见分辨率
                            self._try_detect_resolution(raw)
                        else:
                            # 多次失败，丢弃这些字节并重试
                            # 可能是分辨率切换导致的，丢弃残留数据
                            pass
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

    def _ffmpeg_writer(self):
        """从队列取 NAL 数据写入 FFmpeg stdin（异步，避免阻塞 UDP 接收线程）"""
        while self.running:
            # 等待队列有数据
            self._ffmpeg_queue_event.wait(timeout=0.5)
            self._ffmpeg_queue_event.clear()

            # 批量取出所有待写数据
            with self._ffmpeg_queue_lock:
                batch = self._ffmpeg_queue[:]
                self._ffmpeg_queue.clear()

            if not batch or not self.ffmpeg_proc or not self.ffmpeg_proc.stdin:
                continue

            try:
                for nal_data in batch:
                    self.ffmpeg_proc.stdin.write(nal_data)
                self.ffmpeg_proc.stdin.flush()
            except BrokenPipeError:
                print("[视频] FFmpeg stdin 已关闭")
                break
            except Exception as e:
                if self.running:
                    print(f"[视频] FFmpeg 写入错误: {e}")
                break

    def _display_loop(self):
        """显示视频帧并处理鼠标事件"""
        window_name = f"{self.device_name} - 触控"
        cv2.namedWindow(window_name, cv2.WINDOW_NORMAL)

        # 按视频实际比例设置窗口大小（等分辨率检测后调整）
        # 初始先用一个合理比例，检测到后自动调整
        cv2.resizeWindow(window_name, 375, 667)  # iPhone SE2 比例 750:1334
        cv2.setMouseCallback(window_name, self._on_mouse)

        last_frame_time = time.time()
        fps = 0
        frame_count = 0
        last_resize_w = 0  # 跟踪上次窗口调整时的分辨率，避免重复调整
        last_resize_h = 0

        while self.running:
            # 分辨率变化时重新调整窗口比例
            if self.frame_width > 0 and self.frame_height > 0:
                if self.frame_width != last_resize_w or self.frame_height != last_resize_h:
                    # 保持宽度约 400px，按比例算高度
                    disp_w = 400
                    disp_h = int(disp_w * self.frame_height / self.frame_width)
                    cv2.resizeWindow(window_name, disp_w, disp_h)
                    last_resize_w = self.frame_width
                    last_resize_h = self.frame_height

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
        """鼠标事件 → 触控指令（通过 TrollVNC 或 iOS 端）

        坐标映射：
        - WINDOW_NORMAL 模式下，OpenCV 会在窗口内保持视频比例，可能有黑边
        - getWindowImageRect 返回的是窗口整体尺寸（含黑边），不是画面区域
        - 所以需要根据 frame 和窗口的比例来正确映射坐标
        """
        
        # 如果启用了 VNC 控制且已连接，通过 VNC 发送触控事件
        if self.enable_vnc_control and self.vnc_client and self.vnc_client.connected:
            self._send_vnc_touch(event, x, y, flags, param)
            return
        
        # 否则，不发送任何触控事件（避免触发 iOS 端的 TouchController 导致崩溃）
        # 如果需要回退到 iOS 端触控控制，需要先修复 TouchController
        return
    
    def _send_vnc_touch(self, event, x, y, flags, param):
        """通过 VNC 发送触控事件"""
        with self.frame_lock:
            if self.frame_buffer is not None:
                frame_h, frame_w = self.frame_buffer.shape[:2]
            else:
                frame_h, frame_w = self.frame_height, self.frame_width

        if frame_w == 0 or frame_h == 0:
            return

        # 获取窗口尺寸
        try:
            rect = cv2.getWindowImageRect(param)
            win_w, win_h = rect[2], rect[3]
        except Exception:
            win_w, win_h = frame_w, frame_h

        # WINDOW_NORMAL 模式下，OpenCV 在窗口内保持视频宽高比，可能有黑边
        # 计算画面实际显示区域（缩放后的尺寸和偏移）
        scale = min(win_w / frame_w, win_h / frame_h)
        display_w = frame_w * scale
        display_h = frame_h * scale
        offset_x = (win_w - display_w) / 2.0
        offset_y = (win_h - display_h) / 2.0

        # 把鼠标坐标转换为画面坐标（减去黑边偏移）
        img_x = x - offset_x
        img_y = y - offset_y

        # 归一化到 0~1（基于画面尺寸而非窗口尺寸）
        nx = max(0.0, min(1.0, img_x / max(display_w, 1)))
        ny = max(0.0, min(1.0, img_y / max(display_h, 1)))

        # 如果点击在黑边区域，忽略
        if img_x < 0 or img_x > display_w or img_y < 0 or img_y > display_h:
            return

        # 映射到 VNC 坐标系（基于 TrollVNC 报告的屏幕分辨率）
        vnc_x = int(nx * self.vnc_client.width)
        vnc_y = int(ny * self.vnc_client.height)

        # 发送 VNC PointerEvent
        if event == cv2.EVENT_LBUTTONDOWN:
            self.vnc_client.send_pointer_event(vnc_x, vnc_y, 1)  # 按下
            print(f"[触控] VNC down at ({vnc_x}, {vnc_y})")
        elif event == cv2.EVENT_LBUTTONUP:
            self.vnc_client.send_pointer_event(vnc_x, vnc_y, 0)  # 抬起
            print(f"[触控] VNC up at ({vnc_x}, {vnc_y})")
        elif event == cv2.EVENT_MOUSEMOVE and flags & cv2.EVENT_FLAG_LBUTTON:
            self.vnc_client.send_pointer_event(vnc_x, vnc_y, 0)  # 移动
        # 其他事件（右键、滚轮）暂时不支持 VNC

    def _request_keyframe(self):
        """向 iOS 端请求关键帧（IDR），用于重新连接时获取完整视频帧"""
        with self.control_lock:
            sock = self.control_socket
        if not sock:
            return
        try:
            msg = json.dumps({"type": "request_keyframe"}) + "\n"
            sock.send(msg.encode())
        except Exception as e:
            if self._keyframe_request_count <= 3:
                print(f"[控制] 请求关键帧失败: {e}")

    def send_touch(self, action, x, y):
        """发送触控指令（通过 TrollVNC）"""
        if not self.enable_vnc_control or not self.vnc_client or not self.vnc_client.connected:
            if self.enable_vnc_control:
                print(f"[触控] VNC 未连接，触控不可用")
            return
        
        # VNC button_mask: 0=松开, 1=左键按下, 2=中键, 4=右键
        button_mask = 0
        if action == "down":
            button_mask = 1  # 左键按下
        # "up" 和 "move" 都是 button_mask=0
        
        success = self.vnc_client.send_pointer_event(x, y, button_mask)
        if success:
            print(f"[触控] VNC 事件: {action} at ({x}, {y})")
        else:
            print(f"[触控] VNC 发送失败: {action} at ({x}, {y})")

    def stop(self):
        """停止客户端"""
        print("[信息] 正在停止...")
        self.running = False

        # 关闭 VNC 连接
        if self.vnc_client:
            self.vnc_client.disconnect()

        # 关闭 UDP socket
        if self.udp_socket:
            try:
                self.udp_socket.close()
            except:
                pass
            self.udp_socket = None

        # 彻底终止 FFmpeg 进程
        if self.ffmpeg_proc:
            try:
                if self.ffmpeg_proc.stdin:
                    self.ffmpeg_proc.stdin.close()
            except:
                pass
            try:
                if self.ffmpeg_proc.stdout:
                    self.ffmpeg_proc.stdout.close()
            except:
                pass
            try:
                if self.ffmpeg_proc.stderr:
                    self.ffmpeg_proc.stderr.close()
            except:
                pass
            try:
                self.ffmpeg_proc.terminate()
                self.ffmpeg_proc.wait(timeout=3)
            except:
                try:
                    self.ffmpeg_proc.kill()
                except:
                    pass
            self.ffmpeg_proc = None

        # 关闭控制连接
        with self.control_lock:
            if self.control_socket:
                try:
                    self.control_socket.close()
                except:
                    pass
                self.control_socket = None

        # 清理状态，确保重新启动时不会残留旧数据
        with self.frame_lock:
            self.frame_buffer = None
        self.frame_width = 0
        self.frame_height = 0
        self.resolution_detected.clear()
        with self._ffmpeg_queue_lock:
            self._ffmpeg_queue.clear()
        self.packet_buffer.clear()

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
    parser.add_argument('--vnc-port', type=int, default=5900,
                       help='TrollVNC 端口 (默认: 5900)')
    parser.add_argument('--enable-vnc-control', action='store_true', default=True,
                       help='启用 TrollVNC 触控控制 (默认: True)')
    parser.add_argument('--disable-vnc-control', action='store_true',
                       help='禁用 TrollVNC 触控控制')

    args = parser.parse_args()

    # 处理 VNC 控制参数
    enable_vnc = args.enable_vnc_control and not args.disable_vnc_control

    client = iOSStreamClient(
        ios_ip=args.ios_ip,
        video_port=args.video_port,
        control_port=args.control_port,
        device_name=args.device_name,
        vnc_port=args.vnc_port,
        enable_vnc_control=enable_vnc
    )

    try:
        client.start()
    except KeyboardInterrupt:
        client.stop()


if __name__ == '__main__':
    main()
