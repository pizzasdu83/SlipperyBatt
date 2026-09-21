// Slippery Batt - recolor the battery icon (solid color, gradient, 3DS mode)
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>

#define SBT_DOMAIN CFSTR("com.pizzasdu83.slipperybatt")
#define SBT_NOTIFY "com.pizzasdu83.slipperybatt/reload"
#define SBT_VIEWDUMP_PATH @"/var/mobile/Documents/SlipperyBatt-viewdump.txt"

// 16x6 black plug glyph (the 3DS charging icon), embedded so no extra file has to be uploaded.
static NSString *const kSBTPlugBase64 =
    @"iVBORw0KGgoAAAANSUhEUgAAABAAAAAGCAYAAADKfB7nAAAAJklEQVR42mNkwAT/GfADRlwcQhqx6mPEoYBow5gYKAQ08QJJgQgAQFYFB+Ym9QEAAAAASUVORK5CYII=";

typedef NS_ENUM(NSInteger, SBTState) {
    SBTStateNormal = 0,
    SBTStateLowPower = 1,   // Low Power Mode (green in 3DS mode)
    SBTStateLow = 2,        // 20% or less (and charging, in 3DS mode) -> orange in 3DS mode
};

// ---- Preference state (refreshed on darwin notification + 1s poll) ----
static BOOL sbtEnabled = YES;
static BOOL sbtMode3DS = NO;
static BOOL sbtGradient = NO;
static CGFloat sbtAngle = 0.0f;
// One entry per SBTState: a UIColor, or NSNull when the hex is empty/invalid
// (= keep the stock color for that state).
static NSArray *sbtColors1;
static NSArray *sbtColors2;

static BOOL SBTReadBool(CFStringRef key, BOOL fallback) {
    CFPropertyListRef ref = CFPreferencesCopyAppValue(key, SBT_DOMAIN);
    if (!ref) return fallback;
    id obj = (__bridge_transfer id)ref;
    return [obj respondsToSelector:@selector(boolValue)] ? [obj boolValue] : fallback;
}

static double SBTReadDouble(CFStringRef key, double fallback) {
    CFPropertyListRef ref = CFPreferencesCopyAppValue(key, SBT_DOMAIN);
    if (!ref) return fallback;
    id obj = (__bridge_transfer id)ref;
    return [obj respondsToSelector:@selector(doubleValue)] ? [obj doubleValue] : fallback;
}

static NSString *SBTReadString(CFStringRef key, NSString *fallback) {
    CFPropertyListRef ref = CFPreferencesCopyAppValue(key, SBT_DOMAIN);
    if (!ref) return fallback;
    id obj = (__bridge_transfer id)ref;
    return [obj isKindOfClass:[NSString class]] ? obj : fallback;
}

