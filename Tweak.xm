#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>

#define SBT_DOMAIN CFSTR("com.pizzasdu83.slipperybatt")
#define SBT_NOTIFY "com.pizzasdu83.slipperybatt/reload"
#define SBT_VIEWDUMP_PATH @"/var/mobile/Documents/SlipperyBatt-viewdump.txt"

static NSString *const kSBTPlugBase64 =
    @"iVBORw0KGgoAAAANSUhEUgAAABAAAAAGCAYAAADKfB7nAAAAJklEQVR42mNkwAT/GfADRlwcQhqx6mPEoYBow5gYKAQ08QJJgQgAQFYFB+Ym9QEAAAAASUVORK5CYII=";

typedef NS_ENUM(NSInteger, SBTState) {
    SBTStateNormal = 0,
    SBTStateLowPower = 1,
    SBTStateLow = 2,
};

static BOOL sbtEnabled = YES;
static BOOL sbtMode3DS = NO;
static BOOL sbtGradient = NO;
static BOOL sbtShowPercentage = NO;
static BOOL sbtFlip = NO;
static CGFloat sbtAngle = 0.0f;
static CGFloat sbtPercentX = 300.0f;
static CGFloat sbtPercentY = 20.0f;

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
    sbtShowPercentage = SBTReadBool(CFSTR("ShowPercentage"), NO);
    sbtFlip     = SBTReadBool(CFSTR("FlipHorizontal"), NO);
    sbtAngle    = (CGFloat)SBTReadDouble(CFSTR("Angle"), 0.0);
    sbtPercentX = (CGFloat)SBTReadDouble(CFSTR("PercentPosX"), 300.0);
    sbtPercentY = (CGFloat)SBTReadDouble(CFSTR("PercentPosY"), 20.0);

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

static void SBTGradientPointsForAngle(CGFloat degrees, CGPoint *start, CGPoint *end) {
    CGFloat radians = degrees * (CGFloat)M_PI / 180.0f;
    CGFloat dx = cosf(radians), dy = sinf(radians);
    *start = CGPointMake(0.5f - dx * 0.5f, 0.5f - dy * 0.5f);
    *end   = CGPointMake(0.5f + dx * 0.5f, 0.5f + dy * 0.5f);
}

static id SBTRGB(int r, int g, int b) {
    return (id)[UIColor colorWithRed:r / 255.0f green:g / 255.0f blue:b / 255.0f alpha:1.0f].CGColor;
}

static NSArray *SBT3DSColors(SBTState state) {
    switch (state) {
        case SBTStateLowPower:
            return @[SBTRGB(0, 230, 0), SBTRGB(0, 198, 0), SBTRGB(116, 253, 116), SBTRGB(0, 230, 0)];
        case SBTStateLow:
            return @[SBTRGB(255, 148, 76), SBTRGB(212, 108, 56), SBTRGB(255, 222, 116), SBTRGB(255, 148, 76)];
        case SBTStateNormal:
        default:
            return @[SBTRGB(40, 190, 255), SBTRGB(30, 146, 198), SBTRGB(62, 255, 255), SBTRGB(40, 190, 255)];
    }
}

