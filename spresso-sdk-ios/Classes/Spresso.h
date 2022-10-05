#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>


typedef NS_ENUM(NSUInteger, SpressoEnvironment) {
    SpressoEnvironmentLocal,
    SpressoEnvironmentDev,
    SpressoEnvironmentStaging,
    SpressoEnvironmentProd
};

extern NSString* const SpressoEventTypeCreateOrder;
extern NSString* const SpressoEventTypeGlimpseProduct;
extern NSString* const SpressoEventTypeViewPage;
extern NSString* const SpressoEventTypePurchaseVariant;
extern NSString* const SpressoEventTypeAddToCart;
extern NSString* const SpressoEventTypeViewProduct;

@protocol SpressoDelegate;

@interface Spresso : NSObject

@property (atomic, copy) NSString *userId;
@property (atomic, copy) NSString *sessionId;
@property (nonatomic) SpressoEnvironment env;
@property (nonatomic) BOOL sendEnabled;
@property (nonatomic) BOOL collectionEnabled;
@property (nonatomic) NSDate *lastActivityDate;

/*!
 @property
 
 @abstract
 Current user's name in Spresso Streams.
 */
@property (atomic, copy) NSString *nameTag;

/*!
 @property
 
 @abstract
 The base URL used for Spresso API requests.
 
 @discussion
 Useful if you need to proxy Spresso requests. Defaults to
 https://api.spresso.com.
 */
@property (atomic, copy) NSString *serverURL;

/*!
 @property
 
 @abstract
 Flush timer's interval.
 
 @discussion
 Setting a flush interval of 0 will turn off the flush timer.
 */
@property (atomic) NSUInteger flushInterval;

/*!
 @property
 
 @abstract
 Control whether the library should flush data to Spresso when the app
 enters the background.
 
 @discussion
 Defaults to YES. Only affects apps targeted at iOS 4.0, when background
 task support was introduced, and later.
 */
@property (atomic) BOOL flushOnBackground;

/*!
 @property
 
 @abstract
 Controls whether to show spinning network activity indicator when flushing
 data to the Spresso servers.
 
 @discussion
 Defaults to YES.
 */
@property (atomic) BOOL showNetworkActivityIndicator;


/*!
 @property
 
 @abstract
 The a SpressoDelegate object that can be used to assert fine-grain control
 over Spresso network activity.
 
 @discussion
 Using a delegate is optional. See the documentation for SpressoDelegate
 below for more information.
 */
@property (atomic, weak) id<SpressoDelegate> delegate; // allows fine grain control over uploading (optional)

/*!
 @method
 
 @abstract
 Initializes and returns a singleton instance of the API.
 
 @discussion
 If you are only going to send data to a single Spresso project from your app,
 as is the common case, then this is the easiest way to use the API. This
 method will set up a singleton instance of the <code>Spresso</code> class for
 you using the given project token. When you want to make calls to Spresso
 elsewhere in your code, you can use <code>sharedInstance</code>.
 
 <pre>
 [Spresso sharedInstance] track:@"Something Happened"]];
 </pre>
 
 If you are going to use this singleton approach,
 <code>sharedInstanceWithToken:</code> <b>must be the first call</b> to the
 <code>Spresso</code> class, since it performs important initializations to
 the API.
 
 @param environment        your project environment
 */
+ (Spresso *)sharedInstanceForEnvironment:(SpressoEnvironment)environment;

/*!
 @method
 
 @abstract
 Returns the previously instantiated singleton instance of the API.
 
 @discussion
 The API must be initialized with <code>sharedInstanceWithToken:</code> before
 calling this class method.
 */
+ (Spresso *)sharedInstance;

- (instancetype)initWithForEnvironment:(SpressoEnvironment) env andFlushInterval:(NSUInteger)flushInterval;

