//
//  CDVCommandDelegateImpl.h
//  CRTFileTransfer
//
//  Created by fangyunjiang on 15/11/17.
//  Copyright (c) 2015年 remobile. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RCTBridgeModule.h"
#import "CDVPluginResult.h"

@interface CDVCommandDelegateImpl : NSObject

- (void)setCallback:(RCTResponseSenderBlock)successFunc error:(RCTResponseSenderBlock)errorFunc;
- (void)sendPluginResult:(CDVPluginResult*)result;
- (void)runInBackground:(void (^)())block;

@end
