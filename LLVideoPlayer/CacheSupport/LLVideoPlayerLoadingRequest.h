//
//  LLVideoPlayerLoadingRequest.h
//  Pods
//
//  Created by mario on 2017/8/21.
//
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "LLVideoPlayerCacheFile.h"

@class LLVideoPlayerLoadingRequest;
@protocol LLVideoPlayerLoadingRequestDelegate <NSObject>

- (void)request:(LLVideoPlayerLoadingRequest *)operation didComepleteWithError:(NSError *)error;

@end

@interface LLVideoPlayerLoadingRequest : NSObject

- (instancetype)initWithLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest
                             cacheFile:(LLVideoPlayerCacheFile *)cacheFile;

@property (nonatomic, strong, readonly) AVAssetResourceLoadingRequest *loadingRequest;
@property (nonatomic, assign, readonly) NSInteger realLoadingLength;
@property (nonatomic, assign, readonly) NSInteger requestedLength;

@property (nonatomic, weak) id<LLVideoPlayerLoadingRequestDelegate> delegate;

// 限制 一起请求的 data loading 大小，目前：2M
@property (nonatomic, assign) NSInteger limitLoadingLength;
// 是否开始执行加载
- (BOOL)isResumed;

- (void)resume;
- (void)cancel;

@end
