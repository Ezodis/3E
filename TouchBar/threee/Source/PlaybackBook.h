#import <Foundation/Foundation.h>
@interface PlaybackBook : NSObject
@property NSMutableDictionary<NSString *, NSMutableDictionary *> *sources;
@property NSUInteger sequence;
- (void)report:(NSString *)bundle state:(NSInteger)state;
- (void)commit:(NSString *)bundle playing:(BOOL)playing;
- (void)prefer:(NSString *)bundle;
- (NSInteger)state:(NSString *)bundle;
- (NSString *)target:(NSSet<NSString *> *)running fallback:(NSString *)fallback;
@end
@implementation PlaybackBook
- (instancetype)init { if ((self=[super init])) self.sources=[NSMutableDictionary dictionary]; return self; }
- (NSInteger)state:(NSString *)bundle { if (!bundle.length) return -1; return self.sources[bundle][@"state"] ? [self.sources[bundle][@"state"] integerValue] : -1; }
- (void)report:(NSString *)bundle state:(NSInteger)state {
    if (!bundle.length || state < 0) return;
    NSMutableDictionary *record=self.sources[bundle];
    if (!record) { record=[NSMutableDictionary dictionaryWithDictionary:@{@"state":@(-1),@"order":@0}]; self.sources[bundle]=record; }
    if ([record[@"settle"] timeIntervalSinceNow] > 0 && [record[@"state"] integerValue]!=state) return;
    NSInteger previous=[record[@"state"] integerValue];
    // order: when it started playing (newest playing source wins).
    // recent: last time it started or stopped, so once everything is paused
    // the most recently played source stays displayed.
    if (state==1 && previous!=1) { record[@"order"]=@(++self.sequence); record[@"recent"]=record[@"order"]; }
    else if (state!=1 && previous==1) record[@"recent"]=@(++self.sequence);
    record[@"state"]=@(state);
}
- (void)commit:(NSString *)bundle playing:(BOOL)playing {
    if (!bundle.length) return;
    [self.sources[bundle] removeObjectForKey:@"settle"];
    [self report:bundle state:playing ? 1 : 0];
    self.sources[bundle][@"settle"]=[NSDate dateWithTimeIntervalSinceNow:1];
}
- (void)prefer:(NSString *)bundle { if ([self state:bundle]==1) self.sources[bundle][@"order"]=self.sources[bundle][@"recent"]=@(++self.sequence); }
- (NSString *)target:(NSSet<NSString *> *)running fallback:(NSString *)fallback {
    // Forget exited sessions so a relaunched player gets a fresh playback order.
    for (NSString *bundle in self.sources.allKeys) if (![running containsObject:bundle]) [self.sources removeObjectForKey:bundle];
    NSString *target=nil; NSUInteger newest=0;
    for (NSString *bundle in self.sources) {
        NSDictionary *record=self.sources[bundle]; NSUInteger order=[record[@"order"] unsignedIntegerValue];
        if ([running containsObject:bundle] && [record[@"state"] integerValue]==1 && (!target || order>newest)) { target=bundle; newest=order; }
    }
    if (target) return target;
    // Nothing is playing: keep the source that played most recently, even if
    // paused, instead of whatever app was last focused or MediaRemote reports.
    for (NSString *bundle in self.sources) {
        NSUInteger recent=[self.sources[bundle][@"recent"] unsignedIntegerValue];
        if (recent>newest) { target=bundle; newest=recent; }
    }
    return target ?: fallback;
}
@end
