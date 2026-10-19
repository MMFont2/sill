// holdrig — TEST ONLY (Tests/holdrig/run.sh; never part of Sill, never built for a device). A driver
// library injected into the real Debug app on a private simulator (DYLD_INSERT_LIBRARIES through
// `simctl launch`): it presses a window thumbnail in the bar with synthesized touches
// (Tests/touchrig/TouchSynth: UITouch and UIEvent private setters, as KIF does) and stamps what UIKit
// does with them, from touch-down: the thumbnail's long press and tap, the strip's scroll, and the
// app's own console lines beside them (`hold:` and `lights:`, a Debug build of #113 and later), so the
// time from touch-down to the lights can be measured on any build, main's before #113 included
// (docs/thumbnail-hold-plan.md, Results).
//
// Environment (simctl launch's SIMCTL_CHILD_ prefix):
//   RIG_SCRIPT  scenarios, separated by ';': hold S (press the first thumbnail S seconds, then lift),
//               tap (the second thumbnail, 80 ms), swipe (the third thumbnail, 120 pt left over 0.25 s),
//               drift (the first, creeping 7.5 pt over 2.5 s), drag (the first: past the hold, then
//               150 pt right over 0.6 s), set S (Sill.thumbnailHold written as the Settings panel's
//               stepper writes it, with the strip on screen), wait S. Default "hold 3; tap; swipe; drift;
//               drag".
//   RIG_DELAY   seconds after launch before the first scenario (default 4: the harness's mock first).
//   RIG_ROUTE   enqueue: the touches go in through UIKit's own HID entry point (`_enqueueHIDEvent:`), so
//               UIKit makes them, hit-tests and routes them as a finger's; RIG_NORMALIZED=1 gives their
//               points as fractions of the screen. Otherwise they are made here and sent with
//               sendEvent:, as KIF does.
// It does nothing outside a simulator (no SIMULATOR_UDID) and prints "RIG done" at the end.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "TouchSynth.h"

static double t0 = 0;
static void say(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void say(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    printf("RIG %+8.3f %s\n", CACurrentMediaTime() - t0, line.UTF8String);
    fflush(stdout);
}

static NSString *stateName(UIGestureRecognizerState s) {
    switch (s) {
        case UIGestureRecognizerStatePossible: return @"possible";
        case UIGestureRecognizerStateBegan: return @"began";
        case UIGestureRecognizerStateChanged: return @"changed";
        case UIGestureRecognizerStateEnded: return @"ended";
        case UIGestureRecognizerStateCancelled: return @"cancelled";
        case UIGestureRecognizerStateFailed: return @"failed";
    }
    return @"?";
}

/// Logs each recognizer's state changes (not `changed`, which repeats) under a name.
@interface RigWatch : NSObject
@property (nonatomic, strong) NSMapTable<UIGestureRecognizer *, NSString *> *names;
@property (nonatomic, strong) NSMapTable<UIGestureRecognizer *, NSNumber *> *last;
- (void)watch:(UIGestureRecognizer *)g as:(NSString *)name;
@end

@implementation RigWatch
- (instancetype)init {
    if ((self = [super init])) {
        _names = [NSMapTable weakToStrongObjectsMapTable];
        _last = [NSMapTable weakToStrongObjectsMapTable];
    }
    return self;
}
- (void)watch:(UIGestureRecognizer *)g as:(NSString *)name {
    if ([self.names objectForKey:g]) return;
    [self.names setObject:name forKey:g];
    [self.last setObject:@(g.state) forKey:g];
    [g addObserver:self forKeyPath:@"state" options:NSKeyValueObservingOptionNew context:NULL];
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    UIGestureRecognizer *g = object;
    NSNumber *before = [self.last objectForKey:g];
    if (before && before.integerValue == g.state) return;
    [self.last setObject:@(g.state) forKey:g];
    if (g.state == UIGestureRecognizerStateChanged) return;
    say(@"[%@] %@", [self.names objectForKey:g], stateName(g.state));
}
@end

static RigWatch *watcher;
static TouchSynth *synth;

static UIWindow *keyWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) if (w.isKeyWindow) return w;
    }
    return nil;
}

