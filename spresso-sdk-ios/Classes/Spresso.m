#if ! __has_feature(objc_arc)
#error This file must be compiled with ARC. Either turn on ARC for the project or use -fobjc-arc flag on this file.
#endif

#include <arpa/inet.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <sys/socket.h>
#include <sys/sysctl.h>

#import <CommonCrypto/CommonDigest.h>
#import <CoreTelephony/CTCarrier.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <UIKit/UIDevice.h>
#import "Spresso.h"
#import "SPLogger.h"
#import "SPKeychainItemWrapper.h"

#define VERSION @"1.3.0"
#define SPRESSO_FLUSH_INTERVAL 30



#ifdef SPRESSO_LOG
#define SpressoLog(...) SpressoLog(__VA_ARGS__)
#else
#define SpressoLog(...)
#endif

#ifdef SPRESSO_DEBUG
#define SpressoDebug(...) SpressoLog(__VA_ARGS__)
#else
#define SpressoDebug(...)
#endif

NSString* const SpressoEventTypeCreateOrder = @"spresso_create_order";
NSString* const SpressoEventTypeGlimpsePLE = @"spresso_glimpse_ple";
NSString* const SpressoEventTypeGlimpseProductPLE = @"spresso_glimpse_product_ple";
NSString* const SpressoEventTypeViewPage = @"spresso_screen_view";
NSString* const SpressoEventTypePurchaseVariant = @"spresso_purchase_variant";
NSString* const SpressoEventTypeAddToCart = @"spresso_tap_add_to_cart";
NSString* const SpressoEventTypeViewProduct = @"spresso_view_pdp";

@interface Spresso () <UIAlertViewDelegate> {
    NSUInteger _flushInterval;
}

// re-declare internally as readwrite

@property (nonatomic, copy) NSString *apiToken;
@property (nonatomic, strong) NSMutableDictionary *automaticProperties; // mutable because we update $wifi when reachability changes
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) NSMutableArray *eventsQueue;
@property (nonatomic, assign) UIBackgroundTaskIdentifier taskId;
#if OS_OBJECT_USE_OBJC
@property (nonatomic, strong) dispatch_queue_t serialQueue; // this is for Xcode 4.5 with LLVM 4.1 and iOS 6 SDK
#else
@property (nonatomic, assign) dispatch_queue_t serialQueue; // this is for older Xcodes with older SDKs
#endif
@property (nonatomic, assign) SCNetworkReachabilityRef reachability;
@property (nonatomic, strong) CTTelephonyNetworkInfo *telephonyInfo;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;

@end

@implementation Spresso

static void SpressoReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void *info)
{
    if (info != NULL && [(__bridge NSObject*)info isKindOfClass:[Spresso class]]) {
        @autoreleasepool {
            Spresso *spresso = (__bridge Spresso *)info;
            [spresso reachabilityChanged:flags];
        }
    } else {
        SpressoLog(@"Spresso reachability callback received unexpected info object");
    }
}

static Spresso *sharedInstance = nil;

+ (Spresso *)sharedInstanceForEnvironment:(SpressoEnvironment)environment
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[super alloc] initForEnvironment:environment andFlushInterval:SPRESSO_FLUSH_INTERVAL];
    });
    return sharedInstance;
}

+ (Spresso *)sharedInstance
{
    if (sharedInstance == nil) {
        SpressoLog(@"%@ warning sharedInstance called before sharedInstanceWithToken:", self);
    }
    return sharedInstance;
}

