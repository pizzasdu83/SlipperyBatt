// Slippery Batt - recolor the battery icon (solid color, gradient, 3DS mode)
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>

#define SBT_DOMAIN CFSTR("com.pizzasdu83.slipperybatt")
#define SBT_NOTIFY "com.pizzasdu83.slipperybatt/reload"
#define SBT_CLASSDUMP_PATH @"/var/mobile/Documents/SlipperyBatt-classdump.txt"
#define SBT_VIEWDUMP_PATH  @"/var/mobile/Documents/SlipperyBatt-viewdump.txt"

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
// the stock look (empty/invalid hex, tweak logic decides nothing to paint).
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

// ---- Battery state ----

// Reads what THIS battery view is displaying (so e.g. a Bluetooth device battery
// uses its own level). Falls back to the device's own state if the private
// properties aren't there.
static void SBTReadBatteryState(UIView *view, double *pct, BOOL *charging, BOOL *saver) {
    UIDevice *device = [UIDevice currentDevice];
    double p = device.batteryLevel;
    if (p < 0.0) p = 1.0;
    BOOL c = (device.batteryState == UIDeviceBatteryStateCharging ||
              device.batteryState == UIDeviceBatteryStateFull);
    BOOL s = [NSProcessInfo processInfo].lowPowerModeEnabled;

    @try {
        id v = [view valueForKey:@"chargePercent"];
        if ([v isKindOfClass:[NSNumber class]]) {
            p = [v doubleValue];
            if (p > 1.0) p /= 100.0;   // in case it's expressed 0-100
        }
    } @catch (NSException *e) {}
    @try {
        id v = [view valueForKey:@"chargingState"];
        if ([v isKindOfClass:[NSNumber class]]) c = ([v integerValue] != 0);
    } @catch (NSException *e) {}
    @try {
        id v = [view valueForKey:@"saverModeActive"];
        if ([v isKindOfClass:[NSNumber class]]) s = [v boolValue];
    } @catch (NSException *e) {}

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

// ---- Locating the native pieces of _UIBatteryView (private ivars, best effort) ----

static id SBTIvarObject(id obj, const char *name) {
    Ivar iv = class_getInstanceVariable(object_getClass(obj), name);
    if (!iv) return nil;
    const char *type = ivar_getTypeEncoding(iv);
    if (!type || type[0] != '@') return nil;
    return object_getIvar(obj, iv);
}

static CALayer *SBTLayerFromObject(id o) {
    if ([o isKindOfClass:[UIView class]]) return ((UIView *)o).layer;
    if ([o isKindOfClass:[CALayer class]]) return o;
    return nil;
}

static CALayer *SBTFindFillLayer(UIView *battery) {
    static const char *names[] = { "_fillLayer", "_fillShapeLayer", "_fillView",
                                   "_fillShapeView", "_batteryFillLayer", NULL };
    for (int i = 0; names[i]; i++) {
        CALayer *l = SBTLayerFromObject(SBTIvarObject(battery, names[i]));
        if (l) return l;
    }
    return nil;
}

static const void *SBTOverlayKey = &SBTOverlayKey;
static const void *SBTPlugKey = &SBTPlugKey;
static const void *SBTHidFillKey = &SBTHidFillKey;
static const void *SBTHidBoltKey = &SBTHidBoltKey;

// The stock charging bolt, hidden while our plug icon is shown.
static void SBTSetNativeBoltHidden(UIView *battery, BOOL hide) {
    BOOL wasHidden = [objc_getAssociatedObject(battery, SBTHidBoltKey) boolValue];
    if (!hide && !wasHidden) return;
    static const char *names[] = { "_boltImageView", "_chargingImageView", "_boltView",
                                   "_chargingBoltView", "_boltLayer", NULL };
    for (int i = 0; names[i]; i++) {
        id o = SBTIvarObject(battery, names[i]);
        if ([o isKindOfClass:[UIView class]]) ((UIView *)o).hidden = hide;
        else if ([o isKindOfClass:[CALayer class]]) ((CALayer *)o).hidden = hide;
    }
    objc_setAssociatedObject(battery, SBTHidBoltKey, @(hide), OBJC_ASSOCIATION_RETAIN);
}

// Used only when the native fill layer can't be found: a rough inner rect.
static CGRect SBTFallbackFillRect(UIView *battery, double pct) {
    CGFloat inset = 2.0f, pin = 2.0f;
    CGRect body = CGRectMake(0, 0, battery.bounds.size.width - pin, battery.bounds.size.height);
    CGRect inner = CGRectInset(body, inset, inset);
    inner.size.width = MAX(0.0, inner.size.width * (CGFloat)pct);
    return inner;
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

// ---- Diagnostics: written once so we can adapt to iOS 26's real layout ----

static void SBTDumpLayerTree(CALayer *l, int depth, NSMutableString *out) {
    BOOL isShape = [l isKindOfClass:[CAShapeLayer class]];
    [out appendFormat:@"%*s%@ frame=%@ hidden=%d radius=%.1f bg=%@ delegate=%@ %s\n",
        depth * 2, "", NSStringFromClass([l class]), NSStringFromCGRect(l.frame),
        (int)l.hidden, l.cornerRadius, l.backgroundColor ? @"yes" : @"no",
        NSStringFromClass([l.delegate class]),
        (isShape && ((CAShapeLayer *)l).path) ? "path" : ""];
    for (CALayer *sub in l.sublayers) SBTDumpLayerTree(sub, depth + 1, out);
}

static void SBTDumpBatteryViewOnce(UIView *battery) {
    static BOOL dumped = NO;
    if (dumped) return;
    dumped = YES;

    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"class: %@\nframe: %@\n\nivars:\n", NSStringFromClass([battery class]),
        NSStringFromCGRect(battery.frame)];
    unsigned int n = 0;
    Ivar *ivars = class_copyIvarList([battery class], &n);
    for (unsigned int i = 0; i < n; i++) {
        [out appendFormat:@"  %s (%s)\n", ivar_getName(ivars[i]), ivar_getTypeEncoding(ivars[i])];
    }
    free(ivars);

    [out appendString:@"\nkvc values:\n"];
    for (NSString *key in @[@"chargePercent", @"chargingState", @"saverModeActive"]) {
        id v = nil;
        @try { v = [battery valueForKey:key]; } @catch (NSException *e) { v = @"<no such key>"; }
        [out appendFormat:@"  %@ = %@\n", key, v];
    }

    [out appendString:@"\nlayer tree:\n"];
    SBTDumpLayerTree(battery.layer, 0, out);

    [out appendString:@"\nsubviews:\n"];
    for (UIView *sub in battery.subviews) {
        [out appendFormat:@"  %@ frame=%@\n", NSStringFromClass([sub class]), NSStringFromCGRect(sub.frame)];
    }
    [out writeToFile:SBT_VIEWDUMP_PATH atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static void SBTDumpClasses(void) {
    NSMutableString *out = [NSMutableString string];
    int count = objc_getClassList(NULL, 0);
    Class *classes = (Class *)malloc(sizeof(Class) * (unsigned long)count);
    count = objc_getClassList(classes, count);
    for (int i = 0; i < count; i++) {
        NSString *name = NSStringFromClass(classes[i]);
        if ([name rangeOfString:@"Battery" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [out appendFormat:@"%@\n", name];
        }
    }
    free(classes);

    Class cls = objc_getClass("_UIBatteryView");
    if (cls) {
        unsigned int n = 0;
        Method *methods = class_copyMethodList(cls, &n);
        [out appendString:@"\n_UIBatteryView methods:\n"];
        for (unsigned int i = 0; i < n; i++) {
            [out appendFormat:@"  %@\n", NSStringFromSelector(method_getName(methods[i]))];
        }
        free(methods);
    } else {
        [out appendString:@"\n_UIBatteryView NOT FOUND\n"];
    }
    [out writeToFile:SBT_CLASSDUMP_PATH atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

// ---- Painting ----

static void SBTRestoreNative(UIView *battery, CALayer *overlay, CALayer *fill) {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (overlay) overlay.hidden = YES;
    CALayer *plug = objc_getAssociatedObject(battery, SBTPlugKey);
    if (plug) plug.hidden = YES;
    if ([objc_getAssociatedObject(battery, SBTHidFillKey) boolValue]) {
        if (fill) fill.hidden = NO;
        objc_setAssociatedObject(battery, SBTHidFillKey, @NO, OBJC_ASSOCIATION_RETAIN);
    }
    [CATransaction commit];
    SBTSetNativeBoltHidden(battery, NO);
}

static void SBTApplyOverlay(UIView *battery) {
    if (!battery) return;
    SBTDumpBatteryViewOnce(battery);

    CAGradientLayer *overlay = objc_getAssociatedObject(battery, SBTOverlayKey);
    CALayer *fill = SBTFindFillLayer(battery);

    NSArray *colors = nil, *locations = nil;
    CGPoint start = CGPointZero, end = CGPointZero;
    double pct = 1.0;
    BOOL charging = NO, saver = NO;
    BOOL active = sbtEnabled;
    if (active) {
        SBTReadBatteryState(battery, &pct, &charging, &saver);
        SBTState state = SBTResolveState(pct, charging, saver);
        active = SBTBuildGradient(state, &colors, &locations, &start, &end);
    }

    CGRect rect = CGRectZero;
    if (active) {
        rect = fill ? fill.frame : SBTFallbackFillRect(battery, pct);
        if (rect.size.width < 0.5f || rect.size.height < 0.5f) active = NO;
    }

    if (!active) {
        SBTRestoreNative(battery, overlay, fill);
        return;
    }

    CALayer *parent = fill ? fill.superlayer : battery.layer;
    if (!parent) return;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    if (!overlay) {
        overlay = [CAGradientLayer layer];
        objc_setAssociatedObject(battery, SBTOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN);
    }
    if (overlay.superlayer != parent) {
        [overlay removeFromSuperlayer];
        if (fill) {
            // Right above the native fill, so the percentage text stays on top.
            [parent insertSublayer:overlay above:fill];
        } else {
            overlay.zPosition = 1000;
            [parent addSublayer:overlay];
        }
    }

    overlay.hidden = NO;
    overlay.opacity = 1.0f;
    overlay.frame = rect;
    overlay.colors = colors;
    overlay.locations = locations;
    overlay.startPoint = start;
    overlay.endPoint = end;

    // Same silhouette as the native fill.
    if ([fill isKindOfClass:[CAShapeLayer class]] && ((CAShapeLayer *)fill).path) {
        CAShapeLayer *mask = [CAShapeLayer layer];
        mask.frame = overlay.bounds;
        mask.path = ((CAShapeLayer *)fill).path;
        mask.fillColor = [UIColor blackColor].CGColor;
        overlay.mask = mask;
        overlay.cornerRadius = 0.0f;
        overlay.masksToBounds = NO;
    } else {
        overlay.mask = nil;
        overlay.cornerRadius = (fill && fill.cornerRadius > 0.0f)
            ? fill.cornerRadius : MIN(rect.size.height * 0.25f, 3.0f);
        overlay.masksToBounds = YES;
    }

    // Hide the native fill (only if we found it).
    if (fill) {
        fill.hidden = YES;
        objc_setAssociatedObject(battery, SBTHidFillKey, @YES, OBJC_ASSOCIATION_RETAIN);
    }

    // 3DS charging plug icon.
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
        if (plug.superlayer != parent) {
            [plug removeFromSuperlayer];
            [parent addSublayer:plug];
        }
        CGFloat w = 13.0f, h = w * 6.0f / 16.0f;
        CGPoint center = CGPointMake((battery.bounds.size.width - 2.0f) * 0.5f,
                                     battery.bounds.size.height * 0.5f);
        plug.bounds = CGRectMake(0, 0, w, h);
        plug.position = [battery.layer convertPoint:center toLayer:parent];
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

// ---- Hook target (private UIKit class) ----
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
    SBTDumpClasses();
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
