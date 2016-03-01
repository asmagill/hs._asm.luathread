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
        if (self.L == NULL) [self createLuaState] ;
        _registeredNSHelperFunctions               = [[NSMutableDictionary alloc] init] ;
        _registeredNSHelperLocations               = [[NSMutableDictionary alloc] init] ;
        _registeredLuaObjectHelperFunctions        = [[NSMutableDictionary alloc] init] ;
        _registeredLuaObjectHelperLocations        = [[NSMutableDictionary alloc] init] ;
        _registeredLuaObjectHelperUserdataMappings = [[NSMutableDictionary alloc] init] ;

        _threadForThisSkin                         = (HSASMLuaThread *)[NSThread currentThread] ;

        if ([_threadForThisSkin.dictionaryLock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:LOCK_TIMEOUT]]) {
            [_threadForThisSkin.threadDictionary setObject:self                               forKey:@"_LuaSkin"];
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
        lua_close(self.L);
        [_registeredNSHelperFunctions removeAllObjects] ;
        [_registeredNSHelperLocations removeAllObjects] ;
        [_registeredLuaObjectHelperFunctions removeAllObjects] ;
        [_registeredLuaObjectHelperLocations removeAllObjects] ;
        [_registeredLuaObjectHelperUserdataMappings removeAllObjects];

        HSASMLuaThread  *thisThread = (HSASMLuaThread *)[NSThread currentThread] ;
        if ([thisThread.dictionaryLock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:LOCK_TIMEOUT]]) {
            [thisThread.threadDictionary removeObjectForKey:@"_LuaSkin"] ;
            [thisThread.threadDictionary removeObjectForKey:@"_internalReferences"] ;
            [thisThread.dictionaryLock unlock] ;
        } else {
            ERROR(@"[LuaSkinThread destroyLuaState] unable to obtain dictionary lock") ;
        }
    }
    self.L = NULL;
}

- (BOOL)registerPushNSHelper:(pushNSHelperFunction)helperFN forClass:(char*)className {
    BOOL allGood = NO ;
// this hackery assumes that this method is only called from within the luaopen_* function of a module and
// attempts to compensate for a wrapper to "require"... I doubt anyone is actually using it anymore.
    int level = (int)[[NSUserDefaults standardUserDefaults] integerForKey:@"HSLuaSkinRegisterRequireLevel"];
    if (level == 0) level = 3 ;

    if (className && helperFN) {
        if (_registeredNSHelperFunctions[@(className)]) {
            [self logAtLevel:LS_LOG_WARN
                 withMessage:[NSString stringWithFormat:@"registerPushNSHelper:forClass:%s already defined at %@",
                                                        className,
                                                        _registeredNSHelperLocations[@(className)]]
                fromStackPos:level] ;
        } else {
            luaL_where(self.L, level) ;
            NSString *locationString = @(lua_tostring(self.L, -1)) ;
            _registeredNSHelperLocations[@(className)] = locationString;
            _registeredNSHelperFunctions[@(className)] = [NSValue valueWithPointer:(void *)helperFN];
            lua_pop(self.L, 1) ;
            allGood = YES ;
        }
    } else {
        [self logAtLevel:LS_LOG_WARN
             withMessage:@"registerPushNSHelper:forClass: requires both helperFN and className"
             fromStackPos:level] ;
    }
    return allGood ;
}

- (id)luaObjectAtIndex:(int)idx toClass:(char *)className {
    NSString *theClass = @(className) ;

    for (id key in _registeredLuaObjectHelperFunctions) {
        if ([theClass isEqualToString:key]) {
            luaObjectHelperFunction theFunc = (luaObjectHelperFunction)[_registeredLuaObjectHelperFunctions[key] pointerValue] ;
            return theFunc(self.L, lua_absindex(self.L, idx)) ;
        }
    }
    return nil ;
}

- (BOOL)registerLuaObjectHelper:(luaObjectHelperFunction)helperFN forClass:(char*)className {
    BOOL allGood = NO ;
// this hackery assumes that this method is only called from within the luaopen_* function of a module and
// attempts to compensate for a wrapper to "require"... I doubt anyone is actually using it anymore.
    int level = (int)[[NSUserDefaults standardUserDefaults] integerForKey:@"HSLuaSkinRegisterRequireLevel"];
    if (level == 0) level = 3 ;

    if (className && helperFN) {
        if (_registeredLuaObjectHelperFunctions[@(className)]) {
            [self logAtLevel:LS_LOG_WARN
                 withMessage:[NSString stringWithFormat:@"registerLuaObjectHelper:forClass:%s already defined at %@",
                                                        className,
                                                        _registeredLuaObjectHelperFunctions[@(className)]]
                fromStackPos:level] ;
        } else {
            luaL_where(self.L, level) ;
            NSString *locationString = @(lua_tostring(self.L, -1)) ;
            _registeredLuaObjectHelperLocations[@(className)] = locationString;
            _registeredLuaObjectHelperFunctions[@(className)] = [NSValue valueWithPointer:(void *)helperFN];
            lua_pop(self.L, 1) ;
            allGood = YES ;
        }
    } else {
        [self logAtLevel:LS_LOG_WARN
             withMessage:@"registerLuaObjectHelper:forClass: requires both helperFN and className"
            fromStackPos:level] ;
    }
    return allGood ;
}