- (instancetype)initForEnvironment:(SpressoEnvironment)environment andFlushInterval:(NSUInteger)flushInterval
{

    if (self = [self init]) {

        self.flushInterval = flushInterval;
        self.flushOnBackground = YES;
        self.showNetworkActivityIndicator = YES;
        
        self.collectionEnabled = YES;
        self.sendEnabled = YES;

        // partner-specific
        self.env = environment;
        switch (environment) {
            case SpressoEnvironmentLocal: {
                self.apiToken = @"local_api_token";
                self.serverURL = @"http://192.168.1.135:8080";
                break;
            }
            case SpressoEnvironmentProd: {
                self.apiToken = @"prod";
                self.serverURL = @"https://api.spresso.com/pim/public/events";
                break;
            }
            case SpressoEnvironmentStaging: {
                self.apiToken = @"staging_token";
                self.serverURL = @"https://api.staging.spresso.com/pim/public/events";
                break;
            }
            case SpressoEnvironmentDev: {
                self.apiToken = @"devtoken";
                self.serverURL = @"https://api.staging.spresso.com/pim/public/events";
                break;
            }
            default:
                self.apiToken = @"local_api_token";
                self.serverURL = @"http://localhost:8080";
                break;
        }

        self.deviceId = [self defaultDeviceId];
        self.automaticProperties = [self collectAutomaticProperties];
        self.eventsQueue = [NSMutableArray array];
        self.taskId = UIBackgroundTaskInvalid;
        NSString *label = [NSString stringWithFormat:@"com.spresso.%@.%p", self.apiToken, self];
        self.serialQueue = dispatch_queue_create([label UTF8String], DISPATCH_QUEUE_SERIAL);
        self.dateFormatter = [[NSDateFormatter alloc] init];
        [_dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"];
        [_dateFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
        

        
        // wifi reachability
        BOOL reachabilityOk = NO;
        if ((self.reachability = SCNetworkReachabilityCreateWithName(NULL, "api.spresso.com")) != NULL) {
            SCNetworkReachabilityContext context = {0, (__bridge void*)self, NULL, NULL, NULL};
            if (SCNetworkReachabilitySetCallback(self.reachability, SpressoReachabilityCallback, &context)) {
                if (SCNetworkReachabilitySetDispatchQueue(self.reachability, self.serialQueue)) {
                    reachabilityOk = YES;
                    SpressoDebug(@"%@ successfully set up reachability callback", self);
                } else {
                    // cleanup callback if setting dispatch queue failed
                    SCNetworkReachabilitySetCallback(self.reachability, NULL, NULL);
                }
            }
        }
        if (!reachabilityOk) {
            SpressoLog(@"%@ failed to set up reachability callback: %s", self, SCErrorString(SCError()));
        }
        
        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        
        // cellular info
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 70000
        if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_6_1) {
            self.telephonyInfo = [[CTTelephonyNetworkInfo alloc] init];
//            _automaticProperties[@"$radio"] = [self currentRadio];
            [notificationCenter addObserver:self
                                   selector:@selector(setCurrentRadio)
                                       name:CTRadioAccessTechnologyDidChangeNotification
                                     object:nil];
        }
#endif
        
        [notificationCenter addObserver:self
                               selector:@selector(applicationWillTerminate:)
                                   name:UIApplicationWillTerminateNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(applicationWillResignActive:)
                                   name:UIApplicationWillResignActiveNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(applicationDidBecomeActive:)
                                   name:UIApplicationDidBecomeActiveNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(applicationDidEnterBackground:)
                                   name:UIApplicationDidEnterBackgroundNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(applicationWillEnterForeground:)
                                   name:UIApplicationWillEnterForegroundNotification
                                 object:nil];
        [self unarchive];
        

    }
    
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (self.reachability) {
        SCNetworkReachabilitySetCallback(self.reachability, NULL, NULL);
        SCNetworkReachabilitySetDispatchQueue(self.reachability, NULL);
        self.reachability = nil;
    }
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<Spresso: %p %@>", self, self.apiToken];
}

- (NSString *)deviceModel
{
    size_t size;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    char answer[size];
    sysctlbyname("hw.machine", answer, &size, NULL, 0);
    NSString *results = @(answer);
    return results;
}

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 70000
- (void)setCurrentRadio
{
    dispatch_async(self.serialQueue, ^(){
        self.automaticProperties[@"$radio"] = [self currentRadio];
    });
}

- (NSString *)currentRadio
{
    NSString *radio = _telephonyInfo.currentRadioAccessTechnology;
    if (!radio) {
        radio = @"None";
    } else if ([radio hasPrefix:@"CTRadioAccessTechnology"]) {
        radio = [radio substringFromIndex:23];
    }
    return radio;
}
#endif

- (NSMutableDictionary *)collectAutomaticProperties
{
    NSMutableDictionary *p = [NSMutableDictionary dictionary];
    UIDevice *device = [UIDevice currentDevice];
    NSString *deviceModel = [self deviceModel];
//    [p setValue:@"iphone" forKey:@"mp_lib"];
    [p setValue:VERSION forKey:@"version"];
    [p setValue:@"iOS" forKey:@"platform"];
    [p setValue:VERSION forKey:@"libVersion"];
    [p setValue:[[NSBundle mainBundle] infoDictionary][@"CFBundleVersion"] forKey:@"appVersion"];
    [p setValue:[[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"] forKey:@"appRelease"];
    [p setValue:@"Apple" forKey:@"manufacturer"];
    [p setValue:[device systemName] forKey:@"os"];
    [p setValue:[device systemVersion] forKey:@"osVersion"];
    [p setValue:deviceModel forKey:@"model"];
    CGSize size = [UIScreen mainScreen].bounds.size;
    [p setValue:@((NSInteger)size.height) forKey:@"screenHeight"];
    [p setValue:@((NSInteger)size.width) forKey:@"screenWidth"];
    CTTelephonyNetworkInfo *networkInfo = [[CTTelephonyNetworkInfo alloc] init];
    CTCarrier *carrier = [networkInfo subscriberCellularProvider];
    if (carrier.carrierName.length) {
        [p setValue:carrier.carrierName forKey:@"carrier"];
    }
    [p setValue:self.deviceId forKey:@"deviceId"];
 
    return p;
}

+ (BOOL)inBackground
{
    if (NSClassFromString(@"XCTest")){
        return NO;
    }
    
    return [UIApplication sharedApplication].applicationState == UIApplicationStateBackground;
}

#pragma mark - Encoding/decoding utilities

- (NSData *)JSONSerializeObject:(id)obj
{
    id coercedObj = [self JSONSerializableObjectForObject:obj];
    NSError *error = nil;
    NSData *data = nil;
    @try {
        data = [NSJSONSerialization dataWithJSONObject:coercedObj options:0 error:&error];
    }
    @catch (NSException *exception) {
        SpressoLog(@"%@ exception encoding api data: %@", self, exception);
    }
    if (error) {
        SpressoLog(@"%@ error encoding api data: %@", self, error);
    }
    return data;
}

- (id)JSONSerializableObjectForObject:(id)obj
{
    // valid json types
    if ([obj isKindOfClass:[NSString class]] ||
        [obj isKindOfClass:[NSNumber class]] ||
        [obj isKindOfClass:[NSNull class]]) {
        return obj;
    }
    // recurse on containers
    if ([obj isKindOfClass:[NSArray class]]) {
        NSMutableArray *a = [NSMutableArray array];
        for (id i in obj) {
            [a addObject:[self JSONSerializableObjectForObject:i]];
        }
        return [NSArray arrayWithArray:a];
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        for (id key in obj) {
            NSString *stringKey;
            if (![key isKindOfClass:[NSString class]]) {
                stringKey = [key description];
                SpressoLog(@"%@ warning: property keys should be strings. got: %@. coercing to: %@", self, [key class], stringKey);
            } else {
                stringKey = [NSString stringWithString:key];
            }
            id v = [self JSONSerializableObjectForObject:obj[key]];
            d[stringKey] = v;
        }
        return [NSDictionary dictionaryWithDictionary:d];
    }
    // some common cases
    if ([obj isKindOfClass:[NSDate class]]) {
        return [self.dateFormatter stringFromDate:obj];
    } else if ([obj isKindOfClass:[NSURL class]]) {
        return [obj absoluteString];
    }
    // default to sending the object's description
    NSString *s = [obj description];
    SpressoLog(@"%@ warning: property values should be valid json types. got: %@. coercing to: %@", self, [obj class], s);
    return s;
}

- (NSString *)encodeAPIData:(NSArray *)array
{
    NSString *b64String = @"";
    NSData *data = [self JSONSerializeObject: @{ @"datas": array } ];
    if (data) {
        b64String = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    return b64String;
}

#pragma mark - Tracking

+ (void)assertPropertyTypes:(NSDictionary *)properties
{
    for (id k in properties) {
        NSAssert([k isKindOfClass: [NSString class]], @"%@ property keys must be NSString. got: %@ %@", self, [k class], k);
        // would be convenient to do: id v = [properties objectForKey:k]; but
        // when the NSAssert's are stripped out in release, it becomes an
        // unused variable error. also, note that @YES and @NO pass as
        // instances of NSNumber class.
        NSAssert([properties[k] isKindOfClass:[NSString class]] ||
                 [properties[k] isKindOfClass:[NSNumber class]] ||
                 [properties[k] isKindOfClass:[NSNull class]] ||
                 [properties[k] isKindOfClass:[NSArray class]] ||
                 [properties[k] isKindOfClass:[NSDictionary class]] ||
                 [properties[k] isKindOfClass:[NSDate class]] ||
                 [properties[k] isKindOfClass:[NSURL class]],
                 @"%@ property values must be NSString, NSNumber, NSNull, NSArray, NSDictionary, NSDate or NSURL. got: %@ %@", self, [properties[k] class], properties[k]);
    }
}

- (NSString *)defaultDistinctId
{
    return [self defaultDeviceId];
}

- (NSString *)defaultDeviceId
{
    NSString *deviceId = [self getDeviceIdFromKeychain];
    if (deviceId && deviceId.length > 0) {
        return deviceId;
    }

    if (!deviceId || deviceId.length == 0) {
        deviceId = [self createOwnDeviceId];
    }

    if (deviceId) {
        [self storeDeviceIdInKeychain:deviceId];
    }

    return deviceId;
}

- (NSString *) createOwnDeviceId
{
    NSMutableString *randomString = [[NSMutableString alloc] init];
    NSString *chars = [NSString stringWithFormat:@"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"];
    for (int i = 0; i < 32; i++) {
        [randomString appendFormat: @"%C", [chars characterAtIndex: arc4random_uniform((unsigned int)[chars length])]];
    }
    
    [randomString insertString:@"-" atIndex:20];
    [randomString insertString:@"-" atIndex:16];
    [randomString insertString:@"-" atIndex:12];
    [randomString insertString:@"-" atIndex:8];
    
    return randomString;
}

- (void)identify:(NSString *)userId
{
    if (userId == nil || userId.length == 0) {
        SpressoLog(@"%@ error blank userId id: %@", self, userId);
        return;
    }
    
    BOOL inBackground = [Spresso inBackground];
    
    dispatch_async(self.serialQueue, ^{
        self.userId = userId;
        if (inBackground) {
            [self archiveProperties];
        }
    });
}

- (void)identifyRefUserId:(NSString *)refUserId {
    if (refUserId == nil || refUserId.length == 0) {
        return;
    }
    
    BOOL inBackground = [Spresso inBackground];
    
    dispatch_async(self.serialQueue, ^{
        self.refUserId = refUserId;
        if (inBackground) {
            [self archiveProperties];
        }
    });
}

-(void) storeDeviceIdInKeychain: (NSString*) deviceId {
    
    SPKeychainItemWrapper* wrapper = [[SPKeychainItemWrapper alloc] initWithIdentifier:@"SpressoDeviceID" accessGroup:nil];
    NSLog(@"trying to store device id into keychain = %@", deviceId);
    if (!deviceId) {
        [wrapper resetKeychainItem];
        return;
    }
    
    [wrapper setObject:@"spresso" forKey:(__bridge id)(kSecAttrAccount)];
    [wrapper setObject:deviceId forKey:(__bridge id)(kSecValueData)];
}

-(NSString*) getDeviceIdFromKeychain {
    
    SPKeychainItemWrapper* wrapper = [[SPKeychainItemWrapper alloc] initWithIdentifier:@"SpressoDeviceID" accessGroup:nil];
    NSString* deviceId = [wrapper objectForKey:(__bridge id)(kSecValueData)];
    
    return deviceId;
}

- (void)track:(NSString *)event
{
    [self track:event properties:nil];
}

- (void)track:(NSString *)event properties:(NSDictionary *)properties
{
    if (event == nil || [event length] == 0) {
        SpressoLog(@"%@ spresso track called with empty event parameter. using 'mp_event'", self);
        event = @"mp_event";
    }
    
    if (!self.collectionEnabled ) {
                SpressoDebug(@"Spresso tracking is disabled");
        return;
    }
    properties = [properties copy];
    [Spresso assertPropertyTypes:properties];
    NSNumber *epochMilliseconds = @(round([[NSDate date] timeIntervalSince1970] * 1000));
    BOOL inBackground = [Spresso inBackground];
    
    dispatch_async(self.serialQueue, ^{
        NSMutableDictionary *p = [NSMutableDictionary dictionary];
        [p addEntriesFromDictionary:self.automaticProperties];

        if (self.userId) {
            p[@"userId"] = self.userId;
            p[@"isLoggedIn"] = @(YES);
        } else {
            p[@"isLoggedIn"] = @(NO);
        }
        if (self.refUserId) {
            p[@"refUserId"] = self.refUserId;
        }
        
        if (properties) {
            [p addEntriesFromDictionary:properties];
        }
        NSMutableDictionary *e = [NSMutableDictionary dictionaryWithDictionary:@{@"event": event, @"properties": [NSDictionary dictionaryWithDictionary:p], @"utcTimestampMs" : epochMilliseconds}];
//        p[@"event"] = event;
//        p[@"v"] = VERSION;
//        p[@"utcTimestampMs"] = epochMilliseconds;
        
        if (self.deviceId) {
            [e setValue:self.deviceId forKey:@"deviceId"];
        }

        [e setValue:[[NSUUID UUID] UUIDString] forKey:@"uid"];
        [e setValue:@([[NSTimeZone systemTimeZone] secondsFromGMT] * 1000) forKey:@"timezoneOffset"];
  
        SpressoLog(@"%@ queueing event: %@", self, e);
        
        [self.eventsQueue addObject:e];
        if ([self.eventsQueue count] > 500) {
            [self.eventsQueue removeObjectAtIndex:0];
        }
        if (inBackground) {
            [self archiveEvents];
        }
        
        if (event != nil && ![event isEqualToString:@"glimpseAction"]) {
            self.lastActivityDate = [NSDate date];
        }
    });
}

- (void)reset
{
    dispatch_async(self.serialQueue, ^{
        self.nameTag = nil;
        self.userId = nil;
        self.refUserId = nil;
        self.eventsQueue = [NSMutableArray array];
        [self archive];
    });
}

- (void)softReset
{
    dispatch_async(self.serialQueue, ^{
        self.eventsQueue = [NSMutableArray array];
        [self archive];
    });
}

#pragma mark - Network control

- (NSUInteger)flushInterval
{
    @synchronized(self) {
        return _flushInterval;
    }
}

- (void)setFlushInterval:(NSUInteger)interval
{
    @synchronized(self) {
        _flushInterval = interval;
    }
    [self startFlushTimer];
}

- (void)startFlushTimer
{
    [self stopFlushTimer];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.flushInterval > 0) {
            self.timer = [NSTimer scheduledTimerWithTimeInterval:self.flushInterval
                                                          target:self
                                                        selector:@selector(flush)
                                                        userInfo:nil
                                                         repeats:YES];
            SpressoDebug(@"%@ started flush timer: %@", self, self.timer);
        }
    });
}

- (void)stopFlushTimer
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.timer) {
            [self.timer invalidate];
            SpressoDebug(@"%@ stopped flush timer: %@", self, self.timer);
        }
        self.timer = nil;
    });
}

