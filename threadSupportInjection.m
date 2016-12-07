@import Cocoa ;
@import LuaSkin ;
@import ObjectiveC.runtime ;

NSMapTable *threadToRefTableMap ;
NSMapTable *threadToSkinMap ;

#pragma mark - Support Functions and Classes

@interface LuaSkin (threadedPrivate)

+ (LuaSkin *)originalShared ;
- (id)originalInit ;
- (void)originalDestroyLuaState ;

@end

@implementation LuaSkin (threaded)

+(BOOL)injectThreadSupport {
    static dispatch_once_t onceToken ;
    static BOOL            injectionLooksGood = YES ;

    dispatch_once(&onceToken, ^{
        Class LuaSkinClass     = [LuaSkin class] ;
        Class LuaSkinMetaclass = object_getClass(LuaSkinClass) ;

        if (injectionLooksGood) {
            Method     oldMethod    = class_getClassMethod(LuaSkinMetaclass, NSSelectorFromString(@"shared")) ;
            Method     newMethod    = class_getClassMethod(LuaSkinMetaclass, NSSelectorFromString(@"threadShared")) ;
            IMP        oldImp       = method_getImplementation(oldMethod) ;
            const char *oldEncoding = method_getTypeEncoding(oldMethod) ;

            method_exchangeImplementations(oldMethod, newMethod) ;
            injectionLooksGood = class_addMethod(LuaSkinMetaclass, NSSelectorFromString(@"originalShared"), oldImp, oldEncoding) ;
            [LuaSkin logDebug:[NSString stringWithFormat:@"+[LuaSkin shared] swizzling %@", (injectionLooksGood ? @"succeeded" : @"failed")]] ;
        }
        if (injectionLooksGood) {
            Method     oldMethod    = class_getInstanceMethod(LuaSkinClass, NSSelectorFromString(@"init")) ;
            Method     newMethod    = class_getInstanceMethod(LuaSkinClass, NSSelectorFromString(@"threadInit")) ;
            IMP        oldImp       = method_getImplementation(oldMethod) ;
            const char *oldEncoding = method_getTypeEncoding(oldMethod) ;

            method_exchangeImplementations(oldMethod, newMethod) ;
            injectionLooksGood = class_addMethod(LuaSkinClass, NSSelectorFromString(@"originalInit"), oldImp, oldEncoding) ;
            [LuaSkin logDebug:[NSString stringWithFormat:@"-[LuaSkin init] swizzling %@", (injectionLooksGood ? @"succeeded" : @"failed")]] ;
        }
        if (injectionLooksGood) {
            Method     oldMethod    = class_getInstanceMethod(LuaSkinClass, NSSelectorFromString(@"destroyLuaState")) ;
            Method     newMethod    = class_getInstanceMethod(LuaSkinClass, NSSelectorFromString(@"threadDestroyLuaState")) ;
            IMP        oldImp       = method_getImplementation(oldMethod) ;
            const char *oldEncoding = method_getTypeEncoding(oldMethod) ;

            method_exchangeImplementations(oldMethod, newMethod) ;
            injectionLooksGood = class_addMethod(LuaSkinClass, NSSelectorFromString(@"originalDestroyLuaState"), oldImp, oldEncoding) ;
            [LuaSkin logDebug:[NSString stringWithFormat:@"-[LuaSkin destroyLuaState] swizzling %@", (injectionLooksGood ? @"succeeded" : @"failed")]] ;
        }

        if (!injectionLooksGood) {
            [LuaSkin logError:@"Restart Hammerspoon -- LuaSkin is in an unknown state"] ;
        }
    });
    return injectionLooksGood ;
}

+ (id)threaded {
    NSThread *thisThread = [NSThread currentThread] ;

    // if we're on the main thread, go ahead and act normally
    if ([thisThread isMainThread]) return [LuaSkin shared] ;

    LuaSkin *thisSkin = threadToSkinMap ? [threadToSkinMap objectForKey:thisThread] : nil ;
    if (!thisSkin) {
        NSException* myException = [NSException
                                    exceptionWithName:@"LuaSkinMissing"
                                    reason:@"LuaSkin has not been initialized on this thread"
                                    userInfo:nil];
        @throw myException;
    }
    return thisSkin ;
}

