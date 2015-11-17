/*
 Licensed to the Apache Software Foundation (ASF) under one
 or more contributor license agreements.  See the NOTICE file
 distributed with this work for additional information
 regarding copyright ownership.  The ASF licenses this file
 to you under the Apache License, Version 2.0 (the
 "License"); you may not use this file except in compliance
 with the License.  You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing,
 software distributed under the License is distributed on an
 "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 KIND, either express or implied.  See the License for the
 specific language governing permissions and limitations
 under the License.
 */

#import "RCTBridge.h"
#import "RCTEventDispatcher.h"
#import "CDVFileTransfer.h"
#import "CDVCommandDelegateImpl.h"

#import <AssetsLibrary/ALAsset.h>
#import <AssetsLibrary/ALAssetRepresentation.h>
#import <AssetsLibrary/ALAssetsLibrary.h>
#import <CFNetwork/CFNetwork.h>

#define SET_DEFAULT(obj, defaultValue) ([obj isNull]?defaultValue:obj)

#ifndef DLog
#ifdef DEBUG
#define DLog(fmt, ...) NSLog((@"%s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)
#else
#define DLog(...)
#endif
#endif

@interface CDVFileTransfer ()

@property (nonatomic, strong) CDVCommandDelegateImpl* commandDelegate;

// Sets the requests headers for the request.
- (void)applyRequestHeaders:(NSDictionary*)headers toRequest:(NSMutableURLRequest*)req;
// Creates a delegate to handle an upload.
- (CDVFileTransferDelegate*)delegateForUploadCommand:(NSArray*)args;
// Creates an NSData* for the file for the given upload arguments.
- (void)fileDataForUploadCommand:(NSArray*)args;
@end

// Buffer size to use for streaming uploads.
static const NSUInteger kStreamBufferSize = 32768;
// Magic value within the options dict used to set a cookie.
NSString* const kOptionsKeyCookie = @"__cookie";
// Form boundary for multi-part requests.
NSString* const kFormBoundary = @"+++++org.apache.cordova.formBoundary";

// Writes the given data to the stream in a blocking way.
// If successful, returns bytesToWrite.
// If the stream was closed on the other end, returns 0.
// If there was an error, returns -1.
static CFIndex WriteDataToStream(NSData* data, CFWriteStreamRef stream)
{
    UInt8* bytes = (UInt8*)[data bytes];
    long long bytesToWrite = [data length];
    long long totalBytesWritten = 0;
    
    while (totalBytesWritten < bytesToWrite) {
        CFIndex result = CFWriteStreamWrite(stream,
                                            bytes + totalBytesWritten,
                                            bytesToWrite - totalBytesWritten);
        if (result < 0) {
            CFStreamError error = CFWriteStreamGetError(stream);
            NSLog(@"WriteStreamError domain: %ld error: %ld", error.domain, (long)error.error);
            return result;
        } else if (result == 0) {
            return result;
        }
        totalBytesWritten += result;
    }
    
    return totalBytesWritten;
}

@implementation CDVFileTransfer

@synthesize activeTransfers;
@synthesize bridge = _bridge;

RCT_EXPORT_MODULE(FileTransfer)