- (void)flush
{
    //dont flush if send isn't enabled
    if (!self.sendEnabled) {
        SpressoDebug(@"Sending is disabled");
        return;
    }
    dispatch_async(self.serialQueue, ^{
        SpressoDebug(@"%@ flush starting", self);
        
        __strong id<SpressoDelegate> strongDelegate = self.delegate;
        if (strongDelegate != nil && [strongDelegate respondsToSelector:@selector(spressoWillFlush:)] && ![strongDelegate spressoWillFlush:self]) {
            SpressoDebug(@"%@ flush deferred by delegate", self);
            return;
        }
        
        [self flushEvents];

        
        SpressoDebug(@"%@ flush complete", self);
    });
}

- (void)flushEvents
{
    if (!self.sendEnabled) return;
    [self flushQueue:_eventsQueue
            endpoint:@""];
}


- (void)flushQueue:(NSMutableArray *)queue endpoint:(NSString *)endpoint
{
    while ([queue count] > 0) {
        NSUInteger batchSize = ([queue count] > 50) ? 50 : [queue count];
        NSArray *batch = [queue subarrayWithRange:NSMakeRange(0, batchSize)];
        
        NSString *requestData = [self encodeAPIData:batch];
        NSString *postBody = [NSString stringWithFormat:@"%@", requestData];

        SpressoDebug(@"%@ flushing %lu of %lu to %@: %@", self, (unsigned long)[batch count], (unsigned long)[queue count], endpoint, queue);
        
        SpressoDebug(@"post body: %@", requestData);
        NSURLRequest *request = [self apiRequestWithEndpoint:endpoint andBody:postBody];
        NSError *error = nil;
        
        [self updateNetworkActivityIndicator:YES];
        
        SpressoDebug(@"request: %@", request.debugDescription);
        
        NSData *responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:nil error:&error];
        
        [self updateNetworkActivityIndicator:NO];
        
        if (error) {
            SpressoDebug(@"%@ network failure: %@", self, error);
            break;
        }
        
        NSString *response = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
        SpressoDebug(@"response: %@", response);
//        if ([response intValue] == 0) {
//            SpressoDebug(@"%@ %@ api rejected some items", self, endpoint);
//        };
        
        [queue removeObjectsInArray:batch];
    }
}

