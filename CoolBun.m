// CoolBun - tiny performance HUD + heat saver for sideloaded apps
// Features: floating button, FPS / CPU / RAM / thermal / battery readout,
// FPS cap (Auto/60/45/30) and render-scale reduction (100/75/50/35%).
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <mach/mach.h>

static NSInteger gFPSCap = 0;      // 0 = leave app default
static CGFloat gScale = 1.0;       // render scale multiplier
static NSHashTable *gLinks;
static char kIgnore, kOrig;

#pragma mark - Helpers

static void CBApplyCap(CADisplayLink *l) {
    if (objc_getAssociatedObject(l, &kIgnore)) return;
    NSNumber *orig = objc_getAssociatedObject(l, &kOrig);
    if (!orig) {
        orig = @(l.preferredFramesPerSecond);
        objc_setAssociatedObject(l, &kOrig, orig, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    l.preferredFramesPerSecond = gFPSCap > 0 ? gFPSCap : orig.integerValue;
}

static float CBCPU(void) {
    thread_array_t th; mach_msg_type_number_t n;
    if (task_threads(mach_task_self(), &th, &n) != KERN_SUCCESS) return 0;
    float tot = 0;
    for (mach_msg_type_number_t i = 0; i < n; i++) {
        thread_info_data_t ti; mach_msg_type_number_t c = THREAD_INFO_MAX;
        if (thread_info(th[i], THREAD_BASIC_INFO, (thread_info_t)ti, &c) == KERN_SUCCESS) {
            thread_basic_info_t b = (thread_basic_info_t)ti;
            if (!(b->flags & TH_FLAGS_IDLE)) tot += b->cpu_usage / (float)TH_USAGE_SCALE * 100.0f;
        }
        mach_port_deallocate(mach_task_self(), th[i]);
    }
    vm_deallocate(mach_task_self(), (vm_address_t)th, n * sizeof(thread_t));
    return tot;
}

static float CBRAM(void) {
    task_vm_info_data_t v; mach_msg_type_number_t c = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&v, &c) != KERN_SUCCESS) return 0;
    return v.phys_footprint / 1048576.0f;
}

static NSString *CBThermal(void) {
    switch ([NSProcessInfo processInfo].thermalState) {
        case NSProcessInfoThermalStateNominal: return @"Cool";
        case NSProcessInfoThermalStateFair: return @"Warm";
        case NSProcessInfoThermalStateSerious: return @"HOT";
        case NSProcessInfoThermalStateCritical: return @"CRITICAL";
    }
    return @"?";
}

#pragma mark - CADisplayLink hook (FPS cap)

@interface CADisplayLink (CoolBun) @end
@implementation CADisplayLink (CoolBun)
- (void)cb_addToRunLoop:(NSRunLoop *)rl forMode:(NSRunLoopMode)mode {
    [gLinks addObject:self];
    CBApplyCap(self);
    [self cb_addToRunLoop:rl forMode:mode];
}
@end

#pragma mark - Overlay window

@interface CBWindow : UIWindow @end
@implementation CBWindow
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    UIView *v = [super hitTest:p withEvent:e];
    return (v == self || v == self.rootViewController.view) ? nil : v;
}
@end

@interface CBOverlay : NSObject
@property (nonatomic, strong) CBWindow *win;
@property (nonatomic, strong) UIButton *btn;
@property (nonatomic, strong) UIVisualEffectView *panel;
@property (nonatomic, strong) UILabel *info;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic, assign) NSInteger frames;
@property (nonatomic, assign) CFTimeInterval last;
@property (nonatomic, assign) NSInteger fps;
@property (nonatomic, strong) NSTimer *timer;
@end

@implementation CBOverlay