- (id)init {
    self = [super init];
    if (self) {
        self.commandDelegate = [[CDVCommandDelegateImpl alloc]init];
        activeTransfers = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (NSString*)escapePathComponentForUrlString:(NSString*)urlString
{
    NSRange schemeAndHostRange = [urlString rangeOfString:@"://.*?/" options:NSRegularExpressionSearch];
    
    if (schemeAndHostRange.length == 0) {
        return urlString;
    }
    
    NSInteger schemeAndHostEndIndex = NSMaxRange(schemeAndHostRange);
    NSString* schemeAndHost = [urlString substringToIndex:schemeAndHostEndIndex];
    NSString* pathComponent = [urlString substringFromIndex:schemeAndHostEndIndex];
    pathComponent = [pathComponent stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    
    return [schemeAndHost stringByAppendingString:pathComponent];
}

- (void)applyRequestHeaders:(NSDictionary*)headers toRequest:(NSMutableURLRequest*)req
{
    [req setValue:@"XMLHttpRequest" forHTTPHeaderField:@"X-Requested-With"];
    
    NSString* userAgent = nil;
    if (userAgent) {
        [req setValue:userAgent forHTTPHeaderField:@"User-Agent"];
    }
    
    for (NSString* headerName in headers) {
        id value = [headers objectForKey:headerName];
        if (!value || (value == [NSNull null])) {
            value = @"null";
        }
        
        // First, remove an existing header if one exists.
        [req setValue:nil forHTTPHeaderField:headerName];
        
        if (![value isKindOfClass:[NSArray class]]) {
            value = [NSArray arrayWithObject:value];
        }
        
        // Then, append all header values.
        for (id __strong subValue in value) {
            // Convert from an NSNumber -> NSString.
            if ([subValue respondsToSelector:@selector(stringValue)]) {
                subValue = [subValue stringValue];
            }
            if ([subValue isKindOfClass:[NSString class]]) {
                [req addValue:subValue forHTTPHeaderField:headerName];
            }
        }
    }
}

- (NSURLRequest*)requestForUploadCommand:(NSArray*)args fileData:(NSData*)fileData
{
    // arguments order from js: [filePath, server, fileKey, fileName, mimeType, params, debug, chunkedMode]
    // however, params is a JavaScript object and during marshalling is put into the options dict,
    // thus debug and chunkedMode are the 6th and 7th arguments
    NSString* target = args[0];
    NSString* server = args[1];
    NSString* fileKey = SET_DEFAULT(args[2], @"file");
    NSString* fileName = SET_DEFAULT(args[3], @"image.jpg");
    NSString* mimeType = SET_DEFAULT(args[4], @"image/jpeg");
    NSDictionary* options =  SET_DEFAULT(args[5], nil);
    //    BOOL trustAllHosts = [[command argumentAtIndex:6 withDefault:[NSNumber numberWithBool:YES]] boolValue]; // allow self-signed certs
    BOOL chunkedMode = [SET_DEFAULT(args[7], [NSNumber numberWithBool:YES]) boolValue];
    NSDictionary* headers = SET_DEFAULT(args[8], nil);
    // Allow alternative http method, default to POST. JS side checks
    // for allowed methods, currently PUT or POST (forces POST for
    // unrecognised values)
    NSString* httpMethod = SET_DEFAULT(args[10], @"POST");
    CDVPluginResult* result = nil;
    CDVFileTransferError errorCode = 0;
    
    // NSURL does not accepts URLs with spaces in the path. We escape the path in order
    // to be more lenient.
    NSURL* url = [NSURL URLWithString:server];
    
    if (!url) {
        errorCode = INVALID_URL_ERR;
        NSLog(@"File Transfer Error: Invalid server URL %@", server);
    } else if (!fileData) {
        errorCode = FILE_NOT_FOUND_ERR;
    }
    
    if (errorCode > 0) {
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:[self createFileTransferError:errorCode AndSource:target AndTarget:server]];
        [self.commandDelegate sendPluginResult:result];
        return nil;
    }
    
    NSMutableURLRequest* req = [NSMutableURLRequest requestWithURL:url];
    
    [req setHTTPMethod:httpMethod];
    
    //    Magic value to set a cookie
    if ([options objectForKey:kOptionsKeyCookie]) {
        [req setValue:[options objectForKey:kOptionsKeyCookie] forHTTPHeaderField:@"Cookie"];
        [req setHTTPShouldHandleCookies:NO];
    }
    
    // if we specified a Content-Type header, don't do multipart form upload
    BOOL multipartFormUpload = [headers objectForKey:@"Content-Type"] == nil;
    if (multipartFormUpload) {
        NSString* contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", kFormBoundary];
        [req setValue:contentType forHTTPHeaderField:@"Content-Type"];
    }
    [self applyRequestHeaders:headers toRequest:req];
    
    NSData* formBoundaryData = [[NSString stringWithFormat:@"--%@\r\n", kFormBoundary] dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData* postBodyBeforeFile = [NSMutableData data];
    
    for (NSString* key in options) {
        id val = [options objectForKey:key];
        if (!val || (val == [NSNull null]) || [key isEqualToString:kOptionsKeyCookie]) {
            continue;
        }
        // if it responds to stringValue selector (eg NSNumber) get the NSString
        if ([val respondsToSelector:@selector(stringValue)]) {
            val = [val stringValue];
        }
        // finally, check whether it is a NSString (for dataUsingEncoding selector below)
        if (![val isKindOfClass:[NSString class]]) {
            continue;
        }
        
        [postBodyBeforeFile appendData:formBoundaryData];
        [postBodyBeforeFile appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n", key] dataUsingEncoding:NSUTF8StringEncoding]];
        [postBodyBeforeFile appendData:[val dataUsingEncoding:NSUTF8StringEncoding]];
        [postBodyBeforeFile appendData:[@"\r\n" dataUsingEncoding : NSUTF8StringEncoding]];
    }
    
    [postBodyBeforeFile appendData:formBoundaryData];
    [postBodyBeforeFile appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n", fileKey, fileName] dataUsingEncoding:NSUTF8StringEncoding]];
    if (mimeType != nil) {
        [postBodyBeforeFile appendData:[[NSString stringWithFormat:@"Content-Type: %@\r\n", mimeType] dataUsingEncoding:NSUTF8StringEncoding]];
    }
    [postBodyBeforeFile appendData:[[NSString stringWithFormat:@"Content-Length: %ld\r\n\r\n", (long)[fileData length]] dataUsingEncoding:NSUTF8StringEncoding]];
    
    DLog(@"fileData length: %d", (int)[fileData length]);
    NSData* postBodyAfterFile = [[NSString stringWithFormat:@"\r\n--%@--\r\n", kFormBoundary] dataUsingEncoding:NSUTF8StringEncoding];
    
    long long totalPayloadLength = [fileData length];
    if (multipartFormUpload) {
        totalPayloadLength += [postBodyBeforeFile length] + [postBodyAfterFile length];
    }
    
    [req setValue:[[NSNumber numberWithLongLong:totalPayloadLength] stringValue] forHTTPHeaderField:@"Content-Length"];
    
    if (chunkedMode) {
        CFReadStreamRef readStream = NULL;
        CFWriteStreamRef writeStream = NULL;
        CFStreamCreateBoundPair(NULL, &readStream, &writeStream, kStreamBufferSize);
        [req setHTTPBodyStream:CFBridgingRelease(readStream)];
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            if (CFWriteStreamOpen(writeStream)) {
                if (multipartFormUpload) {
                    NSData* chunks[] = { postBodyBeforeFile, fileData, postBodyAfterFile };
                    int numChunks = sizeof(chunks) / sizeof(chunks[0]);
                    
                    for (int i = 0; i < numChunks; ++i) {
                        CFIndex result = WriteDataToStream(chunks[i], writeStream);
                        if (result <= 0) {
                            break;
                        }
                    }
                } else {
                    WriteDataToStream(fileData, writeStream);
                }
            } else {
                NSLog(@"FileTransfer: Failed to open writeStream");
            }
            CFWriteStreamClose(writeStream);
            CFRelease(writeStream);
        });
    } else {
        if (multipartFormUpload) {
            [postBodyBeforeFile appendData:fileData];
            [postBodyBeforeFile appendData:postBodyAfterFile];
            [req setHTTPBody:postBodyBeforeFile];
        } else {
            [req setHTTPBody:fileData];
        }
    }
    return req;
}

- (CDVFileTransferDelegate*)delegateForUploadCommand:(NSArray*)args
{
    NSString* source = args[0];
    NSString* server = args[1];
    BOOL trustAllHosts = [SET_DEFAULT(args[6], [NSNumber numberWithBool:NO]) boolValue]; // allow self-signed certs
    NSString* objectId = args[9];
    
    CDVFileTransferDelegate* delegate = [[CDVFileTransferDelegate alloc] init];
    
    delegate.command = self;
    delegate.direction = CDV_TRANSFER_UPLOAD;
    delegate.objectId = objectId;
    delegate.source = source;
    delegate.target = server;
    delegate.trustAllHosts = trustAllHosts;
    
    return delegate;
}

- (void)fileDataForUploadCommand:(NSArray *)args
{
    NSString* source = (NSString*)args[0];
    NSString* server = (NSString*)args[1];
    NSError* __autoreleasing err = nil;
    
    // Extract the path part out of a file: URL.
    NSString* filePath = [source hasPrefix:@"/"] ? [source copy] : [(NSURL *)[NSURL URLWithString:source] path];
    if (filePath == nil) {
        // We couldn't find the asset.  Send the appropriate error.
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:[self createFileTransferError:NOT_FOUND_ERR AndSource:source AndTarget:server]];
        [self.commandDelegate sendPluginResult:result];
        return;
    }
    
    // Memory map the file so that it can be read efficiently even if it is large.
    NSData* fileData = [NSData dataWithContentsOfFile:filePath options:NSDataReadingMappedIfSafe error:&err];
    
    if (err != nil) {
        NSLog(@"Error opening file %@: %@", source, err);
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:[self createFileTransferError:NOT_FOUND_ERR AndSource:source AndTarget:server]];
        [self.commandDelegate sendPluginResult:result];
    } else {
        [self uploadData:fileData args:args];
    }
}

RCT_EXPORT_METHOD(upload:(NSArray *)args success:(RCTResponseSenderBlock)success error:(RCTResponseSenderBlock)error) {
    [self.commandDelegate setCallback:success error:error];
    // fileData and req are split into helper functions to ease the unit testing of delegateForUpload.
    // First, get the file data.  This method will call `uploadData:command`.
    [self fileDataForUploadCommand:args];
}

- (void)uploadData:(NSData*)fileData args:(NSArray *)args
{
    NSURLRequest* req = [self requestForUploadCommand:args fileData:fileData];
    
    if (req == nil) {
        return;
    }
    CDVFileTransferDelegate* delegate = [self delegateForUploadCommand:args];
    delegate.connection = [[NSURLConnection alloc] initWithRequest:req delegate:delegate startImmediately:NO];
    if (self.queue == nil) {
        self.queue = [[NSOperationQueue alloc] init];
    }
    [delegate.connection setDelegateQueue:self.queue];
    
    // sets a background task ID for the transfer object.
    delegate.backgroundTaskID = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        [delegate cancelTransfer:delegate.connection];
    }];
    
    @synchronized (activeTransfers) {
        activeTransfers[delegate.objectId] = delegate;
    }
    [delegate.connection start];
}

