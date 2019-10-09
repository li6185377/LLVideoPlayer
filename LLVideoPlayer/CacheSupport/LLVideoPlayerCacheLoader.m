//
//  LLVideoPlayerCacheLoader.m
//  Pods
//
//  Created by mario on 2017/2/23.
//
//

#import "LLVideoPlayerCacheLoader.h"
#import "LLVideoPlayerLoadingRequest.h"
#import "LLVideoPlayerCacheFile.h"
#import "LLVideoPlayerCacheManager.h"
#import "NSURLResponse+LLVideoPlayer.h"

NSString * const kLLVideoPlayerCacheLoaderBusy = @"LLVideoPlayerCacheLoaderBusy";
NSString * const kLLVideoPlayerCacheLoaderIdle = @"LLVideoPlayerCacheLoaderIdle";

NSInteger const kLLVideoPlayerSegmentLength = 1024 * 1024 * 2; // 2M
NSInteger const kLLVideoPlayerQuickStartLength = 1024 * 200;  // 200kb

// default 1M，
// video type : 2 bytes
// video info : 65536 bytes
// video content : 瞎猜了，10s 的数据
NSInteger const kLLVideoPlayerDefaultPreloadLength = 1024 * 1024 * 5; // 5M

@interface LLVideoPlayerCacheLoader () <LLVideoPlayerLoadingRequestDelegate>

@property (nonatomic, strong) NSURL *streamURL;
@property (nonatomic, strong) LLVideoPlayerCacheFile *cacheFile;
@property (nonatomic, strong) NSMutableArray<LLVideoPlayerLoadingRequest *> *operationQueue;
@property (nonatomic, assign) long long totalLength;
@property (nonatomic, assign) long long loadedLength;
@property (nonatomic, assign) BOOL hasUnresumeOperation;
@property (nonatomic, assign) BOOL hasBigLoadingFinished;
@property (nonatomic, copy) void(^hasBigLoadingCancelBlock)(void);

@end

@implementation LLVideoPlayerCacheLoader

#pragma mark - Initialize

- (void)dealloc
{
    for (LLVideoPlayerLoadingRequest *operation in _operationQueue) {
        [operation cancel];
    }
    [[LLVideoPlayerCacheManager defaultManager] releaseCacheFileForURL:_streamURL];
    [[NSNotificationCenter defaultCenter] postNotificationName:kLLVideoPlayerCacheLoaderIdle object:nil];
}

- (instancetype)initWithURL:(NSURL *)streamURL
{
    self = [super init];
    if (self) {
        _streamURL = streamURL;
        _operationQueue = [[NSMutableArray alloc] initWithCapacity:4];
        _cacheFile = [[LLVideoPlayerCacheManager defaultManager] createCacheFileForURL:streamURL];
    }
    return self;
}

#pragma mark - LLVideoPlayerLoadingRequestDelegate

- (void)request:(LLVideoPlayerLoadingRequest *)operation didComepleteWithError:(NSError *)error
{
    if (nil == error) {
        
        const NSInteger needLoadedLength = operation.requestedLength;
        const NSInteger realLoadedLength = operation.realLoadingLength;
        
        /*
         NOTE: The loading ranges may be overlapped,
               so `loadedLength` may be greater than `totalLength`.
         */
        self.loadedLength += realLoadedLength;
        // 标记大数据下载完毕，会等 loadedTimeRanges 更新完毕后，再继续下载
        if (realLoadedLength > kLLVideoPlayerQuickStartLength) {
            self.hasBigLoadingFinished = YES;
            [self shouldResetBigLoadingFinished];
        }
        
        if (self.totalLength == 0) {
            self.totalLength = [operation.loadingRequest.response ll_totalLength];
        }
        
        [operation.loadingRequest finishLoading];
    } else {
        [operation.loadingRequest finishLoadingWithError:error];
    }
    
    [self.operationQueue removeObject:operation];
    [self checkWillLoadingRequest];
}

- (void)setCurrentTime:(NSTimeInterval)currentTime {
    _currentTime = currentTime;
    [self checkWillLoadingRequest];
}

- (void)setSeeking:(BOOL)seeking {
    _seeking = seeking;
    if (seeking) {
        // 当切换进度时，移除未开始下载的任务，修复播放卡住的问题
        for (NSInteger i = 0; i < self.operationQueue.count; i++) {
            LLVideoPlayerLoadingRequest *operation = self.operationQueue[i];
            if (!operation.isResumed) {
                NSError *error = [NSError errorWithDomain:@"user cancel!" code:-999 userInfo:nil];
                [operation.loadingRequest finishLoadingWithError:error];
                [self.operationQueue removeObjectAtIndex:i];
                i--;
            }
        }
    }
}

- (void)setLoadedTimeRanges:(NSArray<NSValue *> *)loadedTimeRanges {
    _loadedTimeRanges = loadedTimeRanges;
    [self shouldResetBigLoadingFinished];
}