- (int)refTableFor:(const char *)tagName {
    NSString *key = (tagName) ? @(tagName) : @"_non-unique_" ;
    NSMutableDictionary *refTableMap = [threadToRefTableMap objectForKey:[NSThread currentThread]] ;
    if (!refTableMap) { // LuaSkin's initialized before we're injected won't have this
        [LuaSkin logDebug:[NSString stringWithFormat:@"-[LuaSkin refTableFor:%@] invoked on thread without an existing table", key]] ;
        refTableMap = [[NSMutableDictionary alloc] init] ;
        [threadToRefTableMap setObject:refTableMap forKey:[NSThread currentThread]] ;
    }
    NSNumber *reference = refTableMap[key] ;
    if (!reference) {
        lua_newtable(self.L);
        int moduleRefTable = luaL_ref(self.L, LUA_REGISTRYINDEX);
        refTableMap[key] = @(moduleRefTable) ;
        reference = refTableMap[key] ;
    }
    return [reference intValue] ;
}

#pragma mark * Swizzled methods

+ (id)threadShared {
//     NSLog(@"in threadShared") ;
    NSThread *thisThread = [NSThread currentThread] ;
    if ([thisThread isMainThread]) return [self originalShared] ;

    LuaSkin *alternateSkin = threadToSkinMap ? [threadToSkinMap objectForKey:thisThread] : nil ;
    if (alternateSkin) {
        [LuaSkin logInfo:@"attempt to use module or function does not support execution in an alternate thread"] ;
        luaL_error(alternateSkin.L, "module or function does not support execution in an alternate thread") ;
    } else {
        HSNSLOG(@"GRAVE BUG CASE 2: LUA EXECUTION ON NON-MAIN THREAD");
        for (NSString *stackSymbol in [NSThread callStackSymbols]) {
            HSNSLOG(@"Previous stack symbol: %@", stackSymbol);
        }
        NSException* myException = [NSException
                                    exceptionWithName:@"LuaOnNonMainThread"
                                    reason:@"Lua execution is happening on a non-main thread"
                                    userInfo:nil];
        @throw myException;
    }
    return nil ;
}

- (id)threadInit {
    NSLog(@"in threadInit") ;
    id result = [self originalInit] ;
    NSLog(@"back from originalInit") ;

    NSMutableDictionary *refTableMap = [[NSMutableDictionary alloc] init] ;
    [threadToRefTableMap setObject:refTableMap forKey:[NSThread currentThread]] ;
    [threadToSkinMap setObject:self forKey:[NSThread currentThread]] ;
    return result ;
}

- (void)threadDestroyLuaState {
    NSLog(@"in threadDestroyState") ;
    [self originalDestroyLuaState] ;
    NSLog(@"back from originalDestroyLuaState") ;

    NSMutableDictionary *refTableMap = [threadToRefTableMap objectForKey:[NSThread currentThread]] ;
    if (refTableMap) { // LuaSkin's initialized before we're injected won't have this
        [refTableMap removeAllObjects] ;
    }
}

@end

int luaopen_hs_luathread_threadSupportInjection(lua_State* L) {
    lua_newtable(L) ;
    lua_pushboolean(L, [NSThread isMainThread]) ; lua_setfield(L, -2, "onMainThread") ;
    if ([NSThread isMainThread]) {
        lua_pushboolean(L, [LuaSkin injectThreadSupport]) ; lua_setfield(L, -2, "injectionStatus") ;
        threadToSkinMap     = [NSMapTable weakToStrongObjectsMapTable] ;
        threadToRefTableMap = [NSMapTable weakToStrongObjectsMapTable] ;
        [threadToSkinMap setObject:[LuaSkin shared] forKey:[NSThread mainThread]] ;
    }
    return 1;
}