RCT_EXPORT_METHOD(abort:(NSArray *)args success:(RCTResponseSenderBlock)success error:(RCTResponseSenderBlock)error) {
    [self.commandDelegate setCallback:success error:error];
    NSString* objectId = args[0];
    
    @synchronized (activeTransfers) {
        CDVFileTransferDelegate* delegate = activeTransfers[objectId];
        if (delegate != nil) {
            [delegate cancelTransfer:delegate.connection];
            CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:[self createFileTransferError:CONNECTION_ABORTED AndSource:delegate.source AndTarget:delegate.target]];
            [self.commandDelegate sendPluginResult:result];
        }
    }
}

RCT_EXPORT_METHOD(download:(NSArray *)args success:(RCTResponseSenderBlock)success error:(RCTResponseSenderBlock)error) {
    [self.commandDelegate setCallback:success error:error];
    DLog(@"File Transfer downloading file...");
    NSString* source = args[0];
    NSString* target = args[1];
    BOOL trustAllHosts = [SET_DEFAULT(args[2],[NSNumber numberWithBool:NO]) boolValue]; // allow self-signed certs
    NSString* objectId = args[3];
    NSDictionary* headers = SET_DEFAULT(args[4],nil);
    
    CDVPluginResult* result = nil;
    CDVFileTransferError errorCode = 0;
    
    NSURL* sourceURL = [NSURL URLWithString:source];
    
    if (!sourceURL) {
        errorCode = INVALID_URL_ERR;
        NSLog(@"File Transfer Error: Invalid server URL %@", source);
    }
    
    if (errorCode > 0) {
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:[self createFileTransferError:errorCode AndSource:source AndTarget:target]];
        [self.commandDelegate sendPluginResult:result];
        return;
    }
    
    NSMutableURLRequest* req = [NSMutableURLRequest requestWithURL:sourceURL];
    [self applyRequestHeaders:headers toRequest:req];
    
    CDVFileTransferDelegate* delegate = [[CDVFileTransferDelegate alloc] init];
    delegate.command = self;
    delegate.direction = CDV_TRANSFER_DOWNLOAD;
    delegate.objectId = objectId;
    delegate.source = source;
    delegate.target = target;
    delegate.trustAllHosts = trustAllHosts;
    delegate.backgroundTaskID = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        [delegate cancelTransfer:delegate.connection];
    }];
    
    delegate.connection = [[NSURLConnection alloc] initWithRequest:req delegate:delegate startImmediately:NO];
    
    if (self.queue == nil) {
        self.queue = [[NSOperationQueue alloc] init];
    }
    [delegate.connection setDelegateQueue:self.queue];
    
    @synchronized (activeTransfers) {
        activeTransfers[delegate.objectId] = delegate;
    }
    // Downloads can take time
    // sending this to a new thread calling the download_async method
    dispatch_async(
                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, (unsigned long)NULL),
                   ^(void) { [delegate.connection start];}
                   );
}

