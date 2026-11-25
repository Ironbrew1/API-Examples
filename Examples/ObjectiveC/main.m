// Build and run:
//   GNUstep (Linux): clang `gnustep-config --objc-flags` main.m `gnustep-config --base-libs` -o main && ./main
//   macOS:           clang -fno-objc-arc -framework Foundation main.m -o main && ./main
#import <Foundation/Foundation.h>

static NSString *const kBaseURL = @"https://ironbrew1.com";
static NSString *const kAPIKey = @"IB1-APIKEYHERE";

static NSString *const kInputPath = @"input.lua";
static NSString *const kOutputPath = @"output.lua";

static NSString *const kQuery = @"platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false";

static const int kRetryDelay = 5;
static const int kMaxWait = 240;
static const int kMaxFails = 3;

static void Fail(NSString *message) {
    fprintf(stderr, "%s\n", [message UTF8String]);
    exit(1);
}

static BOOL Ok(NSInteger code) {
    return code >= 200 && code < 300;
}

// Returns the HTTP status code (0 on transport errors) and stores the response body.
static NSInteger Request(NSString *method, NSString *path, NSData *body, NSData **responseData) {
    NSURL *url = [NSURL URLWithString:[kBaseURL stringByAppendingString:path]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:120];
    [request setHTTPMethod:method];
    [request setValue:kAPIKey forHTTPHeaderField:@"Key"];
    if (body != nil) {
        [request setValue:@"text/plain" forHTTPHeaderField:@"Content-Type"];
        [request setHTTPBody:body];
    }

    NSHTTPURLResponse *response = nil;
    NSError *error = nil;
    NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    *responseData = data != nil ? data : [NSData data];
    return response != nil ? [response statusCode] : 0;
}

static NSDictionary *ParseJSON(NSData *data) {
    NSDictionary *object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![object isKindOfClass:[NSDictionary class]]) {
        Fail(@"Unable to decode JSON");
    }
    return object;
}

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    NSData *source = [NSData dataWithContentsOfFile:kInputPath];
    if (source == nil) {
        Fail([NSString stringWithFormat:@"Unable to read %@", kInputPath]);
    }

    NSData *data = nil;
    NSInteger code = Request(@"POST", [@"/obfuscate?" stringByAppendingString:kQuery], source, &data);
    if (!Ok(code)) {
        Fail([NSString stringWithFormat:@"Unable to queue obfuscation: %ld", (long)code]);
    }

    NSDictionary *queued = ParseJSON(data);
    printf("Obfuscation started with GUID: %s\n", [[queued objectForKey:@"uploadGuid"] UTF8String]);

    int elapsed = 0, fails = 0, wait = 0;

    for (;;) {
        wait += kRetryDelay;
        [NSThread sleepForTimeInterval:wait];
        elapsed += wait;

        code = Request(@"GET", [queued objectForKey:@"statusUrl"], nil, &data);
        if (!Ok(code)) {
            fails++;
            printf("Status check failed with status: %ld (%d/%d)\n", (long)code, fails, kMaxFails);
            if (fails >= kMaxFails || elapsed >= kMaxWait) {
                Fail([NSString stringWithFormat:@"Obfuscation failed (fails: %d | elapsed time: %d)", fails, elapsed]);
            }
            continue;
        }

        NSDictionary *status = ParseJSON(data);
        NSString *state = [status objectForKey:@"status"];

        if ([state isEqualToString:@"completed"]) {
            printf("Obfuscation completed in %d seconds\n", elapsed);
            NSData *script = nil;
            code = Request(@"GET", [status objectForKey:@"downloadUrl"], nil, &script);
            if (!Ok(code)) {
                Fail([NSString stringWithFormat:@"Download failed with status: %ld", (long)code]);
            }
            if (![script writeToFile:kOutputPath atomically:YES]) {
                Fail([NSString stringWithFormat:@"Unable to write %@", kOutputPath]);
            }
            printf("Saved obfuscated script to %s\n", [kOutputPath UTF8String]);
            break;
        }

        if ([state isEqualToString:@"failed"] || elapsed >= kMaxWait) {
            Fail([NSString stringWithFormat:@"Obfuscation failed (status: %@ | elapsed time: %d)", state, elapsed]);
        }

        printf("Obfuscation is still in progress. Elapsed time: %d seconds. Checking again in %d seconds.\n",
               elapsed, kRetryDelay + wait);
    }

    [pool drain];
    return 0;
}