- (void)start {
    self.win = nil;
    if (@available(iOS 13.0, *)) {
        UIWindowScene *scene = nil;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
            if ([s isKindOfClass:UIWindowScene.class]) { scene = (UIWindowScene *)s; break; }
        if (scene) self.win = [[CBWindow alloc] initWithWindowScene:scene];
    }
    if (!self.win) self.win = [[CBWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.win.frame = UIScreen.mainScreen.bounds;
    self.win.windowLevel = UIWindowLevelAlert + 1000;
    self.win.backgroundColor = UIColor.clearColor;
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.clearColor;
    self.win.rootViewController = vc;
    self.win.hidden = NO;

    CGFloat h = UIScreen.mainScreen.bounds.size.height;
    self.btn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.btn.frame = CGRectMake(12, h - 140, 46, 46);
    self.btn.backgroundColor = [UIColor colorWithRed:1 green:0.6 blue:0.75 alpha:0.9];
    self.btn.layer.cornerRadius = 23;
    [self.btn setTitle:@"🥟" forState:UIControlStateNormal];
    [self.btn addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [self.btn addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]];
    [vc.view addSubview:self.btn];

    self.panel = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    self.panel.frame = CGRectMake(12, h - 140 - 250, 230, 240);
    self.panel.layer.cornerRadius = 14;
    self.panel.clipsToBounds = YES;
    self.panel.hidden = YES;
    [vc.view addSubview:self.panel];

    self.info = [[UILabel alloc] initWithFrame:CGRectMake(10, 6, 210, 110)];
    self.info.numberOfLines = 0;
    self.info.textColor = UIColor.whiteColor;
    if (@available(iOS 13.0, *))
        self.info.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightMedium];
    else
        self.info.font = [UIFont fontWithName:@"Menlo" size:13];
    [self.panel.contentView addSubview:self.info];

    [self addTitle:@"FPS cap" y:118];
    [self addSeg:@[@"Auto", @"60", @"45", @"30"] y:138 action:@selector(capChanged:)];
    [self addTitle:@"Render scale" y:176];
    [self addSeg:@[@"100%", @"75%", @"50%", @"35%"] y:196 action:@selector(scaleChanged:)];

    UIDevice.currentDevice.batteryMonitoringEnabled = YES;
    self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    objc_setAssociatedObject(self.link, &kIgnore, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
}

- (void)addTitle:(NSString *)t y:(CGFloat)y {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(10, y, 200, 18)];
    l.text = t; l.textColor = UIColor.lightGrayColor; l.font = [UIFont systemFontOfSize:11];
    [self.panel.contentView addSubview:l];
}

- (void)addSeg:(NSArray *)items y:(CGFloat)y action:(SEL)a {
    UISegmentedControl *s = [[UISegmentedControl alloc] initWithItems:items];
    s.frame = CGRectMake(10, y, 210, 30);
    s.selectedSegmentIndex = 0;
    [s addTarget:self action:a forControlEvents:UIControlEventValueChanged];
    [self.panel.contentView addSubview:s];
}

- (void)toggle { self.panel.hidden = !self.panel.hidden; }

- (void)drag:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.win];
    self.btn.center = CGPointMake(self.btn.center.x + t.x, self.btn.center.y + t.y);
    [g setTranslation:CGPointMake(0, 0) inView:self.win];
    CGRect f = self.panel.frame;
    f.origin = CGPointMake(MAX(4, MIN(self.btn.frame.origin.x, UIScreen.mainScreen.bounds.size.width - f.size.width - 4)),
                           MAX(30, self.btn.frame.origin.y - f.size.height - 8));
    self.panel.frame = f;
}

- (void)capChanged:(UISegmentedControl *)s {
    NSInteger caps[] = {0, 60, 45, 30};
    gFPSCap = caps[s.selectedSegmentIndex];
    for (CADisplayLink *l in gLinks.allObjects) CBApplyCap(l);
    [self applyScale];
}

- (void)scaleChanged:(UISegmentedControl *)s {
    CGFloat sc[] = {1.0, 0.75, 0.5, 0.35};
    gScale = sc[s.selectedSegmentIndex];
    [self applyScale];
}

- (void)tick:(CADisplayLink *)l {
    self.frames++;
    CFTimeInterval now = CACurrentMediaTime();
    if (self.last == 0) self.last = now;
    if (now - self.last >= 1.0) {
        self.fps = (NSInteger)round(self.frames / (now - self.last));
        self.frames = 0; self.last = now;
    }
}

- (void)refresh {
    float bat = UIDevice.currentDevice.batteryLevel * 100;
    self.info.text = [NSString stringWithFormat:
        @"UI FPS  %ld\nCPU     %.0f%%\nRAM     %.0f MB\nHeat    %@\nBattery %.0f%%",
        (long)self.fps, CBCPU(), CBRAM(), CBThermal(), bat < 0 ? 0 : bat];
    if (gScale < 1.0 || gFPSCap > 0) [self applyScale];   // catch newly created views
}

#pragma mark Render scale / MTKView cap

- (void)scan:(UIView *)v {
    CALayer *ly = v.layer;
    CGFloat native = UIScreen.mainScreen.nativeScale;
    if ([ly isKindOfClass:CAMetalLayer.class] || [ly isKindOfClass:NSClassFromString(@"CAEAGLLayer")]) {
        CGFloat want = MAX(1.0, native * gScale);
        if (fabs(v.contentScaleFactor - want) > 0.01) v.contentScaleFactor = want;
    }
    if ([v isKindOfClass:NSClassFromString(@"MTKView")]) {
        NSNumber *o = objc_getAssociatedObject(v, &kOrig);
        if (!o) { o = @([(id)v preferredFramesPerSecond]);
            objc_setAssociatedObject(v, &kOrig, o, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        [(id)v setPreferredFramesPerSecond:gFPSCap > 0 ? gFPSCap : o.integerValue];
    }
    for (UIView *s in v.subviews) [self scan:s];
}

- (void)applyScale {
    for (UIWindow *w in UIApplication.sharedApplication.windows)
        if (w != self.win) [self scan:w];
}
@end

#pragma mark - Entry

static CBOverlay *gOverlay;

__attribute__((constructor)) static void CBInit(void) {
    gLinks = [NSHashTable weakObjectsHashTable];
    Method a = class_getInstanceMethod(CADisplayLink.class, @selector(addToRunLoop:forMode:));
    Method b = class_getInstanceMethod(CADisplayLink.class, @selector(cb_addToRunLoop:forMode:));
    if (a && b) method_exchangeImplementations(a, b);

    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil queue:NSOperationQueue.mainQueue
                                                  usingBlock:^(NSNotification *n) {
        if (gOverlay) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            gOverlay = [CBOverlay new];
            [gOverlay start];
        });
    }];
}