- (BOOL)registerLuaObjectHelper:(luaObjectHelperFunction)helperFN forClass:(char *)className withUserdataMapping:(char *)userdataTag {
    BOOL allGood = [self registerLuaObjectHelper:helperFN forClass:className];
    if (allGood)
        _registeredLuaObjectHelperUserdataMappings[@(userdataTag)] = @(className);
    return allGood ;
}

- (int)pushNSObject:(id)obj withOptions:(LS_NSConversionOptions)options alreadySeenObjects:(NSMutableDictionary *)alreadySeen {
    if (obj) {
// NOTE: We catch self-referential loops, do we also need a recursive depth?  Will crash at depth of 512...
        if (alreadySeen[obj]) {
            lua_rawgeti(self.L, LUA_REGISTRYINDEX, [alreadySeen[obj] intValue]) ;
            return 1 ;
        }

        // check for registered helpers

        for (id key in _registeredNSHelperFunctions) {
            if ([obj isKindOfClass: NSClassFromString(key)]) {
                pushNSHelperFunction theFunc = (pushNSHelperFunction)[_registeredNSHelperFunctions[key] pointerValue] ;
                int resultAnswer = theFunc(self.L, obj) ;
                if (resultAnswer > -1) return resultAnswer ;
            }
        }

        // Check for built-in classes

        if ([obj isKindOfClass:[NSNull class]]) {
            lua_pushnil(self.L) ;
        } else if ([obj isKindOfClass:[NSNumber class]]) {
            [self pushNSNumber:obj withOptions:options] ;
// Note, the NSValue check must come *after* the NSNumber check, as NSNumber is a sub-class of NSValue
        } else if ([obj isKindOfClass:[NSValue class]]) {
            [self pushNSValue:obj withOptions:options] ;
        } else if ([obj isKindOfClass:[NSString class]]) {
                size_t size = [(NSString *)obj lengthOfBytesUsingEncoding:NSUTF8StringEncoding] ;
                lua_pushlstring(self.L, [(NSString *)obj UTF8String], size) ;
        } else if ([obj isKindOfClass:[NSData class]]) {
            lua_pushlstring(self.L, [(NSData *)obj bytes], [(NSData *)obj length]) ;
        } else if ([obj isKindOfClass:[NSDate class]]) {
            lua_pushinteger(self.L, lround([(NSDate *)obj timeIntervalSince1970])) ;
        } else if ([obj isKindOfClass:[NSArray class]]) {
            [self pushNSArray:obj withOptions:options alreadySeenObjects:alreadySeen] ;
        } else if ([obj isKindOfClass:[NSSet class]]) {
            [self pushNSSet:obj withOptions:options alreadySeenObjects:alreadySeen] ;
        } else if ([obj isKindOfClass:[NSDictionary class]]) {
            [self pushNSDictionary:obj withOptions:options alreadySeenObjects:alreadySeen] ;
        } else if ([obj isKindOfClass:[NSURL class]]) {
// normally I'd make a class a helper registered as part of a module; however, NSURL is common enough
// and 99% of the time we just want it stringified... by putting it in here, if someone needs it to do
// more later, they can register a helper to catch the object before it reaches here.
            lua_pushstring(self.L, [[obj absoluteString] UTF8String]) ;
        } else {
            if ((options & LS_NSDescribeUnknownTypes) == LS_NSDescribeUnknownTypes) {
                [self logVerbose:[NSString stringWithFormat:@"unrecognized type %@; converting to '%@'", NSStringFromClass([obj class]), [obj debugDescription]]] ;
                lua_pushstring(self.L, [[NSString stringWithFormat:@"%@", [obj debugDescription]] UTF8String]) ;
            } else if ((options & LS_NSIgnoreUnknownTypes) == LS_NSIgnoreUnknownTypes) {
                [self logVerbose:[NSString stringWithFormat:@"unrecognized type %@; ignoring", NSStringFromClass([obj class])]] ;
                return 0 ;
            }else {
                [self logDebug:[NSString stringWithFormat:@"unrecognized type %@; returning nil", NSStringFromClass([obj class])]] ;
                lua_pushnil(self.L) ;
            }
        }
    } else {
        lua_pushnil(self.L) ;
    }
    return 1 ;
}