- (NSMutableDictionary*)createFileTransferError:(int)code AndSource:(NSString*)source AndTarget:(NSString*)target
{
    NSMutableDictionary* result = [NSMutableDictionary dictionaryWithCapacity:3];
    
    [result setObject:[NSNumber numberWithInt:code] forKey:@"code"];
    if (source != nil) {
        [result setObject:source forKey:@"source"];
    }
    if (target != nil) {
        [result setObject:target forKey:@"target"];
    }
    NSLog(@"FileTransferError %@", result);
    
    return result;
}

- (NSMutableDictionary*)createFileTransferError:(int)code
                                      AndSource:(NSString*)source
                                      AndTarget:(NSString*)target
                                  AndHttpStatus:(int)httpStatus
                                        AndBody:(NSString*)body
{
    NSMutableDictionary* result = [NSMutableDictionary dictionaryWithCapacity:5];
    
    [result setObject:[NSNumber numberWithInt:code] forKey:@"code"];
    if (source != nil) {
        [result setObject:source forKey:@"source"];
    }
    if (target != nil) {
        [result setObject:target forKey:@"target"];
    }
    [result setObject:[NSNumber numberWithInt:httpStatus] forKey:@"http_status"];
    if (body != nil) {
        [result setObject:body forKey:@"body"];
    }
    NSLog(@"FileTransferError %@", result);
    
    return result;
}

