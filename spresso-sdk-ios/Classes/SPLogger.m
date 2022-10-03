#import "SPLogger.h"


@implementation SPLogger

+ (SPLogger *)sharedInstance
{
    static SPLogger *sharedSPLogger = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedSPLogger = [[self alloc] init];
        sharedSPLogger.loggingEnabled = NO;
    });
    return sharedSPLogger;
}

@end
