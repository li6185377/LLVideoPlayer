//
//  LLVideoPlayerCacheLoader.h
//  Pods
//
//  Created by mario on 2017/2/23.
//
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface LLVideoPlayerCacheLoader : NSObject <AVAssetResourceLoaderDelegate>

- (instancetype)initWithURL:(NSURL *)streamURL;

// preload buffer time
@property (nonatomic, assign) NSTimeInterval preloadLimitTime;
// is seeking
@property (nonatomic, assign) BOOL seeking;
// current palying time
@property (nonatomic, assign) NSTimeInterval currentTime;
// an NSArray of NSValues containing CMTimeRanges
@property (nonatomic, copy) NSArray<NSValue *> *loadedTimeRanges;

@end
