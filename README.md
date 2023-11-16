# spresso-ios-sdk

[![CI Status](https://img.shields.io/travis/Spresso/spresso-ios-sdk.svg?style=flat)](https://travis-ci.org/Spresso/spresso-ios-sdk)
[![Version](https://img.shields.io/cocoapods/v/spresso-ios-sdk.svg?style=flat)](https://cocoapods.org/pods/spresso-ios-sdk)
[![License](https://img.shields.io/cocoapods/l/spresso-ios-sdk.svg?style=flat)](https://cocoapods.org/pods/spresso-ios-sdk)
[![Platform](https://img.shields.io/cocoapods/p/spresso-ios-sdk.svg?style=flat)](https://cocoapods.org/pods/spresso-ios-sdk)


## Installation

spresso-ios-sdk is available through [CocoaPods](https://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod 'spresso-ios-sdk'
```

## Initialization

Initialize the library with your current environment and Org ID.

#### Swift

```
Spresso.sharedInstance(for: .prod)
Spresso.sharedInstance().orgId = <org_id>
```

#### Objective-C

```
[Spresso sharedInstanceForEnvironment:SpressoEnvironmentProd];
[Spresso sharedInstance].orgId = @"<org_id>";
```

## Setting a User

#### Swift

```
Spresso.sharedInstance().identify("<user_id>")
```

#### Objective-C

```
[[Spresso sharedInstance] identify:@"<user_id"];
```

## Tracking Events

Example of sending data when a user views a product

#### Swift

```
Spresso.sharedInstance().track(SpressoEventTypeViewPage, properties: ["variantSku": "<variant_sku>",
                                                                              "variantName": "<variant_name>",
                                                                              "variantPrice": "<variant_price>"])
```

#### Objective-C

```
[[Spresso sharedInstance] track:SpressoEventTypeViewProduct properties:@{ @"variantSku": @"<variant_sku>",
                                                                              @"variantName": @"<variant_name>",
                                                                              @"variantPrice": @"<variant_price>"
                                                                           }];
```

## Author

Spresso, developer@spresso.com

## License

spresso-ios-sdk is available under the MIT license. See the LICENSE file for more info.
