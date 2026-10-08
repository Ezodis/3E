#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Independent settings for one keyboard instance in the same Touch Bar.
@interface KeyboardConfiguration : NSObject <NSSecureCoding, NSCopying>
@property(nonatomic, copy) NSString *name;
@property(nonatomic) NSInteger midiChannel;
@property(nonatomic) NSInteger baseNote;
@property(nonatomic) NSInteger octaveCount;
@property(nonatomic) NSInteger transpose;
@property(nonatomic) NSInteger velocity;
+ (instancetype)defaultConfigurationWithName:(NSString *)name channel:(NSInteger)channel baseNote:(NSInteger)baseNote;
@end

/// Persistent collection used by the customization UI. It always supports
/// three keyboard slots, each with its own MIDI mapping.
@interface KeyboardConfigurationStore : NSObject
@property(nonatomic, copy) NSArray<KeyboardConfiguration *> *keyboards;
+ (instancetype)sharedStore;
- (void)restore;
- (void)save;
- (KeyboardConfiguration *)configurationAtIndex:(NSUInteger)index;
- (void)setConfiguration:(KeyboardConfiguration *)configuration atIndex:(NSUInteger)index;
@end

NS_ASSUME_NONNULL_END