- (void)updateNetworkActivityIndicator:(BOOL)on
{
    if (NSClassFromString(@"XCTest")){
        return;
    }
    
    if (_showNetworkActivityIndicator) {
        [UIApplication sharedApplication].networkActivityIndicatorVisible = on;
    }
}

- (void)reachabilityChanged:(SCNetworkReachabilityFlags)flags
{
    dispatch_async(self.serialQueue, ^{
        BOOL wifi = (flags & kSCNetworkReachabilityFlagsReachable) && !(flags & kSCNetworkReachabilityFlagsIsWWAN);
        self.automaticProperties[@"wifi"] = wifi ? @YES : @NO;
    });
}

- (NSURLRequest *)apiRequestWithEndpoint:(NSString *)endpoint andBody:(NSString *)body
{
    
//    NSString* userAgent = [[GDServiceManager sharedManager] getDefaultUserAgent];
    
    NSURL *URL = [NSURL URLWithString:[self.serverURL stringByAppendingString:endpoint]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:URL];
    [request setValue:@"gzip" forHTTPHeaderField:@"Accept-Encoding"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    if (self.orgId && self.orgId.length > 0) {
        [request addValue:self.orgId forHTTPHeaderField:@"org-id"];
    }
//    if (userAgent)
//        [request setValue:userAgent forHTTPHeaderField:@"User-Agent"];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:[body dataUsingEncoding:NSUTF8StringEncoding]];
    SpressoDebug(@"%@ http request: %@?%@", self, URL, body);
    return request;
}

#pragma mark - Persistence

- (NSString *)filePathForData:(NSString *)data
{
    NSString *filename = [NSString stringWithFormat:@"spresso-%@-%@.plist", self.apiToken, data];
    return [[NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) lastObject]
            stringByAppendingPathComponent:filename];
}