- (void)shouldResetBigLoadingFinished {
    // 标记数据回调已更新
    if (!self.hasBigLoadingFinished) {
        return;
    }
    if (self.hasBigLoadingCancelBlock) {
        self.hasBigLoadingCancelBlock();
    }
    __block BOOL isCancelled = NO;
    __weak id wself = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (isCancelled) {
            return;
        }
        __strong LLVideoPlayerCacheLoader *self = wself;
        // 无大数据loading
        self.hasBigLoadingFinished = NO;
        [self checkWillLoadingRequest];
        
        // 判断当前 是否属于空闲阶段
        if (self.totalLength > 0 && !self.seeking && ![self hasBigLoadingRequest]) {
            [[NSNotificationCenter defaultCenter] postNotificationName:kLLVideoPlayerCacheLoaderIdle object:nil];
        }
    });
    self.hasBigLoadingCancelBlock = ^{
        isCancelled = YES;
    };
}

- (void)checkWillLoadingRequest {
    if (self.hasUnresumeOperation && ![self hasBigLoadingRequest] && [self shouldLoadingRequest]) {
        BOOL hasUnresume = NO;
        BOOL beginResume = NO;
        for (LLVideoPlayerLoadingRequest *operation in self.operationQueue) {
            // 一次只循环开始下一项
            if (!operation.isResumed) {
                if (!beginResume) {
                    [operation resume];
                    beginResume = YES;
                } else {
                    hasUnresume = YES;
                }
            }
        }
        self.hasUnresumeOperation = hasUnresume;
    }
}

- (BOOL)shouldLoadingRequest
{
    if (self.preloadLimitTime > 0) {
        if (self.hasBigLoadingFinished) {
            // loadedTime 未更新
            return NO;
        }
        if (self.seeking) {
            // 拖动中，并且 loadedTime 已更新
            return YES;
        }
        CMTime currentTime = CMTimeMakeWithSeconds(self.currentTime, 1);
        for (NSValue *range in self.loadedTimeRanges) {
            CMTimeRange timeRange = [range CMTimeRangeValue];
            if (CMTimeRangeContainsTime(timeRange, currentTime)) {
                CMTime end = CMTimeRangeGetEnd(timeRange);
                if (CMTimeGetSeconds(end) - CMTimeGetSeconds(currentTime) > self.preloadLimitTime) {
                    // 缓存时间大于指定时间，不需要进行资源请求
                    return NO;
                }
                break;
            }
        }
        return YES;
    } else {
        return YES;
    }
}

- (BOOL)hasBigLoadingRequest {
    for (LLVideoPlayerLoadingRequest *operation in self.operationQueue) {
        if (operation.isResumed && operation.requestedLength > kLLVideoPlayerQuickStartLength) {
            return YES;
        }
    }
    return NO;
}

#pragma mark - Private

- (void)startLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest
{
    LLVideoPlayerLoadingRequest *operation = [[LLVideoPlayerLoadingRequest alloc] initWithLoadingRequest:loadingRequest cacheFile:self.cacheFile];
    operation.delegate = self;
    [self.operationQueue addObject:operation];
    
    // enable buffer time limit
    if (self.preloadLimitTime > 0) {
        // 限制每次加载的大小
        operation.limitLoadingLength = kLLVideoPlayerSegmentLength;
        
        // 小于 200kb 的直接请求
        BOOL shouldLoading = (operation.requestedLength < kLLVideoPlayerQuickStartLength);;
        const BOOL hasBigLoading = [self hasBigLoadingRequest];
        
        // 大于 200kb，并且处于拖动中
        if (!shouldLoading && self.seeking) {
            // 没有大的请求在加载
            if (!hasBigLoading && !self.hasBigLoadingFinished) {
                shouldLoading = YES;
            }
        }
        // 正常播放的加载判断
        if (!shouldLoading) {
            BOOL forceWait = NO;
            // 加载超过 2M 后，都由播放进度来决定什么时候加载
            if (self.loadedLength > kLLVideoPlayerSegmentLength) {
                forceWait = YES;
            }
            // 前头还有大请求
            if (hasBigLoading) {
                forceWait = YES;
            }
            if (!forceWait) {
                shouldLoading = [self shouldLoadingRequest];
            }
        }
        if (shouldLoading) {
            // 开始当前资源下载
            [operation resume];
            [[NSNotificationCenter defaultCenter] postNotificationName:kLLVideoPlayerCacheLoaderBusy object:nil];
        } else {
            // 标记有未开始的资源请求，减少实时判断 time range 操作
            self.hasUnresumeOperation = YES;
        }
    } else {
        // 开始当前资源下载
        [operation resume];
        [[NSNotificationCenter defaultCenter] postNotificationName:kLLVideoPlayerCacheLoaderBusy object:nil];
    }
}

- (void)cancelLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest
{
    for (NSInteger i = 0; i < self.operationQueue.count; i++) {
        LLVideoPlayerLoadingRequest *operation = self.operationQueue[i];
        if (operation.loadingRequest == loadingRequest) {
            [operation cancel];
            [self.operationQueue removeObjectAtIndex:i];
            i--;
        }
    }
    [self checkWillLoadingRequest];
}

#pragma mark - AVAssetResourceLoaderDelegate

- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForLoadingOfRequestedResource:(AVAssetResourceLoadingRequest *)loadingRequest
{
    [self startLoadingRequest:loadingRequest];
    return YES;
}

- (void)resourceLoader:(AVAssetResourceLoader *)resourceLoader didCancelLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest
{
    [self cancelLoadingRequest:loadingRequest];
}

@end