// Returns nil if the string isn't a valid 6-digit hex color.
static UIColor *SBTColorFromHex(NSString *hex) {
    if (!hex) return nil;
    NSString *s = [hex stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([s hasPrefix:@"#"]) s = [s substringFromIndex:1];
    if (s.length != 6) return nil;
    unsigned int rgbValue = 0;
    NSScanner *scanner = [NSScanner scannerWithString:s];
    if (![scanner scanHexInt:&rgbValue] || !scanner.isAtEnd) return nil;
    CGFloat r = ((rgbValue & 0xFF0000) >> 16) / 255.0f;
    CGFloat g = ((rgbValue & 0x00FF00) >> 8) / 255.0f;
    CGFloat b = (rgbValue & 0x0000FF) / 255.0f;
    return [UIColor colorWithRed:r green:g blue:b alpha:1.0f];
}

static id SBTReadColor(CFStringRef key, NSString *fallbackHex) {
    UIColor *c = SBTColorFromHex(SBTReadString(key, fallbackHex));
    return c ? (id)c : (id)[NSNull null];
}

static void SBTLoadPrefs(void) {
    CFPreferencesAppSynchronize(SBT_DOMAIN);

    sbtEnabled  = SBTReadBool(CFSTR("Enabled"), YES);
    sbtMode3DS  = SBTReadBool(CFSTR("Mode3DS"), NO);
    sbtGradient = SBTReadBool(CFSTR("GradientEnabled"), NO);
    sbtAngle    = (CGFloat)SBTReadDouble(CFSTR("Angle"), 0.0);

    // Defaults here must match the "default" values in Root.plist.
    sbtColors1 = @[
        SBTReadColor(CFSTR("NormalColor1"),   @"#34C759"),
        SBTReadColor(CFSTR("LowPowerColor1"), @"#FFD60A"),
        SBTReadColor(CFSTR("LowColor1"),      @"#FF3B30"),
    ];
    sbtColors2 = @[
        SBTReadColor(CFSTR("NormalColor2"),   @"#00C7BE"),
        SBTReadColor(CFSTR("LowPowerColor2"), @"#FF9F0A"),
        SBTReadColor(CFSTR("LowColor2"),      @"#FF9500"),
    ];
}

// ---- Gradient helpers ----

// Converts an angle in degrees to CAGradientLayer start/end points (unit square).
// 0 = left to right, 90 = top to bottom.
static void SBTGradientPointsForAngle(CGFloat degrees, CGPoint *start, CGPoint *end) {
    CGFloat radians = degrees * (CGFloat)M_PI / 180.0f;
    CGFloat dx = cosf(radians), dy = sinf(radians);
    *start = CGPointMake(0.5f - dx * 0.5f, 0.5f - dy * 0.5f);
    *end   = CGPointMake(0.5f + dx * 0.5f, 0.5f + dy * 0.5f);
}

static id SBTRGB(int r, int g, int b) {
    return (id)[UIColor colorWithRed:r / 255.0f green:g / 255.0f blue:b / 255.0f alpha:1.0f].CGColor;
}

// The 3DS palettes. Stops are listed bottom -> top, like the CSS "0deg" gradients.
static NSArray *SBT3DSColors(SBTState state) {
    switch (state) {
        case SBTStateLowPower:  // Low Power Mode: green
            return @[SBTRGB(0, 230, 0), SBTRGB(0, 198, 0), SBTRGB(116, 253, 116), SBTRGB(0, 230, 0)];
        case SBTStateLow:       // charging / almost empty: orange
            return @[SBTRGB(255, 148, 76), SBTRGB(212, 108, 56), SBTRGB(255, 222, 116), SBTRGB(255, 148, 76)];
        case SBTStateNormal:    // normal: blue
        default:
            return @[SBTRGB(40, 190, 255), SBTRGB(30, 146, 198), SBTRGB(62, 255, 255), SBTRGB(40, 190, 255)];
    }
}

// Fills in the gradient for a state. Returns NO when this state should keep
// the stock look (empty/invalid hex).
static BOOL SBTBuildGradient(SBTState state, NSArray **colors, NSArray **locations,
                             CGPoint *start, CGPoint *end) {
    if (sbtMode3DS) {
        *colors = SBT3DSColors(state);
        *locations = @[@0.0, @0.5, @0.75, @1.0];
        *start = CGPointMake(0.5f, 1.0f);   // bottom
        *end   = CGPointMake(0.5f, 0.0f);   // top
        return YES;
    }

    id c1 = (state < (SBTState)sbtColors1.count) ? sbtColors1[state] : nil;
    if (![c1 isKindOfClass:[UIColor class]]) return NO;
    UIColor *first = c1;
    UIColor *second = first;
    if (sbtGradient) {
        id c2 = (state < (SBTState)sbtColors2.count) ? sbtColors2[state] : nil;
        if ([c2 isKindOfClass:[UIColor class]]) second = c2;
    }

    *colors = @[(id)first.CGColor, (id)second.CGColor];
    *locations = nil;
    if (sbtGradient) {
        SBTGradientPointsForAngle(sbtAngle, start, end);
    } else {
        *start = CGPointMake(0.0f, 0.5f);
        *end   = CGPointMake(1.0f, 0.5f);
    }
    return YES;
}

// ---- Private UIKit access helpers ----

static id SBTValueForKey(id obj, NSString *key) {
    @try { return [obj valueForKey:key]; } @catch (NSException *e) { return nil; }
}

static CALayer *SBTLayerFromObject(id o) {
    if ([o isKindOfClass:[UIView class]]) return ((UIView *)o).layer;
    if ([o isKindOfClass:[CALayer class]]) return o;
    return nil;
}

static id SBTIvarObject(id obj, const char *name) {
    Ivar iv = class_getInstanceVariable(object_getClass(obj), name);   // searches superclasses too
    if (!iv) return nil;
    const char *type = ivar_getTypeEncoding(iv);
    if (!type || type[0] != '@') return nil;
    return object_getIvar(obj, iv);
}

// _UIBatteryView exposes its layers through public-looking accessors
// (fillLayer, bodyLayer, boltLayer...). The on-screen class is actually the
// subclass STUIStatusBarBatteryView, which is why the ivars aren't listed on it.
static CALayer *SBTFindFillLayer(UIView *battery) {
    CALayer *l = SBTLayerFromObject(SBTValueForKey(battery, @"fillLayer"));
    if (l) return l;
    static const char *names[] = { "_fillLayer", "_fillShapeLayer", "_fillView", NULL };
    for (int i = 0; names[i]; i++) {
        l = SBTLayerFromObject(SBTIvarObject(battery, names[i]));
        if (l) return l;
    }
    return nil;
}

// Reads what THIS battery view is displaying (so e.g. a Bluetooth device battery
// uses its own level). Falls back to the device's own state if a key is missing.
static void SBTReadBatteryState(UIView *view, double *pct, BOOL *charging, BOOL *saver) {
    UIDevice *device = [UIDevice currentDevice];
    double p = device.batteryLevel;
    if (p < 0.0) p = 1.0;
    BOOL c = (device.batteryState == UIDeviceBatteryStateCharging ||
              device.batteryState == UIDeviceBatteryStateFull);
    BOOL s = [NSProcessInfo processInfo].lowPowerModeEnabled;

    id v = SBTValueForKey(view, @"chargePercent");        // 0.0 - 1.0 (confirmed by the dump)
    if ([v isKindOfClass:[NSNumber class]]) {
        p = [v doubleValue];
        if (p > 1.0) p /= 100.0;
    }
    v = SBTValueForKey(view, @"chargingState");
    if ([v isKindOfClass:[NSNumber class]]) c = ([v integerValue] != 0);
    v = SBTValueForKey(view, @"saverModeActive");
    if ([v isKindOfClass:[NSNumber class]]) s = [v boolValue];

    *pct = MAX(0.0, MIN(1.0, p));
    *charging = c;
    *saver = s;
}

static SBTState SBTResolveState(double pct, BOOL charging, BOOL saver) {
    if (saver) return SBTStateLowPower;
    if (pct <= 0.205) return SBTStateLow;                 // 20% or less
    if (sbtMode3DS && charging) return SBTStateLow;       // 3DS: orange while charging
    return SBTStateNormal;
}

static UIImage *SBTPlugImage(void) {
    static UIImage *image;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSData *data = [[NSData alloc] initWithBase64EncodedString:kSBTPlugBase64 options:0];
        if (data) image = [UIImage imageWithData:data];
    });
    return image;
}