- (void)onReset {
    @synchronized (activeTransfers) {
        while ([activeTransfers count] > 0) {
            CDVFileTransferDelegate* delegate = [activeTransfers allValues][0];
            [delegate cancelTransfer:delegate.connection];
        }
    }
}

@end

@interface CDVFileTransferEntityLengthRequest : NSObject {
    NSURLConnection* _connection;
    CDVFileTransferDelegate* __weak _originalDelegate;
}

- (CDVFileTransferEntityLengthRequest*)initWithOriginalRequest:(NSURLRequest*)originalRequest andDelegate:(CDVFileTransferDelegate*)originalDelegate;

@end

@implementation CDVFileTransferEntityLengthRequest

- (CDVFileTransferEntityLengthRequest*)initWithOriginalRequest:(NSURLRequest*)originalRequest andDelegate:(CDVFileTransferDelegate*)originalDelegate
{
    if (self) {
        DLog(@"Requesting entity length for GZIPped content...");
        
        NSMutableURLRequest* req = [originalRequest mutableCopy];
        [req setHTTPMethod:@"HEAD"];
        [req setValue:@"identity" forHTTPHeaderField:@"Accept-Encoding"];
        
        _originalDelegate = originalDelegate;
        _connection = [NSURLConnection connectionWithRequest:req delegate:self];
    }
    return self;
}