/*!
 @property
 
 @abstract
 Sets the distinct ID of the current user.
 
 @discussion
 As of version 2.3.1, Spresso will choose a default distinct ID based on
 whether you are using the AdSupport.framework or not.
 
 If you are not using the AdSupport Framework (iAds), then we use the
 <code>[UIDevice currentDevice].identifierForVendor</code> (IFV) string as the
 default distinct ID.  This ID will identify a user across all apps by the same
 vendor, but cannot be used to link the same user across apps from different
 vendors.
 
 If you are showing iAds in your application, you are allowed use the iOS ID
 for Advertising (IFA) to identify users. If you have this framework in your
 app, Spresso will use the IFA as the default distinct ID. If you have
 AdSupport installed but still don't want to use the IFA, you can define the
 <code>MIXPANEL_NO_IFA</code> preprocessor flag in your build settings, and
 Spresso will use the IFV as the default distinct ID.
 
 If we are unable to get an IFA or IFV, we will fall back to generating a
 random persistent UUID.
 
 For tracking events, you do not need to call <code>identify:</code> if you
 want to use the default.  However, <b>Spresso People always requires an
 explicit call to <code>identify:</code></b>. If calls are made to
 <code>set:</code>, <code>increment</code> or other <code></code>
 methods prior to calling <code>identify:</code>, then they are queued up and
 flushed once <code>identify:</code> is called.
 
 If you'd like to use the default distinct ID for Spresso People as well
 (recommended), call <code>identify:</code> using the current distinct ID:
 <code>[spresso identify:spresso.distinctId]</code>.
 
 @param distinctId string that uniquely identifies the current user
 */
- (void)identify:(NSString *)distinctId;

- (void)identifySessionWithId:(NSString *)sessionId;

/*!
 @method
 
 @abstract
 Tracks an event.
 
 @param event           event name
 */
-(void) track:(NSString *)event;
-(void) trackSessionStart:(NSString*) postalCode additionalProperties:(NSDictionary*) additionalProperties;
-(void) trackSessionEnd;
-(void) setupMembershipStatus:(NSNumber *) membershipStatus andShouldAutoRenew:(BOOL) shouldAutoRenew;

/*!
 @method
 
 @abstract
 Tracks an event with properties.
 
 @discussion
 Properties will allow you to segment your events in your Spresso reports.
 Property keys must be <code>NSString</code> objects and values must be
 <code>NSString</code>, <code>NSNumber</code>, <code>NSNull</code>,
 <code>NSArray</code>, <code>NSDictionary</code>, <code>NSDate</code> or
 <code>NSURL</code> objects.
 
 @param event           event name
 @param properties      properties dictionary
 */
- (void)track:(NSString *)event properties:(NSDictionary *)properties;

/*!
 @method
 
 @abstract
 Clears all stored properties and distinct IDs. Useful if your app's user logs out.
 */
- (void)reset;
-(void)softReset;

/*!
 @method
 
 @abstract
 Uploads queued data to the Spresso server.
 
 @discussion
 By default, queued data is flushed to the Spresso servers every minute (the
 default for <code>flushInvterval</code>), and on background (since
 <code>flushOnBackground</code> is on by default). You only need to call this
 method manually if you want to force a flush at a particular moment.
 */
- (void)flush;

/*!
 @method
 
 @abstract
 Writes current project info, including distinct ID, super properties and pending event
 and People record queues to disk.
 
 @discussion
 This state will be recovered when the app is launched again if the Spresso
 library is initialized with the same project token. <b>You do not need to call
 this method</b>. The library listens for app state changes and handles
 persisting data as needed. It can be useful in some special circumstances,
 though, for example, if you'd like to track app crashes from main.m.
 */
- (void)archive;


- (void)createAlias:(NSString *)alias forDistinctID:(NSString *)distinctID;
- (void) createNewSessionId;

@end

/*!
 @protocol
 
 @abstract
 Delegate protocol for controlling the Spresso API's network behavior.
 
 @discussion
 Creating a delegate for the Spresso object is entirely optional. It is only
 necessary when you want full control over when data is uploaded to the server,
 beyond simply calling stop: and start: before and after a particular block of
 your code.
 */
@protocol SpressoDelegate <NSObject>
@optional

/*!
 @method
 
 @abstract
 Asks the delegate if data should be uploaded to the server.
 
 @discussion
 Return YES to upload now, NO to defer until later.
 
 @param spresso        Spresso API instance
 */
- (BOOL)spressoWillFlush:(Spresso *)spresso;

@end