/// The thumbnails' touch views: a view with a long press of 0.75 s or more (the trackpad's and the
/// stream's long presses are 0.45 s), left to right.
static NSArray<UIView *> *thumbnails(UIWindow *window) {
    NSMutableArray<UIView *> *found = [NSMutableArray array];
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:window];
    while (queue.count) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        for (UIGestureRecognizer *g in v.gestureRecognizers) {
            if ([g isKindOfClass:UILongPressGestureRecognizer.class] && ((UILongPressGestureRecognizer *)g).minimumPressDuration >= 0.75 && !v.hidden) {
                [found addObject:v];
                break;
            }
        }
        [queue addObjectsFromArray:v.subviews];
    }
    [found sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        CGFloat ax = [a convertPoint:CGPointZero toView:nil].x, bx = [b convertPoint:CGPointZero toView:nil].x;
        return ax < bx ? NSOrderedAscending : ax > bx ? NSOrderedDescending : NSOrderedSame;
    }];
    return found;
}

static UILongPressGestureRecognizer *holdOf(UIView *v) {
    for (UIGestureRecognizer *g in v.gestureRecognizers)
        if ([g isKindOfClass:UILongPressGestureRecognizer.class]) return (UILongPressGestureRecognizer *)g;
    return nil;
}

static UIScrollView *stripOf(UIView *v) {
    for (UIView *s = v.superview; s; s = s.superview) if ([s isKindOfClass:UIScrollView.class]) return (UIScrollView *)s;
    return nil;
}

static CGPoint centre(UIView *v) {
    return [v convertPoint:CGPointMake(CGRectGetMidX(v.bounds), CGRectGetMidY(v.bounds)) toView:nil];
}

static void watchAll(NSArray<UIView *> *thumbs) {
    [thumbs enumerateObjectsUsingBlock:^(UIView *v, NSUInteger i, BOOL *stop) {
        for (UIGestureRecognizer *g in v.gestureRecognizers) {
            NSString *kind = [g isKindOfClass:UILongPressGestureRecognizer.class] ? @"hold" : [g isKindOfClass:UITapGestureRecognizer.class] ? @"tap" : NSStringFromClass(g.class);
            [watcher watch:g as:[NSString stringWithFormat:@"thumbnail %lu %@", (unsigned long)i + 1, kind]];
        }
    }];
    UIScrollView *strip = stripOf(thumbs.firstObject);
    if (strip) [watcher watch:strip.panGestureRecognizer as:@"strip's scroll"];
}

/// Runs `steps` one after another on the main queue: each block returns the seconds to wait before
/// the next.
static void runSteps(NSMutableArray<double (^)(void)> *steps, void (^done)(void)) {
    if (steps.count == 0) { done(); return; }
    double (^step)(void) = steps.firstObject;
    [steps removeObjectAtIndex:0];
    double wait = step();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ runSteps(steps, done); });
}

static void addPress(NSMutableArray *steps, NSString *title, NSInteger index, double hold, CGFloat moveX, CGFloat moveY, double moveOver, double moveAfter, int moves) {
    __block CGPoint at = CGPointZero;
    __block UIView *pressed = nil;
    [steps addObject:^double{
        UIWindow *w = keyWindow();
        NSArray<UIView *> *thumbs = thumbnails(w);
        if ((NSInteger)thumbs.count <= index) { say(@"%@: no thumbnail %ld (%lu found)", title, (long)index + 1, (unsigned long)thumbs.count); return 0; }
        watchAll(thumbs);
        pressed = thumbs[index];
        at = centre(pressed);
        UIScrollView *strip = stripOf(pressed);
        t0 = CACurrentMediaTime();
        say(@"=== %@: thumbnail %ld of %lu at (%.0f, %.0f); its hold %.2f s (%@); the strip at x %.0f",
            title, (long)index + 1, (unsigned long)thumbs.count, at.x, at.y, holdOf(pressed).minimumPressDuration,
            NSStringFromClass(holdOf(pressed).class), strip.contentOffset.x);
        [synth beginAt:@[[NSValue valueWithCGPoint:at]]];
        say(@"touch-down sent");
        return moves > 0 ? moveAfter : hold;
    }];
    for (int k = 1; k <= moves; k++) {
        [steps addObject:^double{
            CGPoint p = CGPointMake(at.x + moveX * k / moves, at.y + moveY * k / moves);
            [synth moveTo:@[[NSValue valueWithCGPoint:p]]];
            if (k == 1) say(@"moving");
            if (k == moves) say(@"moved to (%.1f, %.1f)", p.x, p.y);
            return k == moves ? MAX(0, hold - moveAfter - moveOver) : moveOver / moves;
        }];
    }
    [steps addObject:^double{
        [synth endIndices:[NSIndexSet indexSetWithIndex:0]];
        say(@"lift sent");
        return 1.0;
    }];
    // What it left: where the strip is and where the pressed thumbnail is now. Whatever opened (the
    // lights) is then put away with a tap on the stream under the bar, which the lights' catcher
    // covers while they show (and which a mock session ignores otherwise).
    [steps addObject:^double{
        UIWindow *w = keyWindow();
        NSArray<UIView *> *thumbs = thumbnails(w);
        UIScrollView *strip = stripOf(thumbs.firstObject);
        NSUInteger now = pressed ? [thumbs indexOfObject:pressed] : NSNotFound;
        say(@"after: the strip at x %.0f; the thumbnail pressed is number %@ of %lu", strip.contentOffset.x,
            now == NSNotFound ? @"?" : [NSString stringWithFormat:@"%lu", (unsigned long)now + 1], (unsigned long)thumbs.count);
        CGPoint below = CGPointMake(at.x, at.y + 300);
        [synth beginAt:@[[NSValue valueWithCGPoint:below]]];
        return 0.08;
    }];
    [steps addObject:^double{
        [synth endIndices:[NSIndexSet indexSetWithIndex:0]];
        return 1.0;
    }];
}