- (void)connection:(NSURLConnection*)connection didReceiveResponse:(NSURLResponse*)response
{
    DLog(@"HEAD request returned; content-length is %lld", [response expectedContentLength]);
    [_originalDelegate updateBytesExpected:[response expectedContentLength]];
}

- (void)connection:(NSURLConnection*)connection didReceiveData:(NSData*)data
{}

- (void)connectionDidFinishLoading:(NSURLConnection*)connection
{}

@end

@implementation CDVFileTransferDelegate

@synthesize connection = _connection, source, target, responseData, responseHeaders, command, bytesTransfered, bytesExpected, direction, responseCode, objectId, targetFileHandle;

- (void)connectionDidFinishLoading:(NSURLConnection*)connection
{
    NSString* uploadResponse = nil;
    NSString* downloadResponse = nil;
    NSMutableDictionary* uploadResult;
    CDVPluginResult* result = nil;
    
    NSLog(@"File Transfer Finished with response code %d", self.responseCode);
    
    if (self.direction == CDV_TRANSFER_UPLOAD) {
        uploadResponse = [[NSString alloc] initWithData:self.responseData encoding:NSUTF8StringEncoding];
        
        if ((self.responseCode >= 200) && (self.responseCode < 300)) {
            // create dictionary to return FileUploadResult object
            uploadResult = [NSMutableDictionary dictionaryWithCapacity:3];
            if (uploadResponse != nil) {
                [uploadResult setObject:uploadResponse forKey:@"response"];
                [uploadResult setObject:self.responseHeaders forKey:@"headers"];
            }
            [uploadResult setObject:[NSNumber numberWithLongLong:self.bytesTransfered] forKey:@"bytesSent"];
            [uploadResult setObject:[NSNumber numberWithInt:self.responseCode] forKey:@"responseCode"];
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:uploadResult];
        } else {
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:[command createFileTransferError:CONNECTION_ERR AndSource:source AndTarget:target AndHttpStatus:self.responseCode AndBody:uploadResponse]];
        }
    }
    if (self.direction == CDV_TRANSFER_DOWNLOAD) {
        if (self.targetFileHandle) {
            [self.targetFileHandle closeFile];
            self.targetFileHandle = nil;
            DLog(@"File Transfer Download success");
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:@{@"file":self.target}];
        } else {
            downloadResponse = [[NSString alloc] initWithData:self.responseData encoding:NSUTF8StringEncoding];
            CDVFileTransferError errorCode = self.responseCode == 404 ? FILE_NOT_FOUND_ERR
            : (self.responseCode == 304 ? NOT_MODIFIED : CONNECTION_ERR);
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:[command createFileTransferError:errorCode AndSource:source AndTarget:target AndHttpStatus:self.responseCode AndBody:downloadResponse]];
        }
    }
    [self.command.commandDelegate sendPluginResult:result];
    
    // remove connection for activeTransfers
    @synchronized (command.activeTransfers) {
        [command.activeTransfers removeObjectForKey:objectId];
        // remove background id task in case our upload was done in the background
        [[UIApplication sharedApplication] endBackgroundTask:self.backgroundTaskID];
        self.backgroundTaskID = UIBackgroundTaskInvalid;
    }
}

- (void)removeTargetFile
{
    NSFileManager* fileMgr = [NSFileManager defaultManager];
    
    NSString *targetPath = [self targetFilePath];
    if ([fileMgr fileExistsAtPath:targetPath])
    {
        [fileMgr removeItemAtPath:targetPath error:nil];
    }
}