static BOOL SBTBuildGradient(SBTState state, NSArray **colors, NSArray **locations,
                             CGPoint *start, CGPoint *end) {
    if (sbtMode3DS) {
        *colors = SBT3DSColors(state);
        *locations = @[@0.0, @0.5, @0.75, @1.0];
        *start = CGPointMake(0.5f, 1.0f);
        *end   = CGPointMake(0.5f, 0.0f);
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

static id SBTValueForKey(id obj, NSString *key) {
    @try { return [obj valueForKey:key]; } @catch (NSException *e) { return nil; }
}

static CALayer *SBTLayerFromObject(id o) {
    if ([o isKindOfClass:[UIView class]]) return ((UIView *)o).layer;
    if ([o isKindOfClass:[CALayer class]]) return o;
    return nil;
}

static id SBTIvarObject(id obj, const char *name) {
    Ivar iv = class_getInstanceVariable(object_getClass(obj), name);
    if (!iv) return nil;
    const char *type = ivar_getTypeEncoding(iv);
    if (!type || type[0] != '@') return nil;
    return object_getIvar(obj, iv);
}

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

static void SBTReadBatteryState(UIView *view, double *pct, BOOL *charging, BOOL *saver) {
    UIDevice *device = [UIDevice currentDevice];
    double p = device.batteryLevel;
    if (p < 0.0) p = 1.0;
    BOOL c = (device.batteryState == UIDeviceBatteryStateCharging ||
              device.batteryState == UIDeviceBatteryStateFull);
    BOOL s = [NSProcessInfo processInfo].lowPowerModeEnabled;

    id v = SBTValueForKey(view, @"chargePercent");
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
    if (sbtMode3DS && charging && pct > 0.90) return SBTStateLowPower;
    if (pct <= 0.205) return SBTStateLow;
    if (sbtMode3DS && charging) return SBTStateLow;
    return SBTStateNormal;
}

static UIImage *SBTPlugImage(BOOL white) {
    static UIImage *blackImage, *whiteImage;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSData *data = [[NSData alloc] initWithBase64EncodedString:kSBTPlugBase64 options:0];
        if (!data) return;
        blackImage = [UIImage imageWithData:data scale:1.0];
        CGRect rect = CGRectMake(0, 0, blackImage.size.width, blackImage.size.height);
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
        format.scale = 1.0;
        format.opaque = NO;
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:rect.size format:format];
        whiteImage = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            [blackImage drawInRect:rect];
            CGContextSetBlendMode(ctx.CGContext, kCGBlendModeSourceIn);
            CGContextSetFillColorWithColor(ctx.CGContext, [UIColor whiteColor].CGColor);
            CGContextFillRect(ctx.CGContext, rect);
        }];
    });
    return white ? whiteImage : blackImage;
}

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
    if (battery.bounds.size.width < 5.0f || battery.bounds.size.height < 5.0f) return;

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

static const void *SBTGradientKey = &SBTGradientKey;
static const void *SBTOrigMasksKey = &SBTOrigMasksKey;
static const void *SBTPlugKey = &SBTPlugKey;
static const void *SBTHidBoltKey = &SBTHidBoltKey;

static void SBTSetNativeBoltHidden(UIView *battery, BOOL hide) {
    BOOL wasHidden = [objc_getAssociatedObject(battery, SBTHidBoltKey) boolValue];
    if (!hide && !wasHidden) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CALayer *bolt = SBTLayerFromObject(SBTValueForKey(battery, @"boltLayer"));
    if (bolt) bolt.hidden = hide;
    if (hide) {
        CALayer *fill = SBTFindFillLayer(battery);
        if (fill) fill.mask = nil;
    }
    [CATransaction commit];
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

static const void *SBTPlugDarkKey = &SBTPlugDarkKey;

@interface SBTPercentWindow : UIWindow
@end
@implementation SBTPercentWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event { return nil; }
@end

static SBTPercentWindow *sbtPercentWindow;
static UILabel *sbtPercentLabel;

static UIWindowScene *SBTActiveWindowScene(void) {
    UIWindowScene *fallback = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        if (scene.activationState == UISceneActivationStateForegroundActive) return ws;
        if (!fallback) fallback = ws;
    }
    return fallback;
}

static void SBTEnsurePercentWindow(void) {
    if (sbtPercentWindow) return;
    UIScreen *screen = [UIScreen mainScreen];
    sbtPercentWindow = [[SBTPercentWindow alloc] initWithFrame:screen.bounds];
    sbtPercentWindow.screen = screen;
    sbtPercentWindow.windowLevel = 2147483000.0;
    sbtPercentWindow.userInteractionEnabled = NO;
    sbtPercentWindow.backgroundColor = [UIColor clearColor];
    sbtPercentWindow.hidden = YES;
    UIWindowScene *scene = SBTActiveWindowScene();
    if (scene) sbtPercentWindow.windowScene = scene;

    sbtPercentLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    sbtPercentLabel.font = [UIFont systemFontOfSize:15.0f weight:UIFontWeightSemibold];
    sbtPercentLabel.textColor = [UIColor whiteColor];
    sbtPercentLabel.layer.shadowColor = [UIColor blackColor].CGColor;
    sbtPercentLabel.layer.shadowOpacity = 0.55f;
    sbtPercentLabel.layer.shadowRadius = 2.0f;
    sbtPercentLabel.layer.shadowOffset = CGSizeMake(0, 0.5f);
    [sbtPercentWindow addSubview:sbtPercentLabel];
}

