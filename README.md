# spresso-sdk-ios

[![CI Status](https://img.shields.io/travis/Spresso/spresso-sdk-ios.svg?style=flat)](https://travis-ci.org/Spresso/spresso-sdk-ios)
[![Version](https://img.shields.io/cocoapods/v/spresso-sdk-ios.svg?style=flat)](https://cocoapods.org/pods/spresso-sdk-ios)
[![License](https://img.shields.io/cocoapods/l/spresso-sdk-ios.svg?style=flat)](https://cocoapods.org/pods/spresso-sdk-ios)
[![Platform](https://img.shields.io/cocoapods/p/spresso-sdk-ios.svg?style=flat)](https://cocoapods.org/pods/spresso-sdk-ios)


## Installation

spresso-sdk-ios is available through [CocoaPods](https://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod 'spresso-sdk-ios'
```

## Initialization

Initialize the library with your current environment and orgId.

### Swift

```ruby
Spresso.sharedInstance(for: .prod)
Spresso.sharedInstance().orgId = <org_id>
```

### Objective-C

```ruby
[Spresso sharedInstanceForEnvironment:SpressoEnvironmentProd];
[Spresso sharedInstance].orgId = @"<org_id>";
```

## Setting a User

### Swift

```ruby
Spresso.sharedInstance().identify("<user_id>")
```

### Objective-C

```ruby
[[Spresso sharedInstance] identify:@"<user_id"];
```

## Tracking Events

Example of tracking viewing a product

### Swift

```ruby
Spresso.sharedInstance().track(SpressoEventTypeViewPage, properties: ["variantSku": "<variant_sku>",
                                                                              "variantName": "<variant_name>",
                                                                              "variantPrice": "<variant_price>"])
```

### Objective-C

```ruby
[[Spresso sharedInstance] track:SpressoEventTypeViewProduct properties:@{ @"variantSku": @"<variant_sku>",
                                                                              @"variantName": @"<variant_name>",
                                                                              @"variantPrice": @"<variant_price>"
                                                                           }];
```

## Author

Spresso, developer@spresso.com

## License

spresso-sdk-ios is available under the MIT license. See the LICENSE file for more info.