// ---- Diagnostics: written once per battery view class, once it has a real size ----

static void SBTDumpLayerTree(CALayer *l, int depth, NSMutableString *out) {
    BOOL isShape = [l isKindOfClass:[CAShapeLayer class]];
    [out appendFormat:@"%*s%@ frame=%@ hidden=%d opacity=%.2f radius=%.1f masks=%d bg=%@ mask=%@ delegate=%@ %s\n",
        depth * 2, "", NSStringFromClass([l class]), NSStringFromCGRect(l.frame),
        (int)l.hidden, l.opacity, l.cornerRadius, (int)l.masksToBounds,
        l.backgroundColor ? @"yes" : @"no",
        l.mask ? NSStringFromClass([l.mask class]) : @"none",
        NSStringFromClass([l.delegate class]),
        (isShape && ((CAShapeLayer *)l).path) ? "path" : ""];
    for (CALayer *sub in l.sublayers) SBTDumpLayerTree(sub, depth + 1, out);
}

static void SBTDumpAccessor(UIView *battery, NSString *key, NSMutableString *out) {
    CALayer *l = SBTLayerFromObject(SBTValueForKey(battery, key));
    if (!l) { [out appendFormat:@"  %@ = nil\n", key]; return; }
    NSString *bg = l.backgroundColor ? [[UIColor colorWithCGColor:l.backgroundColor] description] : @"none";
    NSString *mask = l.mask ? NSStringFromClass([l.mask class]) : @"none";
    [out appendFormat:@"  %@ = %@ frame=%@ bounds=%@ hidden=%d opacity=%.2f radius=%.1f masks=%d bg=%@ mask=%@ sublayers=%lu\n",
        key, NSStringFromClass([l class]), NSStringFromCGRect(l.frame), NSStringFromCGRect(l.bounds),
        (int)l.hidden, l.opacity, l.cornerRadius, (int)l.masksToBounds, bg, mask,
        (unsigned long)l.sublayers.count];
}

