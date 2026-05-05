/*
 * iOSScreenStream - 流服务端实现
 * 修复：TCP 控制通道改为 iOS 端监听（PC 连入发指令）
 * 新增：UDP 视频分包、心跳保活、TCP 数据边界处理
 */

#import "StreamServer.h"
#import "Logging.h"
#import <UIKit/UIKit.h>

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <fcntl.h>

// UDP 分包：每个包最大 1400 字节（安全低于 MTU）
#define UDP_MAX_PACKET_SIZE 1400
// 分包头：4字节总长度 + 4字节偏移 + 4字节分包长度 + 2字节序号
#define PACKET_HEADER_SIZE 14

// 心跳间隔（秒）
#define HEARTBEAT_INTERVAL 5.0

@interface StreamServer () <NSStreamDelegate>
@end

@implementation StreamServer {
    NSString *mServerIP;
    int mVideoPort;
    int mControlPort;
    BOOL mIsRunning;
    
    // UDP 视频发送
    int mUdpSocket;
    struct sockaddr_in mServerAddr;
    uint16_t mPacketSeq;  // 分包序号
    
    // TCP 控制通道（iOS 端监听）
    int mTcpListenSocket;
    int mTcpClientSocket;
    NSMutableData *mReceivedData;
    NSTimer *mHeartbeatTimer;
    
    // 重连检测
    NSDate *mLastHeartbeat;
}

- (instancetype)initWithServerIP:(NSString *)ip videoPort:(int)videoPort controlPort:(int)controlPort {
    self = [super init];
    if (self) {
        mServerIP = ip;
        mVideoPort = videoPort;
        mControlPort = controlPort;
        mIsRunning = NO;
        mUdpSocket = -1;
        mTcpListenSocket = -1;
        mTcpClientSocket = -1;
        mReceivedData = [NSMutableData data];
        mPacketSeq = 0;
        mHeartbeatTimer = nil;
        mLastHeartbeat = nil;
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

- (BOOL)isRunning { return mIsRunning; }
- (NSString *)serverIP { return mServerIP; }
- (int)videoPort { return mVideoPort; }
- (int)controlPort { return mControlPort; }

- (BOOL)start {
    if (mIsRunning) return YES;
    
    // 创建 UDP socket 用于视频推流
    mUdpSocket = socket(AF_INET, SOCK_DGRAM, 0);
    if (mUdpSocket < 0) {
        TVLog(@"创建 UDP socket 失败");
        return NO;
    }
    
    // 设置发送缓冲区
    int sendBufSize = 256 * 1024;
    setsockopt(mUdpSocket, SOL_SOCKET, SO_SNDBUF, &sendBufSize, sizeof(sendBufSize));
    
    // 设置目标地址
    memset(&mServerAddr, 0, sizeof(mServerAddr));
    mServerAddr.sin_family = AF_INET;
    mServerAddr.sin_port = htons(mVideoPort);
    inet_pton(AF_INET, [mServerIP UTF8String], &mServerAddr.sin_addr);
    
    // 连接 UDP（方便用 send 而非 sendto）
    if (connect(mUdpSocket, (struct sockaddr *)&mServerAddr, sizeof(mServerAddr)) < 0) {
        TVLog(@"UDP connect 失败");
        close(mUdpSocket);
        mUdpSocket = -1;
        return NO;
    }
    
    // 启动 TCP 监听（iOS 端作为服务端，等待 PC 连入）
    if (![self startTcpListen]) {
        close(mUdpSocket);
        mUdpSocket = -1;
        return NO;
    }
    
    mIsRunning = YES;
    TVLog(@"流服务已启动: 视频→%@:%d(UDP), 控制监听:%d(TCP)", mServerIP, mVideoPort, mControlPort);
    return YES;
}

#pragma mark - TCP 监听（控制通道）

- (BOOL)startTcpListen {
    mTcpListenSocket = socket(AF_INET, SOCK_STREAM, 0);
    if (mTcpListenSocket < 0) {
        TVLog(@"创建 TCP 监听 socket 失败");
        return NO;
    }
    
    // 允许端口复用
    int reuse = 1;
    setsockopt(mTcpListenSocket, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
    
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons(mControlPort);
    
    if (bind(mTcpListenSocket, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        TVLog(@"TCP bind 失败 (端口 %d)", mControlPort);
        close(mTcpListenSocket);
        mTcpListenSocket = -1;
        return NO;
    }
    
    if (listen(mTcpListenSocket, 1) < 0) {
        TVLog(@"TCP listen 失败");
        close(mTcpListenSocket);
        mTcpListenSocket = -1;
        return NO;
    }
    
    // 设为非阻塞，用 GCD 定时轮询接受连接
    int flags = fcntl(mTcpListenSocket, F_GETFL, 0);
    fcntl(mTcpListenSocket, F_SETFL, flags | O_NONBLOCK);
    
    TVLog(@"TCP 控制端口监听中: %d", mControlPort);
    
    // 启动轮询线程接受连接 + 读数据
    [self startPollingRead];
    
    return YES;
}

- (void)startPollingRead {
    // 使用 GCD 定时器轮询 TCP 连接和数据
    dispatch_queue_t pollQueue = dispatch_queue_create("com.iosscreenstream.tcpoll", DISPATCH_QUEUE_SERIAL);
    
    dispatch_async(pollQueue, ^{
        while (self->mIsRunning) {
            // 如果没有客户端连接，尝试 accept
            if (self->mTcpClientSocket < 0 && self->mTcpListenSocket >= 0) {
                struct sockaddr_in clientAddr;
                socklen_t clientLen = sizeof(clientAddr);
                int clientFd = accept(self->mTcpListenSocket, (struct sockaddr *)&clientAddr, &clientLen);
                if (clientFd >= 0) {
                    self->mTcpClientSocket = clientFd;
                    // 设为非阻塞
                    int flags = fcntl(clientFd, F_GETFL, 0);
                    fcntl(clientFd, F_SETFL, flags | O_NONBLOCK);
                    
                    char clientIP[INET_ADDRSTRLEN];
                    inet_ntop(AF_INET, &clientAddr.sin_addr, clientIP, sizeof(clientIP));
                    TVLog(@"PC 控制端已连接: %s:%d", clientIP, ntohs(clientAddr.sin_port));
                    
                    // 启动心跳
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self startHeartbeat];
                    });
                }
            }
            
            // 读取客户端数据
            if (self->mTcpClientSocket >= 0) {
                uint8_t buffer[4096];
                ssize_t bytesRead = recv(self->mTcpClientSocket, buffer, sizeof(buffer), 0);
                if (bytesRead > 0) {
                    @synchronized(self->mReceivedData) {
                        [self->mReceivedData appendBytes:buffer length:bytesRead];
                    }
                    [self processReceivedData];
                } else if (bytesRead == 0) {
                    // 客户端断开
                    TVLog(@"PC 控制端断开连接");
                    close(self->mTcpClientSocket);
                    self->mTcpClientSocket = -1;
                    [self stopHeartbeat];
                } else {
                    // EAGAIN/EWOULDBLOCK = 暂无数据，正常
                    if (errno != EAGAIN && errno != EWOULDBLOCK) {
                        TVLog(@"TCP 读取错误: %s", strerror(errno));
                        close(self->mTcpClientSocket);
                        self->mTcpClientSocket = -1;
                        [self stopHeartbeat];
                    }
                }
            }
            
            usleep(10000); // 10ms 轮询间隔
        }
    });
}

#pragma mark - 心跳保活

- (void)startHeartbeat {
    [self stopHeartbeat];
    mLastHeartbeat = [NSDate date];
    mHeartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:HEARTBEAT_INTERVAL
                                                       target:self
                                                     selector:@selector(sendHeartbeat)
                                                     userInfo:nil
                                                      repeats:YES];
}