- (NSString *)eventsFilePath
{
    return [self filePathForData:@"events"];
}

- (NSString *)peopleFilePath
{
    return [self filePathForData:@"people"];
}

- (NSString *)propertiesFilePath
{
    return [self filePathForData:@"properties"];
}

- (void)archive
{
    [self archiveEvents];
    [self archiveProperties];
}

- (void)archiveEvents
{
    NSString *filePath = [self eventsFilePath];
    NSMutableArray *eventsQueueCopy = [NSMutableArray arrayWithArray:[self.eventsQueue copy]];
    SpressoDebug(@"%@ archiving events data to %@: %@", self, filePath, eventsQueueCopy);
    if (![NSKeyedArchiver archiveRootObject:eventsQueueCopy toFile:filePath]) {
        SpressoLog(@"%@ unable to archive events data", self);
    }
}

- (void)archiveProperties
{
    NSString *filePath = [self propertiesFilePath];
    NSMutableDictionary *p = [NSMutableDictionary dictionary];
    [p setValue:self.userId forKey:@"userId"];
    [p setValue:self.nameTag forKey:@"nameTag"];
    [p setValue:self.deviceId forKey:@"deviceId"];
    [p setValue:self.refUserId forKey:@"refUserId"];


    SpressoDebug(@"%@ archiving properties data to %@: %@", self, filePath, p);
    if (![NSKeyedArchiver archiveRootObject:p toFile:filePath]) {
        SpressoLog(@"%@ unable to archive properties data", self);
    }
}