- (id)toNSObjectAtIndex:(int)idx withOptions:(LS_NSConversionOptions)options alreadySeenObjects:(NSMutableDictionary *)alreadySeen {
    char *userdataTag = nil;

    int realIndex = lua_absindex(self.L, idx) ;
    NSMutableArray *seenObject = alreadySeen[[NSValue valueWithPointer:lua_topointer(self.L, idx)]] ;
    if (seenObject) {
        if ([[seenObject lastObject] isEqualToNumber:@(NO)] && ((options & LS_NSAllowsSelfReference) != LS_NSAllowsSelfReference)) {
            [self logAtLevel:LS_LOG_WARN
                 withMessage:@"lua table cannot contain self-references"
                fromStackPos:1] ;
//             return [NSNull null] ;
            return nil ;
        } else {
            return [seenObject firstObject] ;
        }
    }
    switch (lua_type(self.L, realIndex)) {
        case LUA_TNUMBER:
            if (lua_isinteger(self.L, idx)) {
                return @(lua_tointeger(self.L, idx)) ;
            } else {
                return @(lua_tonumber(self.L, idx));
            }
        case LUA_TSTRING: {
                LS_NSConversionOptions stringOptions = options & ( LS_NSPreserveLuaStringExactly | LS_NSLuaStringAsDataOnly ) ;
                if (stringOptions == LS_NSLuaStringAsDataOnly) {
                    size_t size ;
                    unsigned char *junk = (unsigned char *)lua_tolstring(self.L, idx, &size) ;
                    return [NSData dataWithBytes:(void *)junk length:size] ;
                } else if (stringOptions == LS_NSPreserveLuaStringExactly) {
                    if ([self isValidUTF8AtIndex:idx]) {
                        size_t size ;
                        unsigned char *string = (unsigned char *)lua_tolstring(self.L, idx, &size) ;
                        return [[NSString alloc] initWithData:[NSData dataWithBytes:(void *)string length:size] encoding: NSUTF8StringEncoding] ;
                    } else {
                        size_t size ;
                        unsigned char *junk = (unsigned char *)lua_tolstring(self.L, idx, &size) ;
                        return [NSData dataWithBytes:(void *)junk length:size] ;
                    }
                } else {
                    if (stringOptions != LS_NSNone) {
                        [self logAtLevel:LS_LOG_DEBUG
                             withMessage:@"only one of LS_NSPreserveLuaStringExactly or LS_NSLuaStringAsDataOnly can be specified: using default behavior"
                            fromStackPos:0] ;
                    }
                    return [self getValidUTF8AtIndex:idx] ;
                }
            }
        case LUA_TNIL:
            return [NSNull null] ;
        case LUA_TBOOLEAN:
            return lua_toboolean(self.L, idx) ? (id)kCFBooleanTrue : (id)kCFBooleanFalse;
        case LUA_TTABLE:
            return [self tableAtIndex:realIndex withOptions:options alreadySeenObjects:alreadySeen] ;
        case LUA_TUSERDATA: // Note: This is specifically last, so it can fall through to the default case, for objects we can't handle automatically
            //FIXME: This seems very unsafe to happen outside a protected call
            if (lua_getfield(self.L, realIndex, "__type") == LUA_TSTRING) {
                userdataTag = (char *)lua_tostring(self.L, -1);
            }
            lua_pop(self.L, 1);

            if (userdataTag) {
                NSString *classMapping = _registeredLuaObjectHelperUserdataMappings[@(userdataTag)];
                if (classMapping) {
                    return [self luaObjectAtIndex:realIndex toClass:(char *)[classMapping UTF8String]];
                }
            }
            if (userdataTag) [self logBreadcrumb:[NSString stringWithFormat:@"unrecognized userdata type %s", userdataTag]] ;
        default:
            if ((options & LS_NSDescribeUnknownTypes) == LS_NSDescribeUnknownTypes) {
                NSString *answer = @(luaL_tolstring(self.L, idx, NULL));
                [self logVerbose:[NSString stringWithFormat:@"unrecognized type %s; converting to '%@'", lua_typename(self.L, lua_type(self.L, realIndex)), answer]] ;
                lua_pop(self.L, 1) ;
                return answer ;
            } else if ((options & LS_NSIgnoreUnknownTypes) == LS_NSIgnoreUnknownTypes) {
                [self logVerbose:[NSString stringWithFormat:@"unrecognized type %s; ignoring with placeholder [NSNull null]",
                                                          lua_typename(self.L, lua_type(self.L, realIndex))]] ;
                return [NSNull null] ;
            } else {
                [self logDebug:[NSString stringWithFormat:@"unrecognized type %s; returning nil", lua_typename(self.L, lua_type(self.L, realIndex))]] ;
                return nil ;
            }
    }
}

@end