static void SBTDumpBatteryView(UIView *battery) {
    static NSMutableSet *dumpedClasses;
    static NSMutableString *allDumps;
    if (battery.bounds.size.width < 5.0f || battery.bounds.size.height < 5.0f) return;   // wait for a real size

    NSString *cname = NSStringFromClass([battery class]);
    if (!dumpedClasses) { dumpedClasses = [NSMutableSet set]; allDumps = [NSMutableString string]; }
    if ([dumpedClasses containsObject:cname]) return;
    [dumpedClasses addObject:cname];

    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"==== %@ ====\nframe: %@\nchain:", cname, NSStringFromCGRect(battery.frame)];
    for (Class c = [battery class]; c; c = class_getSuperclass(c)) [out appendFormat:@" %@", NSStringFromClass(c)];
    [out appendString:@"\n\nivars (whole chain):\n"];
    for (Class c = [battery class]; c && c != [UIView class]; c = class_getSuperclass(c)) {
        unsigned int n = 0;
        Ivar *ivars = class_copyIvarList(c, &n);
        for (unsigned int i = 0; i < n; i++) {
            [out appendFormat:@"  %@.%s (%s)\n", NSStringFromClass(c), ivar_getName(ivars[i]), ivar_getTypeEncoding(ivars[i])];
        }
        free(ivars);
    }

    [out appendString:@"\nkvc values:\n"];
    for (NSString *key in @[@"chargePercent", @"chargingState", @"saverModeActive", @"showsPercentage",
                            @"showsInlineChargingIndicator", @"lowBatteryMode", @"iconSize", @"sizeCategory"]) {
        [out appendFormat:@"  %@ = %@\n", key, SBTValueForKey(battery, key) ?: @"<nil or no such key>"];
    }

    [out appendString:@"\nlayer accessors:\n"];
    for (NSString *key in @[@"fillLayer", @"percentFillLayer", @"percentFillShapeLayer", @"bodyLayer",
                            @"bodyShapeLayer", @"pinLayer", @"boltLayer", @"boltMaskLayer"]) {
        SBTDumpAccessor(battery, key, out);
    }

    [out appendString:@"\nlayer tree:\n"];
    SBTDumpLayerTree(battery.layer, 0, out);
    [out appendString:@"\nsubviews:\n"];
    for (UIView *sub in battery.subviews) {
        [out appendFormat:@"  %@ frame=%@ hidden=%d\n", NSStringFromClass([sub class]),
            NSStringFromCGRect(sub.frame), (int)sub.hidden];
    }
    [out appendString:@"\n"];

    [allDumps appendString:out];
    [allDumps writeToFile:SBT_VIEWDUMP_PATH atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

// ---- Painting ----
// The gradient is a sublayer INSIDE the native fill layer. That way the native
// code keeps owning the geometry (width = charge level, rounded corners, text
// cutout mask...) and we only paint on top of its background color.

static const void *SBTGradientKey = &SBTGradientKey;      // on the fill layer
static const void *SBTOrigMasksKey = &SBTOrigMasksKey;    // on the fill layer
static const void *SBTPlugKey = &SBTPlugKey;              // on the battery view
static const void *SBTHidBoltKey = &SBTHidBoltKey;        // on the battery view

static void SBTSetNativeBoltHidden(UIView *battery, BOOL hide) {
    BOOL wasHidden = [objc_getAssociatedObject(battery, SBTHidBoltKey) boolValue];
    if (!hide && !wasHidden) return;
    CALayer *bolt = SBTLayerFromObject(SBTValueForKey(battery, @"boltLayer"));
    if (bolt) bolt.hidden = hide;
    objc_setAssociatedObject(battery, SBTHidBoltKey, @(hide), OBJC_ASSOCIATION_RETAIN);
}

static void SBTRestoreNative(UIView *battery, CALayer *fill) {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (fill) {
        CAGradientLayer *grad = objc_getAssociatedObject(fill, SBTGradientKey);
        if (grad && !grad.hidden) {
            grad.hidden = YES;
            NSNumber *orig = objc_getAssociatedObject(fill, SBTOrigMasksKey);
            if (orig) fill.masksToBounds = orig.boolValue;
        }
    }
    CALayer *plug = objc_getAssociatedObject(battery, SBTPlugKey);
    if (plug) plug.hidden = YES;
    [CATransaction commit];
    SBTSetNativeBoltHidden(battery, NO);
}

static void SBTApplyOverlay(UIView *battery) {
    if (!battery) return;
    SBTDumpBatteryView(battery);

    CALayer *fill = SBTFindFillLayer(battery);

    NSArray *colors = nil, *locations = nil;
    CGPoint start = CGPointZero, end = CGPointZero;
    double pct = 1.0;
    BOOL charging = NO, saver = NO;
    BOOL active = (sbtEnabled && fill != nil);
    if (active) {
        SBTReadBatteryState(battery, &pct, &charging, &saver);
        SBTState state = SBTResolveState(pct, charging, saver);
        active = SBTBuildGradient(state, &colors, &locations, &start, &end);
    }
    if (active && (fill.bounds.size.width < 0.5f || fill.bounds.size.height < 0.5f)) active = NO;

    if (!active) {
        SBTRestoreNative(battery, fill);
        return;
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    CAGradientLayer *grad = objc_getAssociatedObject(fill, SBTGradientKey);
    if (!grad) {
        grad = [CAGradientLayer layer];
        objc_setAssociatedObject(fill, SBTGradientKey, grad, OBJC_ASSOCIATION_RETAIN);
        objc_setAssociatedObject(fill, SBTOrigMasksKey, @(fill.masksToBounds), OBJC_ASSOCIATION_RETAIN);
    }
    if (grad.superlayer != fill) {
        [grad removeFromSuperlayer];
        [fill addSublayer:grad];
    }
    fill.masksToBounds = YES;      // clip the gradient to the native rounded shape
    grad.hidden = NO;
    grad.opacity = 1.0f;
    grad.frame = fill.bounds;
    grad.colors = colors;
    grad.locations = locations;
    grad.startPoint = start;
    grad.endPoint = end;

    // 3DS charging plug icon, centered on the battery body.
    BOOL showPlug = sbtMode3DS && charging;
    CALayer *plug = objc_getAssociatedObject(battery, SBTPlugKey);
    if (showPlug) {
        if (!plug) {
            plug = [CALayer layer];
            plug.contents = (__bridge id)SBTPlugImage().CGImage;
            plug.contentsGravity = kCAGravityResizeAspect;
            plug.zPosition = 2000;
            objc_setAssociatedObject(battery, SBTPlugKey, plug, OBJC_ASSOCIATION_RETAIN);
        }
        if (plug.superlayer != battery.layer) {
            [plug removeFromSuperlayer];
            [battery.layer addSublayer:plug];
        }
        CGFloat w = 13.0f, h = w * 6.0f / 16.0f;
        CGPoint center = CGPointMake((battery.bounds.size.width - 2.0f) * 0.5f,
                                     battery.bounds.size.height * 0.5f);
        CALayer *body = SBTLayerFromObject(SBTValueForKey(battery, @"bodyLayer"));
        if (body && body.bounds.size.width > 0.5f) {
            center = [battery.layer convertPoint:CGPointMake(CGRectGetMidX(body.bounds), CGRectGetMidY(body.bounds))
                                       fromLayer:body];
        }
        plug.bounds = CGRectMake(0, 0, w, h);
        plug.position = center;
        plug.hidden = NO;
    } else if (plug) {
        plug.hidden = YES;
    }
    [CATransaction commit];
    SBTSetNativeBoltHidden(battery, showPlug);
}

// ---- Track every live battery view so the poll can re-apply on state changes ----
static NSHashTable<UIView *> *sbtTrackedViews;

static void SBTTrackView(UIView *view) {
    if (!sbtTrackedViews) sbtTrackedViews = [NSHashTable weakObjectsHashTable];
    [sbtTrackedViews addObject:view];
}

// ---- Hook target (private UIKit class; the status bar uses its subclass STUIStatusBarBatteryView) ----
@interface _UIBatteryView : UIView
@end

%hook _UIBatteryView

- (void)layoutSubviews {
    %orig;
    SBTTrackView(self);
    SBTApplyOverlay(self);
}

- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        SBTTrackView(self);
        SBTApplyOverlay(self);
    }
}

%end

static void SBTReloadCallback(CFNotificationCenterRef center, void *observer,
                              CFStringRef name, const void *object,
                              CFDictionaryRef userInfo) {
    SBTLoadPrefs();
    for (UIView *v in sbtTrackedViews) SBTApplyOverlay(v);
}

static void SBTPollTick(CFRunLoopTimerRef timer, void *info) {
    SBTLoadPrefs();
    for (UIView *v in sbtTrackedViews) SBTApplyOverlay(v);
}

%ctor {
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    SBTLoadPrefs();
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL, SBTReloadCallback, CFSTR(SBT_NOTIFY), NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);

    // Fallback path: re-check preferences and the battery state once a second,
    // in case the darwin notification never reaches SpringBoard.
    CFRunLoopTimerRef pollTimer = CFRunLoopTimerCreate(
        kCFAllocatorDefault, CFAbsoluteTimeGetCurrent(), 1.0, 0, 0,
        SBTPollTick, NULL);
    CFRunLoopAddTimer(CFRunLoopGetMain(), pollTimer, kCFRunLoopCommonModes);
}