- (void)unarchive
{
    [self unarchiveEvents];
    [self unarchiveProperties];
}

- (void)unarchiveEvents
{
    NSString *filePath = [self eventsFilePath];
    @try {
        self.eventsQueue = [NSKeyedUnarchiver unarchiveObjectWithFile:filePath];
        SpressoDebug(@"%@ unarchived events data: %@", self, self.eventsQueue);
    }
    @catch (NSException *exception) {
        SpressoLog(@"%@ unable to unarchive events data, starting fresh", self);
        self.eventsQueue = nil;
    }
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        NSError *error;
        BOOL removed = [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
        if (!removed) {
            SpressoLog(@"%@ unable to remove archived events file at %@ - %@", self, filePath, error);
        }
    }
    if (!self.eventsQueue) {
        self.eventsQueue = [NSMutableArray array];
    }
}



- (void)unarchiveProperties
{
    NSString *filePath = [self propertiesFilePath];
    NSDictionary *properties = nil;
    @try {
        properties = [NSKeyedUnarchiver unarchiveObjectWithFile:filePath];
        SpressoDebug(@"%@ unarchived properties data: %@", self, properties);
    }
    @catch (NSException *exception) {
        SpressoLog(@"%@ unable to unarchive properties data, starting fresh", self);
    }
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        NSError *error;
        BOOL removed = [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
        if (!removed) {
            
            SpressoLog(@"%@ unable to remove archived properties file at %@ - %@", self, filePath, error);
        }
    }
    if (properties) {
        self.userId = properties[@"userId"];
        self.nameTag = properties[@"nameTag"];
        self.refUserId = properties[@"refUserId"];
    }
}