- (void)stopHeartbeat {
    if (mHeartbeatTimer) {
        [mHeartbeatTimer invalidate];
        mHeartbeatTimer = nil;
    }
}

- (void)sendHeartbeat {
    if (mTcpClientSocket < 0) return;
    
    // 发送心跳包
    NSData *heartbeat = [@"{\"type\":\"heartbeat\"}\n" dataUsingEncoding:NSUTF8StringEncoding];
    ssize_t sent = send(mTcpClientSocket, heartbeat.bytes, heartbeat.length, 0);
    if (sent <= 0) {
        TVLog(@"心跳发送失败，连接可能已断开");
        close(mTcpClientSocket);
        mTcpClientSocket = -1;
        [self stopHeartbeat];
    }
}

#pragma mark - UDP 视频分包发送

- (void)sendVideoData:(NSData *)data isKeyFrame:(BOOL)isKeyFrame {
    if (!mIsRunning || mUdpSocket < 0) return;
    
    NSUInteger totalLength = data.length;
    const uint8_t *dataBytes = (const uint8_t *)data.bytes;
    
    if (totalLength <= UDP_MAX_PACKET_SIZE - PACKET_HEADER_SIZE) {
        // 小包：加序号头直接发
        uint16_t seq = mPacketSeq++;
        NSMutableData *packet = [NSMutableData dataWithCapacity:2 + totalLength];
        [packet appendBytes:&seq length:2];
        [packet appendBytes:dataBytes length:totalLength];
        send(mUdpSocket, packet.bytes, packet.length, 0);
    } else {
        // 大包：分包发送
        uint16_t seq = mPacketSeq++;
        NSUInteger payloadSize = UDP_MAX_PACKET_SIZE - PACKET_HEADER_SIZE;
        NSUInteger offset = 0;
        uint16_t partIndex = 0;
        uint16_t totalParts = (uint16_t)((totalLength + payloadSize - 1) / payloadSize);
        
        while (offset < totalLength) {
            NSUInteger chunkLen = MIN(payloadSize, totalLength - offset);
            
            NSMutableData *packet = [NSMutableData dataWithCapacity:PACKET_HEADER_SIZE + chunkLen];
            
            // 分包头
            uint32_t totalLenNet = htonl((uint32_t)totalLength);
            uint32_t offsetNet = htonl((uint32_t)offset);
            [packet appendBytes:&seq length:2];           // 2字节序号
            [packet appendBytes:&totalParts length:2];     // 2字节总分包数
            [packet appendBytes:&partIndex length:2];      // 2字节当前分包索引
            [packet appendBytes:&totalLenNet length:4];    // 4字节总长度
            [packet appendBytes:&offsetNet length:4];      // 4字节偏移
            
            // 数据
            [packet appendBytes:dataBytes + offset length:chunkLen];
            
            ssize_t sent = send(mUdpSocket, packet.bytes, packet.length, 0);
            if (sent < 0) {
                TVLog(@"UDP 分包发送失败: part %d/%d", partIndex, totalParts);
                break;
            }
            
            offset += chunkLen;
            partIndex++;
        }
    }
}

