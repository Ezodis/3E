#import "KeyboardConfiguration.h"

static NSString *const Strip3KeyboardDefaultsKey = @"Strip3KeyboardConfigurations";

@implementation KeyboardConfiguration
+ (BOOL)supportsSecureCoding { return YES; }
- (instancetype)init { if((self=[super init])) { _name=@"Keyboard"; _midiChannel=1; _baseNote=60; _octaveCount=2; _transpose=0; _velocity=100; } return self; }
+ (instancetype)defaultConfigurationWithName:(NSString *)name channel:(NSInteger)channel baseNote:(NSInteger)baseNote {
    KeyboardConfiguration *configuration=[self new]; configuration.name=name; configuration.midiChannel=MAX(1,MIN(16,channel)); configuration.baseNote=baseNote; return configuration;
}
- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.name forKey:@"name"]; [coder encodeInteger:self.midiChannel forKey:@"channel"]; [coder encodeInteger:self.baseNote forKey:@"baseNote"]; [coder encodeInteger:self.octaveCount forKey:@"octaves"]; [coder encodeInteger:self.transpose forKey:@"transpose"]; [coder encodeInteger:self.velocity forKey:@"velocity"];
}
- (instancetype)initWithCoder:(NSCoder *)coder {
    if((self=[self init])) { _name=[coder decodeObjectOfClass:NSString.class forKey:@"name"] ?: @"Keyboard"; _midiChannel=[coder decodeIntegerForKey:@"channel"]; _baseNote=[coder decodeIntegerForKey:@"baseNote"]; _octaveCount=[coder decodeIntegerForKey:@"octaves"]; _transpose=[coder decodeIntegerForKey:@"transpose"]; _velocity=[coder decodeIntegerForKey:@"velocity"]; }
    return self;
}
- (id)copyWithZone:(NSZone *)zone { KeyboardConfiguration *copy=[KeyboardConfiguration new]; copy.name=self.name; copy.midiChannel=self.midiChannel; copy.baseNote=self.baseNote; copy.octaveCount=self.octaveCount; copy.transpose=self.transpose; copy.velocity=self.velocity; return copy; }
@end

@implementation KeyboardConfigurationStore
+ (instancetype)sharedStore { static KeyboardConfigurationStore *store; static dispatch_once_t once; dispatch_once(&once,^{ store=[self new]; [store restore]; }); return store; }
- (instancetype)init { if((self=[super init])) _keyboards=@[]; return self; }
- (void)restore {
    NSData *data=[[NSUserDefaults standardUserDefaults] dataForKey:Strip3KeyboardDefaultsKey];
    NSArray *saved=data ? [NSKeyedUnarchiver unarchivedObjectOfClasses:[NSSet setWithObjects:NSArray.class,KeyboardConfiguration.class,NSString.class,nil] fromData:data error:nil] : nil;
    NSMutableArray *result=[NSMutableArray array];
    NSArray *defaults=@[
        [KeyboardConfiguration defaultConfigurationWithName:@"Keyboard 1" channel:1 baseNote:60],
        [KeyboardConfiguration defaultConfigurationWithName:@"Keyboard 2" channel:2 baseNote:48],
        [KeyboardConfiguration defaultConfigurationWithName:@"Keyboard 3" channel:3 baseNote:72]
    ];
    for(NSUInteger index=0;index<3;index++) [result addObject:index<saved.count ? [saved[index] copy] : defaults[index]];
    self.keyboards=result;
}
- (void)save { NSData *data=[NSKeyedArchiver archivedDataWithRootObject:self.keyboards requiringSecureCoding:YES error:nil]; if(data) [[NSUserDefaults standardUserDefaults] setObject:data forKey:Strip3KeyboardDefaultsKey]; }
- (KeyboardConfiguration *)configurationAtIndex:(NSUInteger)index { return index<self.keyboards.count ? self.keyboards[index] : nil; }
- (void)setConfiguration:(KeyboardConfiguration *)configuration atIndex:(NSUInteger)index { if(!configuration || index>=3) return; NSMutableArray *items=[self.keyboards mutableCopy]; while(items.count<3) [items addObject:[KeyboardConfiguration new]]; items[index]=[configuration copy]; self.keyboards=items; [self save]; }
@end
