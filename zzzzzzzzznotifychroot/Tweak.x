#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <spawn.h>
#include "../config.h"

static UIWindow *window = nil;
static BOOL autoEnabled;

static void easy_spawn(const char *args[]) {
    pid_t pid;
    int status;
    posix_spawn(&pid, args[0], NULL, NULL, (char * const*)args, NULL);
    waitpid(pid, &status, WEXITED);
}

@interface FBSSystemService : NSObject
+ (instancetype)sharedService;
- (int)pidForApplication:(NSString *)bundleId;
@end

@interface RBSProcessIdentity
@property (nonatomic, readonly) NSString *embeddedApplicationIdentifier;
@end

@interface FBProcessExecutionContext
@property (nonatomic, assign) NSDictionary *environment;
@property (nonatomic, assign) RBSProcessIdentity *identity;
@end

@interface FBApplicationProcess
@property (nonatomic, assign) FBProcessExecutionContext *executionContext;
@end

extern CFNotificationCenterRef CFNotificationCenterGetDistributedCenter(void);

BOOL isEnableApplication(NSString *bundleID) {
    NSDictionary *pref = [NSDictionary dictionaryWithContentsOfFile:PREF_PATH];

    if (!pref || pref[bundleID] == nil) {
        return NO;
    }

    return [pref[bundleID] boolValue];
}

void bypassApplication(NSString *bundleID) {
    int pid = [[%c(FBSSystemService) sharedService] pidForApplication:bundleID];

    if (isEnableApplication(bundleID) && pid != -1) {
        NSDictionary *info = @{
            @"Pid" : [NSNumber numberWithInt:pid]
        };

        CFNotificationCenterPostNotification(CFNotificationCenterGetDistributedCenter(), CFSTR(Notify_Chrooter), NULL, (__bridge CFDictionaryRef)info, YES);

        kill(pid, SIGSTOP);
    }
}

%group SpringBoardHook

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)arg1 {
    %orig;
    // Automatically enabled on Reboot and Re-Jailbreak etc
    if (autoEnabled && access(kernbypassMem, F_OK) != 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^(void) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Enable KernByPass?"
                                                                           message:@"​Run kernbypassd"
                                                                    preferredStyle:UIAlertControllerStyleAlert];

            window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
            window.windowLevel = UIWindowLevelAlert;

            [window makeKeyAndVisible];
            window.rootViewController = [[UIViewController alloc] init];
            UIViewController *vc = window.rootViewController;

            UIAlertAction *caAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                window.hidden = YES;
                window = nil;
            }];

            UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"YES" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                window.hidden = YES;
                window = nil;
                // run kernbypassd
                NSMutableDictionary *mutableDict = [[NSMutableDictionary alloc] initWithContentsOfFile:PREF_PATH]?:[NSMutableDictionary dictionary];
                [mutableDict setObject:@YES forKey:@"autoEnabled"];
                [mutableDict writeToFile:PREF_PATH atomically:YES];
                CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR(Notify_Preferences), NULL, NULL, YES);
                easy_spawn((const char *[]){"/usr/bin/kernbypassd", NULL});
                // touch /tmp/kernbypassdAlertMem
                FILE *fp = fopen(kernbypassdAlertMem, "w");
                fclose(fp);
            }];

            [alert addAction:caAction];
            [alert addAction:okAction];

            alert.preferredAction = okAction;

            [vc presentViewController:alert animated:YES completion:nil];
        });
    }
    // Alert prompting for Reboot when using previous version
    if ([[NSFileManager defaultManager] removeItemAtPath:@rebootMem error:nil]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"KernByPass Unofficial"
                                                                       message:@"[Note] Please reboot before Enable!!"
                                                                preferredStyle:UIAlertControllerStyleAlert];

        window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
        window.windowLevel = UIWindowLevelAlert;

        [window makeKeyAndVisible];
        window.rootViewController = [[UIViewController alloc] init];
        UIViewController *vc = window.rootViewController;

        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            window.hidden = YES;
            window = nil;
        }];

        [alert addAction:okAction];

        [vc presentViewController:alert animated:YES completion:nil];
    }
}
%end

%hook FBApplicationProcess
- (void)launchWithDelegate:(id)delegate {
    NSDictionary *env = self.executionContext.environment;
    %orig;
    // Choicy compatible
    if (env[@"_MSSafeMode"] || env[@"_SafeMode"]) {
        bypassApplication(self.executionContext.identity.embeddedApplicationIdentifier);
    }
}
%end

%end // SpringBoardHook End

static void settingsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:PREF_PATH];
    autoEnabled = (BOOL)[dict[@"autoEnabled"] ?: @NO boolValue];
}

static void notifyAlert(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    if (access(kernbypassMem, F_OK) == 0 && access(kernbypassdAlertMem, F_OK) == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                       message:@"Enabled KernBypass"
                                                                preferredStyle:UIAlertControllerStyleAlert];

        window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
        window.windowLevel = UIWindowLevelAlert;

        [window makeKeyAndVisible];
        window.rootViewController = [[UIViewController alloc] init];
        UIViewController *vc = window.rootViewController;

        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            window.hidden = YES;
            window = nil;
            remove(kernbypassdAlertMem);
        }];

        [alert addAction:okAction];

        [vc presentViewController:alert animated:YES completion:nil];
    } else if (access(kernbypassdAlertMem, F_OK) == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                       message:@"Failed"
                                                                preferredStyle:UIAlertControllerStyleAlert];

        window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
        window.windowLevel = UIWindowLevelAlert;

        [window makeKeyAndVisible];
        window.rootViewController = [[UIViewController alloc] init];
        UIViewController *vc = window.rootViewController;

        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            window.hidden = YES;
            window = nil;
            remove(kernbypassdAlertMem);
        }];

        [alert addAction:okAction];

        [vc presentViewController:alert animated:YES completion:nil];
    }
}

%ctor {
    // Settings Notifications
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL,
                                    settingsChanged,
                                    CFSTR(Notify_Preferences),
                                    NULL,
                                    CFNotificationSuspensionBehaviorCoalesce);

    settingsChanged(NULL, NULL, NULL, NULL, NULL);

    // Alert Notifications
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL,
                                    notifyAlert,
                                    CFSTR(Notify_Alert),
                                    NULL,
                                    CFNotificationSuspensionBehaviorCoalesce);

    NSString *identifier = [[NSBundle mainBundle] bundleIdentifier];

    if ([identifier isEqualToString:@"com.apple.springboard"]) {
        %init(SpringBoardHook);
    } else {
        bypassApplication(identifier);
    }
}