- (void)cancelTransfer:(NSURLConnection*)connection
{
    [connection cancel];
    @synchronized (self.command.activeTransfers) {
        CDVFileTransferDelegate* delegate = self.command.activeTransfers[self.objectId];
        [self.command.activeTransfers removeObjectForKey:self.objectId];
        [[UIApplication sharedApplication] endBackgroundTask:delegate.backgroundTaskID];
        delegate.backgroundTaskID = UIBackgroundTaskInvalid;
    }
    
    [self removeTargetFile];
}

- (void)cancelTransferWithError:(NSURLConnection*)connection errorMessage:(NSString*)errorMessage
{
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_IO_EXCEPTION messageAsDictionary:[self.command createFileTransferError:FILE_NOT_FOUND_ERR AndSource:self.source AndTarget:self.target AndHttpStatus:self.responseCode AndBody:errorMessage]];
    
    NSLog(@"File Transfer Error: %@", errorMessage);
    [self cancelTransfer:connection];
    [self.command.commandDelegate sendPluginResult:result];
}

- (NSString *)targetFilePath
{
    NSString *path = [self.target hasPrefix:@"/"] ? [self.target copy] : [(NSURL *)[NSURL URLWithString:self.target] path];
    return path;
}

- (void)connection:(NSURLConnection*)connection didReceiveResponse:(NSURLResponse*)response
{
    NSError* __autoreleasing error = nil;
    
    self.mimeType = [response MIMEType];
    self.targetFileHandle = nil;
    
    // required for iOS 4.3, for some reason; response is
    // a plain NSURLResponse, not the HTTP subclass
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
        
        self.responseCode = (int)[httpResponse statusCode];
        self.bytesExpected = [response expectedContentLength];
        self.responseHeaders = [httpResponse allHeaderFields];
        if ((self.direction == CDV_TRANSFER_DOWNLOAD) && (self.responseCode == 200) && (self.bytesExpected == NSURLResponseUnknownLength)) {
            // Kick off HEAD request to server to get real length
            // bytesExpected will be updated when that response is returned
            self.entityLengthRequest = [[CDVFileTransferEntityLengthRequest alloc] initWithOriginalRequest:connection.currentRequest andDelegate:self];
        }
    } else if ([response.URL isFileURL]) {
        NSDictionary* attr = [[NSFileManager defaultManager] attributesOfItemAtPath:[response.URL path] error:nil];
        self.responseCode = 200;
        self.bytesExpected = [attr[NSFileSize] longLongValue];
    } else {
        self.responseCode = 200;
        self.bytesExpected = NSURLResponseUnknownLength;
    }
    if ((self.direction == CDV_TRANSFER_DOWNLOAD) && (self.responseCode >= 200) && (self.responseCode < 300)) {
        // Download response is okay; begin streaming output to file
        NSString *filePath = [self targetFilePath];
        if (filePath == nil) {
            // We couldn't find the asset.  Send the appropriate error.
            [self cancelTransferWithError:connection errorMessage:[NSString stringWithFormat:@"Could not create target file"]];
            return;
        }
        
        NSString* parentPath = [filePath stringByDeletingLastPathComponent];
        
        // create parent directories if needed
        if ([[NSFileManager defaultManager] createDirectoryAtPath:parentPath withIntermediateDirectories:YES attributes:nil error:&error] == NO) {
            if (error) {
                [self cancelTransferWithError:connection errorMessage:[NSString stringWithFormat:@"Could not create path to save downloaded file: %@", [error localizedDescription]]];
            } else {
                [self cancelTransferWithError:connection errorMessage:@"Could not create path to save downloaded file"];
            }
            return;
        }
        // create target file
        if ([[NSFileManager defaultManager] createFileAtPath:filePath contents:nil attributes:nil] == NO) {
            [self cancelTransferWithError:connection errorMessage:@"Could not create target file"];
            return;
        }
        // open target file for writing
        self.targetFileHandle = [NSFileHandle fileHandleForWritingAtPath:filePath];
        if (self.targetFileHandle == nil) {
            [self cancelTransferWithError:connection errorMessage:@"Could not open target file for writing"];
        }
        DLog(@"Streaming to file %@", filePath);
    }
}

