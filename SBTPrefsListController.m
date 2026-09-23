#import "SBTPrefsListController.h"
#import <Preferences/PSSpecifier.h>

static NSString *const kSBTDomain = @"com.pizzasdu83.slipperybatt";

static BOOL SBTPrefBool(NSString *key, BOOL fallback) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)kSBTDomain);
    CFPropertyListRef ref = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                      (__bridge CFStringRef)kSBTDomain);
    if (!ref) return fallback;
    id obj = (__bridge_transfer id)ref;
    return [obj respondsToSelector:@selector(boolValue)] ? [obj boolValue] : fallback;
}

@implementation SBTPrefsListController {
    // Latest value of the three switches that change which rows are visible.
    NSMutableDictionary<NSString *, NSNumber *> *_sbtToggles;
}

- (BOOL)sbtToggle:(NSString *)key fallback:(BOOL)fallback {
    NSNumber *cached = _sbtToggles[key];
    if (cached) return cached.boolValue;
    return SBTPrefBool(key, fallback);
}

// Rows are shown or hidden according to the prefix of their "id" in Root.plist:
//   (no id)  always visible                          -> master switch
//   en_...   visible when the tweak is enabled       -> 3DS switch
//   cu_...   enabled AND 3DS mode off                -> custom colors
//   gr_...   enabled AND 3DS off AND gradient on     -> gradient-only rows
- (NSArray *)specifiers {
    if (!_specifiers) {
        NSArray *all = [self loadSpecifiersFromPlistName:@"Root" target:self];

        BOOL enabled    = [self sbtToggle:@"Enabled" fallback:YES];
        BOOL mode3DS    = [self sbtToggle:@"Mode3DS" fallback:NO];
        BOOL gradient   = [self sbtToggle:@"GradientEnabled" fallback:NO];
        BOOL percentage = [self sbtToggle:@"ShowPercentage" fallback:NO];

        NSMutableArray *visible = [NSMutableArray array];
        for (PSSpecifier *spec in all) {
            NSString *ident = spec.identifier ?: @"";
            BOOL show = YES;
            if ([ident hasPrefix:@"en_"])      show = enabled;
            else if ([ident hasPrefix:@"pc_"]) show = enabled && percentage;
            else if ([ident hasPrefix:@"cu_"]) show = enabled && !mode3DS;
            else if ([ident hasPrefix:@"gr_"]) show = enabled && !mode3DS && gradient;
            if (show) [visible addObject:spec];
        }
        _specifiers = visible;
    }
    return _specifiers;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    BOOL isToggle = [key isEqualToString:@"Enabled"] ||
                    [key isEqualToString:@"Mode3DS"] ||
                    [key isEqualToString:@"GradientEnabled"] ||
                    [key isEqualToString:@"ShowPercentage"];
    if (isToggle) {
        if (!_sbtToggles) _sbtToggles = [NSMutableDictionary dictionary];
        _sbtToggles[key] = @([value boolValue]);
    }

    [super setPreferenceValue:value specifier:specifier];

    if (isToggle) {
        __weak SBTPrefsListController *weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf sbtRebuild];
        });
    }
}

- (void)sbtRebuild {
    _specifiers = nil;
    [self reloadSpecifiers];
}

- (void)confirmResetSettings {
    NSIndexPath *selected = self.table.indexPathForSelectedRow;
    if (selected) [self.table deselectRowAtIndexPath:selected animated:YES];

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Reset All Settings?"
        message:@"This restores Slippery Batt to its default colors and modes."
        preferredStyle:UIAlertControllerStyleAlert];

    __weak SBTPrefsListController *weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive
        handler:^(UIAlertAction *action) {
            [weakSelf sbtPerformReset];
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)sbtPerformReset {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kSBTDomain];
    NSArray<NSString *> *keys = @[
        @"Enabled", @"Mode3DS", @"GradientEnabled", @"ShowPercentage",
        @"FlipHorizontal", @"PercentPosX", @"PercentPosY", @"Angle",
        @"NormalColor1", @"NormalColor2",
        @"LowPowerColor1", @"LowPowerColor2",
        @"LowColor1", @"LowColor2",
    ];
    for (NSString *key in keys) [defaults removeObjectForKey:key];
    [defaults synchronize];

    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.pizzasdu83.slipperybatt/reload"), NULL, NULL, YES);

    [_sbtToggles removeAllObjects];
    [self sbtRebuild];
}

@end