static void SBTUpdateFloatingPercent(void) {
    BOOL want = sbtEnabled && sbtShowPercentage;
    if (!want) {
        if (sbtPercentWindow) sbtPercentWindow.hidden = YES;
        return;
    }
    SBTEnsurePercentWindow();
    if (!sbtPercentWindow.windowScene) {
        UIWindowScene *scene = SBTActiveWindowScene();
        if (scene) sbtPercentWindow.windowScene = scene;
        else { sbtPercentWindow.hidden = YES; return; }
    }

    double pct = [UIDevice currentDevice].batteryLevel;
    if (pct < 0.0) pct = 1.0;
    sbtPercentLabel.text = [NSString stringWithFormat:@"%d%%", (int)lround(pct * 100.0)];
    [sbtPercentLabel sizeToFit];

    CGRect screen = [UIScreen mainScreen].bounds;
    CGPoint center = CGPointMake(sbtPercentX, sbtPercentY);
    CGFloat halfW = sbtPercentLabel.bounds.size.width * 0.5f + 2.0f;
    CGFloat halfH = sbtPercentLabel.bounds.size.height * 0.5f + 2.0f;
    center.x = MAX(halfW, MIN(screen.size.width - halfW, center.x));
    center.y = MAX(halfH, MIN(screen.size.height - halfH, center.y));
    sbtPercentLabel.center = center;
    sbtPercentWindow.hidden = NO;
}

static CATransform3D SBTFlipTransform(void) {
    return (sbtEnabled && sbtFlip) ? CATransform3DMakeScale(-1.0, 1.0, 1.0) : CATransform3DIdentity;
}

static void SBTApplyFlip(UIView *battery) {
    CATransform3D t = SBTFlipTransform();
    if (!CATransform3DEqualToTransform(battery.layer.transform, t)) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        battery.layer.transform = t;
        [CATransaction commit];
    }
}

static void SBTApplyOverlay(UIView *battery) {
    if (!battery) return;
    SBTDumpBatteryView(battery);

    CALayer *fill = SBTFindFillLayer(battery);

    NSArray *colors = nil, *locations = nil;
    CGPoint start = CGPointZero, end = CGPointZero;
    double pct = 1.0;
    BOOL charging = NO, saver = NO;
    if (sbtEnabled) SBTReadBatteryState(battery, &pct, &charging, &saver);

    SBTUpdateFloatingPercent();
    SBTApplyFlip(battery);

    BOOL active = (sbtEnabled && fill != nil);
    if (active) {
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
    fill.masksToBounds = YES;
    grad.hidden = NO;
    grad.opacity = 1.0f;
    grad.frame = fill.bounds;
    grad.colors = colors;
    grad.locations = locations;
    grad.startPoint = start;
    grad.endPoint = end;

    BOOL showPlug = sbtMode3DS && charging;
    CALayer *plug = objc_getAssociatedObject(battery, SBTPlugKey);
    if (showPlug) {
        if (!plug) {
            plug = [CALayer layer];
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

        BOOL dark = ([UIScreen mainScreen].traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);
        NSNumber *lastDark = objc_getAssociatedObject(plug, SBTPlugDarkKey);
        if (!lastDark || lastDark.boolValue != dark) {
            plug.contents = (__bridge id)SBTPlugImage(dark).CGImage;
            objc_setAssociatedObject(plug, SBTPlugDarkKey, @(dark), OBJC_ASSOCIATION_RETAIN);
        }
        plug.bounds = CGRectMake(0, 0, w, h);
        plug.position = center;
        plug.transform = SBTFlipTransform();
        plug.hidden = NO;
        if (![plug animationForKey:@"sbtBlink"]) {
            CAKeyframeAnimation *blink = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
            blink.values = @[@1.0, @1.0, @0.0, @0.0];
            blink.keyTimes = @[@0.0, @0.5, @0.5, @1.0];
            blink.calculationMode = kCAAnimationDiscrete;
            blink.duration = 2.0;
            blink.repeatCount = HUGE_VALF;
            blink.removedOnCompletion = NO;
            [plug addAnimation:blink forKey:@"sbtBlink"];
        }
    } else if (plug) {
        [plug removeAnimationForKey:@"sbtBlink"];
        plug.opacity = 1.0f;
        plug.hidden = YES;
    }
    [CATransaction commit];
    SBTSetNativeBoltHidden(battery, showPlug);
}

static NSHashTable<UIView *> *sbtTrackedViews;

static void SBTTrackView(UIView *view) {
    if (!sbtTrackedViews) sbtTrackedViews = [NSHashTable weakObjectsHashTable];
    [sbtTrackedViews addObject:view];
}

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

    CFRunLoopTimerRef pollTimer = CFRunLoopTimerCreate(
        kCFAllocatorDefault, CFAbsoluteTimeGetCurrent(), 1.0, 0, 0,
        SBTPollTick, NULL);
    CFRunLoopAddTimer(CFRunLoopGetMain(), pollTimer, kCFRunLoopCommonModes);
}