- (void)connection:(NSURLConnection*)connection didFailWithError:(NSError*)error
{
    NSString* body = [[NSString alloc] initWithData:self.responseData encoding:NSUTF8StringEncoding];
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:[command createFileTransferError:CONNECTION_ERR AndSource:source AndTarget:target AndHttpStatus:self.responseCode AndBody:body]];
    
    NSLog(@"File Transfer Error: %@", [error localizedDescription]);
    
    [self cancelTransfer:connection];
    [self.command.commandDelegate sendPluginResult:result];
}

- (void)connection:(NSURLConnection*)connection didReceiveData:(NSData*)data
{
    self.bytesTransfered += data.length;
    if (self.targetFileHandle) {
        [self.targetFileHandle writeData:data];
    } else {
        [self.responseData appendData:data];
    }
    [self updateProgress];
}

- (void)updateBytesExpected:(long long)newBytesExpected
{
    DLog(@"Updating bytesExpected to %lld", newBytesExpected);
    self.bytesExpected = newBytesExpected;
    [self updateProgress];
}

- (void)updateProgress
{
    if (self.direction == CDV_TRANSFER_DOWNLOAD) {
        BOOL lengthComputable = (self.bytesExpected != NSURLResponseUnknownLength);
        // If the response is GZipped, and we have an outstanding HEAD request to get
        // the length, then hold off on sending progress events.
        if (!lengthComputable && (self.entityLengthRequest != nil)) {
            return;
        }
        NSMutableDictionary* downloadProgress = [NSMutableDictionary dictionaryWithCapacity:3];
        [downloadProgress setObject:[NSNumber numberWithBool:lengthComputable] forKey:@"lengthComputable"];
        [downloadProgress setObject:[NSNumber numberWithLongLong:self.bytesTransfered] forKey:@"loaded"];
        [downloadProgress setObject:[NSNumber numberWithLongLong:self.bytesExpected] forKey:@"total"];
        
        [self.command.bridge.eventDispatcher sendAppEventWithName:@"downloadProgress" body:@{@"progress": downloadProgress}];
    }
}

- (void)connection:(NSURLConnection*)connection didSendBodyData:(NSInteger)bytesWritten totalBytesWritten:(NSInteger)totalBytesWritten totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite
{
    if (self.direction == CDV_TRANSFER_UPLOAD) {
        NSMutableDictionary* uploadProgress = [NSMutableDictionary dictionaryWithCapacity:3];
        
        [uploadProgress setObject:[NSNumber numberWithBool:true] forKey:@"lengthComputable"];
        [uploadProgress setObject:[NSNumber numberWithLongLong:totalBytesWritten] forKey:@"loaded"];
        [uploadProgress setObject:[NSNumber numberWithLongLong:totalBytesExpectedToWrite] forKey:@"total"];
        
        [self.command.bridge.eventDispatcher sendAppEventWithName:@"uploadProgress" body:@{@"progress": uploadProgress}];
    }
    self.bytesTransfered = totalBytesWritten;
}

// for self signed certificates
- (void)connection:(NSURLConnection*)connection willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge*)challenge
{
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        if (self.trustAllHosts) {
            NSURLCredential* credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
            [challenge.sender useCredential:credential forAuthenticationChallenge:challenge];
        }
        [challenge.sender continueWithoutCredentialForAuthenticationChallenge:challenge];
    } else {
        [challenge.sender performDefaultHandlingForAuthenticationChallenge:challenge];
    }
}

- (id)init
{
    if ((self = [super init])) {
        self.responseData = [NSMutableData data];
        self.targetFileHandle = nil;
    }
    return self;
}

@end
