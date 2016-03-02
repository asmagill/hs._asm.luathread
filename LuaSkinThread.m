#import "LuaSkinThread.h"
#import "LuaSkinThread+Private.h"

#pragma mark - LuaSkinThread Class Implementation

@implementation LuaSkinThread

#pragma mark - LuaSkinThread public methods

+(id)thread {
    // if we're on the main thread, go ahead and act normally
    if ([NSThread isMainThread]) return [LuaSkin shared] ;

    // otherwise, we're storing the LuaSkin instance in the thread's dictionary
    HSASMLuaThread  *thisThread = (HSASMLuaThread *)[NSThread currentThread] ;

    LuaSkinThread *thisSkin ;
    if ([thisThread.dictionaryLock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:LOCK_TIMEOUT]]) {
        thisSkin   = [thisThread.threadDictionary objectForKey:@"_LuaSkin"] ;
        [thisThread.dictionaryLock unlock] ;
    } else {
        ERROR(@"[LuaSkinThread thread] unable to obtain dictionary lock") ;
        return nil ;
    }

    if (!thisSkin) {
        thisSkin = [[LuaSkinThread alloc] init] ;
    }
    return thisSkin ;
}

-(BOOL)setRef:(int)refNumber forLabel:(const char *)label inModule:(const char *)module {
    return [self setRef:refNumber forLabel:label inModule:module inThread:[NSThread currentThread]] ;
}

-(int)getRefForLabel:(const char *)label inModule:(const char *)module {
    return [self getRefForLabel:label inModule:module inThread:[NSThread currentThread]] ;
}

#pragma mark - LuaSkinThread internal methods

// Inject a new class method for use as a replacement for [LuaSkin shared] in a threaded instance.
// We do this, rather than swizzle shared itself because LuaSkin isn't the only component of a module
// that needs to be thread-aware/thread-safe, so we still want modules which haven't been explicitly
// looked at and tested to fail to load within the luathread... by leaving the shared class method
// alone, an exception is still thrown for untested modules and we don't potentially introduce new
// unintended side-effects in to the core LuaSkin and Hammerspoon modules
+(BOOL)inject {
    static dispatch_once_t onceToken ;
    static BOOL            injected = NO ;

    dispatch_once(&onceToken, ^{

        // since we're adding a class method, we need to get LuaSkin's metaclass... this is the
        // easiest way to do so...
        Class  oldClass = object_getClass([LuaSkin class]) ;
        Class  newClass = [LuaSkinThread class] ;
        SEL    selector = @selector(thread) ;
        Method method   = class_getClassMethod(newClass, selector) ;

        BOOL wasAdded = class_addMethod(oldClass,
                                        selector,
                                        method_getImplementation(method),
                                        method_getTypeEncoding(method)) ;
        if (wasAdded) {
            injected = YES ;
        } else {
            [[LuaSkin shared] logError:@"Unable to inject thread method into LuaSkin"] ;
        }
    });
    return injected ;
}

-(BOOL)setRef:(int)refNumber forLabel:(const char *)label inModule:(const char *)module inThread:(NSThread *)thread {
    BOOL result = NO ;
    if ([thread isKindOfClass:[HSASMLuaThread class]]) {
        HSASMLuaThread *luaThread  = (HSASMLuaThread *)thread ;
        NSString       *moduleName = [NSString stringWithFormat:@"%s", module] ;
        NSString       *labelName  = [NSString stringWithFormat:@"%s", label] ;

        if ([luaThread.dictionaryLock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:LOCK_TIMEOUT]]) {
            if (![[luaThread.threadDictionary objectForKey:@"_internalReferences"] objectForKey:moduleName]) {
                [[luaThread.threadDictionary objectForKey:@"_internalReferences"] setObject:[[NSMutableDictionary alloc] init]
                                                                                forKey:moduleName] ;
            }
            [[[luaThread.threadDictionary objectForKey:@"_internalReferences"] objectForKey:moduleName] setObject:@(refNumber)
                                                                                                     forKey:labelName] ;
            result = YES ;
            [luaThread.dictionaryLock unlock] ;
        } else {
            ERROR(@"[LuaSkinThread setRef:forLabel:inModule:] unable to obtain dictionary lock") ;
        }
    } else {
        ERROR(@"[LuaSkinThread setRef:forLabel:inModule:] thread is not an hs._asm.luathread") ;
    }
    return result ;
}

-(int)getRefForLabel:(const char *)label inModule:(const char *)module inThread:(NSThread *)thread {
    int result = LUA_REFNIL ;
    if ([thread isKindOfClass:[HSASMLuaThread class]]) {
        HSASMLuaThread *luaThread  = (HSASMLuaThread *)thread ;
        NSString       *moduleName = [NSString stringWithFormat:@"%s", module] ;
        NSString       *labelName  = [NSString stringWithFormat:@"%s", label] ;

        if ([luaThread.dictionaryLock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:LOCK_TIMEOUT]]) {
            NSNumber *holder = [[[luaThread.threadDictionary objectForKey:@"_internalReferences"]
                                                             objectForKey:moduleName]
                                                             objectForKey:labelName] ;
            result = holder ? [holder intValue] : LUA_NOREF ;
            [luaThread.dictionaryLock unlock] ;
        } else {
            ERROR(@"[LuaSkinThread getRefForLabel:inModule:] unable to obtain dictionary lock") ;
        }
    } else {
        ERROR(@"[LuaSkinThread getRefForLabel:inModule:] thread is not an hs._asm.luathread") ;
    }
    return result ;
}

#pragma mark - LuaSkinThread overrides to the LuaSkin class

- (id)init {
    self = [super init];
    if (self) {
        _threadForThisSkin = (HSASMLuaThread *)[NSThread currentThread] ;

        if ([_threadForThisSkin.dictionaryLock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:LOCK_TIMEOUT]]) {
            [_threadForThisSkin.threadDictionary setObject:self forKey:@"_LuaSkin"];
            [_threadForThisSkin.threadDictionary setObject:[[NSMutableDictionary alloc] init] forKey:@"_internalReferences"] ;
            [_threadForThisSkin.dictionaryLock unlock] ;
        } else {
            ERROR(@"[LuaSkinThread init] unable to obtain dictionary lock") ;
        }
    }
    return self;
}

- (void)destroyLuaState {
    NSLog(@"LuaSkinThread destroyLuaState");
    NSAssert((self.L != NULL), @"LuaSkinThread destroyLuaState called with no Lua environment", nil);
    if (self.L) {
        [super destroyLuaState] ;
        if ([_threadForThisSkin.dictionaryLock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:LOCK_TIMEOUT]]) {
            [_threadForThisSkin.threadDictionary removeObjectForKey:@"_LuaSkin"] ;
            [_threadForThisSkin.threadDictionary removeObjectForKey:@"_internalReferences"] ;
            [_threadForThisSkin.dictionaryLock unlock] ;
        } else {
            ERROR(@"[LuaSkinThread destroyLuaState] unable to obtain dictionary lock") ;
        }
    }
    self.L = NULL;
}

@end