static void start(void) {
    UIWindow *w = keyWindow();
    if (!w) { say(@"no key window yet"); dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ start(); }); return; }
    say(@"TouchSynth: %@", [TouchSynth selfCheck]);
    synth = [[TouchSynth alloc] initWithWindow:w];
    // RIG_ROUTE=enqueue: UIKit's own HID entry point makes the touches (RIG_NORMALIZED=1: as fractions of
    // the screen); otherwise the touches are made here and sent with sendEvent:, as KIF does.
    synth.viaEnqueue = [NSProcessInfo.processInfo.environment[@"RIG_ROUTE"] isEqualToString:@"enqueue"];
    synth.normalized = [NSProcessInfo.processInfo.environment[@"RIG_NORMALIZED"] isEqualToString:@"1"];
    say(@"route: %@%@", synth.viaEnqueue ? @"UIKit's HID entry point" : @"sendEvent: (KIF)", synth.normalized ? @", normalized" : @"");
    watcher = [RigWatch new];
    NSString *script = NSProcessInfo.processInfo.environment[@"RIG_SCRIPT"] ?: @"hold 3; tap; swipe; drift; drag";
    NSMutableArray<double (^)(void)> *steps = [NSMutableArray array];
    for (NSString *raw in [script componentsSeparatedByString:@";"]) {
        NSArray *parts = [[raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] componentsSeparatedByString:@" "];
        NSString *verb = parts.firstObject;
        double arg = parts.count > 1 ? [parts[1] doubleValue] : 0;
        if ([verb isEqualToString:@"hold"]) addPress(steps, [NSString stringWithFormat:@"hold %.1f s", arg ?: 3], 0, arg ?: 3, 0, 0, 0, 0, 0);
        else if ([verb isEqualToString:@"tap"]) addPress(steps, @"tap", 1, 0.08, 0, 0, 0, 0, 0);
        else if ([verb isEqualToString:@"swipe"]) addPress(steps, @"swipe", 2, 0.5, -120, 0, 0.25, 0.03, 15);
        else if ([verb isEqualToString:@"drift"]) addPress(steps, @"drift", 0, 2.5, 7.5, 0, 2.4, 0.05, 24);
        else if ([verb isEqualToString:@"drag"]) {
            double hold = 0;
            NSArray<UIView *> *thumbs = thumbnails(w);
            if (thumbs.count) hold = holdOf(thumbs.firstObject).minimumPressDuration;
            addPress(steps, @"drag", 0, hold + 0.4 + 0.6 + 0.3, 150, 0, 0.6, hold + 0.4, 20);
        } else if ([verb isEqualToString:@"set"]) {
            // The setting changed while the strip is on screen, as the Settings panel's stepper writes it.
            [steps addObject:^double{
                [NSUserDefaults.standardUserDefaults setDouble:arg forKey:@"Sill.thumbnailHold"];
                say(@"=== set Sill.thumbnailHold to %.1f s", arg);
                return 1.0;
            }];
        } else if ([verb isEqualToString:@"wait"]) [steps addObject:^double{ return arg; }];
        else if (verb.length) say(@"unknown step %@", raw);
    }
    runSteps(steps, ^{ say(@"RIG done"); printf("RIG done\n"); fflush(stdout); });
}

__attribute__((constructor)) static void holdrigLoad(void) {
    if (!getenv("SIMULATOR_UDID")) return;   // a simulator's processes only
    double delay = getenv("RIG_DELAY") ? atof(getenv("RIG_DELAY")) : 4;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        t0 = CACurrentMediaTime();
        start();
    });
}