- (void)stop {
    if (!mIsRunning) return;
    
    [self stopHeartbeat];
    
    if (mUdpSocket >= 0) {
        close(mUdpSocket);
        mUdpSocket = -1;
    }
    if (mTcpClientSocket >= 0) {
        close(mTcpClientSocket);
        mTcpClientSocket = -1;
    }
    if (mTcpListenSocket >= 0) {
        close(mTcpListenSocket);
        mTcpListenSocket = -1;
    }
    
    mIsRunning = NO;
    TVLog(@"流服务已停止");
}

#pragma mark - TCP 数据解析

- (void)processReceivedData {
    @synchronized(mReceivedData) {
        NSData *data = [mReceivedData copy];
        [mReceivedData setLength:0];
        
        NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!string) {
            // 可能是不完整的 UTF-8，保留数据
            [mReceivedData appendData:data];
            return;
        }
        
        // 按换行符分割完整 JSON 消息
        NSArray *lines = [string componentsSeparatedByString:@"\n"];
        
        // 最后一段可能不完整（没有换行符结尾）
        BOOL lastComplete = [string hasSuffix:@"\n"];
        
        for (NSUInteger i = 0; i < lines.count; i++) {
            NSString *line = lines[i];
            
            // 最后一段不完整，保留
            if (i == lines.count - 1 && !lastComplete) {
                if (line.length > 0) {
                    [mReceivedData appendData:[line dataUsingEncoding:NSUTF8StringEncoding]];
                }
                continue;
            }
            
            if (line.length == 0) continue;
            
            NSError *error;
            NSDictionary *msg = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding]
                                                                options:0
                                                                  error:&error];
            if (error || ![msg isKindOfClass:[NSDictionary class]]) {
                TVLog(@"JSON 解析失败: %@", line);
                continue;
            }
            
            NSString *type = msg[@"type"];
            if ([type isEqualToString:@"touch"]) {
                [self handleTouchMessage:msg];
            } else if ([type isEqualToString:@"heartbeat"]) {
                mLastHeartbeat = [NSDate date];
            } else if ([type isEqualToString:@"pong"]) {
                mLastHeartbeat = [NSDate date];
            }
        }
    }
}

- (void)handleTouchMessage:(NSDictionary *)msg {
    NSString *action = msg[@"action"];
    CGFloat x = [msg[@"x"] floatValue];
    CGFloat y = [msg[@"y"] floatValue];
    
    // 归一化坐标 → 屏幕坐标
    CGSize screenSize = [[UIScreen mainScreen] bounds].size;
    CGPoint point = CGPointMake(x * screenSize.width, y * screenSize.height);
    
    if ([action isEqualToString:@"down"]) {
        [self.delegate streamServer:self didReceiveTouchDown:point];
    } else if ([action isEqualToString:@"up"]) {
        [self.delegate streamServer:self didReceiveTouchUp:point];
    } else if ([action isEqualToString:@"move"]) {
        [self.delegate streamServer:self didReceiveTouchMove:point];
    }
}

@end
