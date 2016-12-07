@import Cocoa ;
@import LuaSkin ;
@import ObjectiveC.runtime ;

static NSMutableDictionary *refTableMap ;

#pragma mark - Support Functions and Classes

@interface HSLuaSkinWrapper : NSObject
@end

@implementation HSLuaSkinWrapper

- (int)refTableFor:(const char *)tagName {
    LuaSkin   *skin = [LuaSkin shared] ;
    lua_State *L    = skin.L ;

    NSString *key = (tagName) ? @(tagName) : @"_non-unique_" ;
    NSNumber *reference = refTableMap[key] ;
    if (!reference) {
        lua_newtable(L);
        int moduleRefTable = luaL_ref(L, LUA_REGISTRYINDEX);
        refTableMap[key] = @(moduleRefTable) ;
        reference = refTableMap[key] ;
    }
    return [reference intValue] ;
}

@end

#pragma mark - Module Functions

static int testThreadSuport(lua_State *L) {
    lua_pushboolean(L, [LuaSkin respondsToSelector:NSSelectorFromString(@"refTableReferences")]) ;
    return 1 ;
}

static int injectPlaceholders(__unused lua_State *L) {
    if (![LuaSkin respondsToSelector:NSSelectorFromString(@"refTableReferences")]) {
        if (![[LuaSkin class] respondsToSelector:NSSelectorFromString(@"threaded")]) {
            Class  LSClass     = object_getClass([LuaSkin class]) ;
            SEL    oldSelector = NSSelectorFromString(@"shared") ;
            SEL    newSelector = NSSelectorFromString(@"threaded") ;
            Method method      = class_getClassMethod(LSClass, oldSelector) ;
            BOOL wasAdded = class_addMethod(LSClass,
                                            newSelector,
                                            method_getImplementation(method),
                                            method_getTypeEncoding(method)) ;
            if (wasAdded) {
                [LuaSkin logInfo:@"[LuaSkin threaded] injected"] ;
            } else {
                [LuaSkin logInfo:@"[LuaSkin threaded] injection failed"] ;
            }
        } else {
            [LuaSkin logWarn:@"[LuaSkin threaded] already injected"] ;
        }
        if (![LuaSkin respondsToSelector:NSSelectorFromString(@"refTableFor:")]) {
            Class  LSClass     = [LuaSkin class] ;
            Class  WRClass     = [HSLuaSkinWrapper class] ;
            SEL    newSelector = NSSelectorFromString(@"refTableFor:") ;
            Method method      = class_getInstanceMethod(WRClass, newSelector) ;
            BOOL wasAdded = class_addMethod(LSClass,
                                            newSelector,
                                            method_getImplementation(method),
                                            method_getTypeEncoding(method)) ;
            if (wasAdded) {
                [LuaSkin logInfo:@"[LuaSkin refTableFor:] injected"] ;
            } else {
                [LuaSkin logInfo:@"[LuaSkin refTableFor:] injection failed"] ;
            }
        } else {
            [LuaSkin logWarn:@"[LuaSkin refTableFor:] already injected"] ;
        }
    } else {
        [LuaSkin logWarn:@"Hammerspoon Application already supports threads"] ;
    }
    return 0 ;
}

// Functions for returned object when module loads
static luaL_Reg moduleLib[] = {
    {"supported",          testThreadSuport},
    {"injectPlaceholders", injectPlaceholders},
    {NULL,                 NULL}
};

// // Metatable for module, if needed
// static const luaL_Reg module_metaLib[] = {
//     {"__gc", meta_gc},
//     {NULL,   NULL}
// };

int luaopen_hs_luathread_supported(__unused lua_State* L) {
    LuaSkin *skin = [LuaSkin shared] ;
    [skin registerLibrary:moduleLib metaFunctions:nil] ;

    refTableMap = [[NSMutableDictionary alloc] init] ;

    return 1;
}