#pragma mark - UIApplication notifications

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    SpressoDebug(@"%@ application did become active", self);
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    SpressoDebug(@"%@ application will resign active", self);
    [self stopFlushTimer];
}

- (void)applicationDidEnterBackground:(NSNotificationCenter *)notification
{
    SpressoDebug(@"%@ did enter background", self);
    
    self.taskId = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        SpressoDebug(@"%@ flush %lu cut short", self, (unsigned long)self.taskId);
        [[UIApplication sharedApplication] endBackgroundTask:self.taskId];
        self.taskId = UIBackgroundTaskInvalid;
    }];
    SpressoDebug(@"%@ starting background cleanup task %lu", self, (unsigned long)self.taskId);
    
    if (self.flushOnBackground) {
        [self flush];
    }
    
    dispatch_async(self.serialQueue, ^{
        [self archive];
        SpressoDebug(@"%@ ending background cleanup task %lu", self, (unsigned long)self.taskId);
        if (self.taskId != UIBackgroundTaskInvalid) {
            [[UIApplication sharedApplication] endBackgroundTask:self.taskId];
            self.taskId = UIBackgroundTaskInvalid;
        }
    });
}

- (void)applicationWillEnterForeground:(NSNotificationCenter *)notification
{
    SpressoDebug(@"%@ will enter foreground", self);
    dispatch_async(self.serialQueue, ^{
        if (self.taskId != UIBackgroundTaskInvalid) {
            [[UIApplication sharedApplication] endBackgroundTask:self.taskId];
            self.taskId = UIBackgroundTaskInvalid;
            [self updateNetworkActivityIndicator:NO];
        }
    });
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    SpressoDebug(@"%@ application will terminate", self);
    dispatch_async(_serialQueue, ^{
        [self archive];
    });
}


@end
