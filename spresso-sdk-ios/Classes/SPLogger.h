#import <Foundation/Foundation.h>
#import <os/log.h>


@interface SPLogger : NSObject

@property (nonatomic, assign) BOOL loggingEnabled;

+ (SPLogger *)sharedInstance;

@end

static inline os_log_t spressoLog() {
    static os_log_t logger = nil;
    if (!logger) {
        logger = os_log_create("com.spresso.sdk.objc", "Spresso");
    }
    return logger;
}

static inline __attribute__((always_inline)) void SPLogDebug(NSString *format, ...) {
    if (![SPLogger sharedInstance].loggingEnabled) return;
    va_list arg_list;
    va_start(arg_list, format);
    NSString *formattedString = [[NSString alloc] initWithFormat:format arguments:arg_list];
    os_log_with_type(spressoLog(), OS_LOG_TYPE_DEBUG, "<Debug>: %s", [formattedString UTF8String]);
}

static inline __attribute__((always_inline)) void SPLogInfo(NSString *format, ...) {
    if (![SPLogger sharedInstance].loggingEnabled) return;
    va_list arg_list;
    va_start(arg_list, format);
    NSString *formattedString = [[NSString alloc] initWithFormat:format arguments:arg_list];
    os_log_with_type(spressoLog(), OS_LOG_TYPE_INFO, "<Info>: %s", [formattedString UTF8String]);
}

static inline __attribute__((always_inline)) void SPLogWarning(NSString *format, ...) {
    if (![SPLogger sharedInstance].loggingEnabled) return;
    va_list arg_list;
    va_start(arg_list, format);
    NSString *formattedString = [[NSString alloc] initWithFormat:format arguments:arg_list];
    os_log_with_type(spressoLog(), OS_LOG_TYPE_ERROR, "<Warning>: %s", [formattedString UTF8String]);
}

static inline __attribute__((always_inline)) void SPLogError(NSString *format, ...) {
    if (![SPLogger sharedInstance].loggingEnabled) return;
    va_list arg_list;
    va_start(arg_list, format);
    NSString *formattedString = [[NSString alloc] initWithFormat:format arguments:arg_list];
    os_log_with_type(spressoLog(), OS_LOG_TYPE_ERROR, "<Error>: %s", [formattedString UTF8String]);
}
