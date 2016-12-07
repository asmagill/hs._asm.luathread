@import Cocoa ;
@import LuaSkin ;
#import "../HSLuaThread.h"
#import "../LuaSkin+threaded.h"

static const char *USERDATA_TAG = "hs.luathread.luaskin" ;
static NSDictionary *initialAssignmentsForThread ;

#define get_objectFromUserdata(objType, L, idx, tag) (objType*)*((void**)luaL_checkudata(L, idx, tag))

#pragma mark - Support Functions and Classes

static void registerLuaSkinThreadWithSkin(LuaSkin *skin) ;

@interface LuaSkinThread : HSLuaThread <LuaSkinDelegate>
@property (readonly) int            runStringRef ;
@property (readonly) LuaSkin        *skin ;
@property (readonly) lua_State      *L ;
@end

@implementation LuaSkinThread

-(instancetype)initWithName:(NSString *)name {
    self = [super initWithName:name] ;
    if (self) {
        _runStringRef = LUA_NOREF ;
    }
    return self ;
}

- (BOOL)startInstance {
    self.restartLuaState = NO ;

    _skin = [[LuaSkin alloc] init];
    _L = _skin.L ;
    _skin.delegate = self ;

    lua_pushglobaltable(_L) ;
    registerLuaSkinThreadWithSkin(_skin) ;
    [_skin pushNSObject:self] ;
    lua_setfield(_L, -2, "_instance") ;

    NSString *threadInitFile = [initialAssignmentsForThread objectForKey:@"coreinitfile"] ;
    if (threadInitFile) {
        int loadresult = luaL_loadfile(_L, [threadInitFile UTF8String]);
        if (loadresult != 0) {
            [LuaSkin logError:[NSString stringWithFormat:@"%s:startInstance - unable to load core init file %@: %s", USERDATA_TAG, threadInitFile, lua_tostring(_L, -1)]] ;
            lua_pop(_L, 1) ;
            return NO ;
        }
        lua_pushstring(_L, [self.name UTF8String]) ;
        [_skin pushNSObject:initialAssignmentsForThread] ;
        if (lua_pcall(_L, 2, 1, 0) != LUA_OK) {
            [LuaSkin logError:[NSString stringWithFormat:@"%s:startInstance - unable to execute core init file %@: %s", USERDATA_TAG, threadInitFile, lua_tostring(_L, -1)]] ;
            lua_pop(_L, 1) ;
            return NO ;
        }
        if (lua_type(_L, -1) == LUA_TFUNCTION) {
            _runStringRef = luaL_ref(_L, LUA_REGISTRYINDEX) ; // eats returned type, so no pop necessary
        } else {
            [LuaSkin logError:[NSString stringWithFormat:@"%s:startInstance - core init file %@ did not return a function, found %s", USERDATA_TAG, threadInitFile, luaL_tolstring(_L, -1, NULL)]] ;
            lua_pop(_L, 2) ; // return type & __tostring version of it
            return NO ;
        }
    } else {
        [LuaSkin logError:[NSString stringWithFormat:@"%s:startInstance - no core init file defined", USERDATA_TAG]] ;
        return NO ;
    }
    return YES ;
}

- (void)restartInstance {
#ifdef VERBOSE_LOGGING
    [LuaSkin logDebug:[NSString stringWithFormat:@"%s:restartInstance - reload requested for %@", USERDATA_TAG, self.name]] ;
#endif
    _skin.delegate = nil ;
    [_skin destroyLuaState] ;
    _runStringRef = LUA_NOREF ;
    if (![self startInstance]) {
        [LuaSkin logError:[NSString stringWithFormat:@"%s:restartInstance - exiting thread; error during reload for %@", USERDATA_TAG, self.name]] ;
        self.performCleanClose = NO ;
        [self cancel] ;
    }
}

- (void)instanceCancelled:(BOOL)cleanClose {
    if (cleanClose) {
        luaL_unref(_L, LUA_REGISTRYINDEX, _runStringRef) ;
        _skin.delegate = nil ;
        [_skin destroyLuaState] ;
    }
    _runStringRef = LUA_NOREF ;
}

- (void)handleIncomingData:(NSData *)input {
    if (_runStringRef != LUA_NOREF) {
        int preStackTop = lua_absindex(_L, lua_gettop(_L)) ;
        lua_rawgeti(_L, LUA_REGISTRYINDEX, _runStringRef);
        lua_pushlstring(_L, [input bytes], [input length]) ;
        @try {
            if (lua_pcall(_L, 1, LUA_MULTRET, 0) != LUA_OK) {
                [LuaSkin logError:[NSString stringWithFormat:@"%s:handleIncomingData: - exiting thread; error in runstring function for %@:%s", USERDATA_TAG, self.name, lua_tostring(_L, -1)]] ;
                self.performCleanClose = NO ;
                [self cancel] ;
                lua_pop(_L, 1) ;
            } else {
                [self flushOutput] ; // make sure all printed output gets sent to callback
                int postStackTop = lua_absindex(_L, lua_gettop(_L)) ;
                NSMutableArray *results = [[NSMutableArray alloc] init] ;
                for (int i = preStackTop ; i < postStackTop ; i++) {
                    id value = [_skin toNSObjectAtIndex:(i + 1) withOptions:LS_NSUnsignedLongLongPreserveBits |
                                                                            LS_NSDescribeUnknownTypes         |
                                                                            LS_NSPreserveLuaStringExactly     |
                                                                            LS_NSAllowsSelfReference] ;
                    if (!value) value = [NSNull null] ;
                    [results addObject:value] ;
                }
                [self returnResults:results] ;
                for (int i = preStackTop ; i < postStackTop ; i++) { lua_pop(_L, 1) ; }
            }
        } @catch (NSException *theException) {
            [self logAtLevel:LS_LOG_ERROR withMessage:[NSString stringWithFormat:@"%s:handleIncomingData: - exception evaluating input:%@", USERDATA_TAG, theException]] ;
        }
    } else {
        [LuaSkin logError:[NSString stringWithFormat:@"%s:handleIncomingData: - exiting thread; missing runstring function for %@", USERDATA_TAG, self.name]] ;
        self.performCleanClose = NO ;
        [self cancel] ;
    }
}

- (void)logAtLevel:(int)level withMessage:(NSString *)message {
    [super logAtLevel:level withMessage:message] ;
    [_skin logAtLevel:level withMessage:message] ;
}

@end

#pragma mark - Module Functions

static int luaskin_newThread(lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TSTRING | LS_TOPTIONAL, LS_TBREAK] ;
    NSString *name = (lua_type(L, 1) == LUA_TSTRING) ? [NSString stringWithFormat:@"%@::%@", [skin toNSObjectAtIndex:1], [[NSUUID UUID] UUIDString]] : [[NSUUID UUID] UUIDString] ;
    LuaSkinThread *threadObject = [[LuaSkinThread alloc] initWithName:name] ;
    return luathread_managerForThreadWithType(L, threadObject, @"LuaSkin") ;
}

static int luaskin_initialAssignments(__unused lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TTABLE, LS_TBREAK] ;
    initialAssignmentsForThread = [skin toNSObjectAtIndex:1] ;
    return 0 ;
}

#pragma mark - Module Methods

static int luaskin_timestamp(lua_State *L) {
    lua_pushnumber(L, [[NSDate date] timeIntervalSince1970]) ;
    return 1 ;
}

static int luaskin_threadIsCancelled(lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK] ;
    LuaSkinThread *thread = [skin toNSObjectAtIndex:1] ;
    lua_pushboolean(L, thread.cancelled) ;
    return 1 ;
}

static int luaskin_threadName(__unused lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK] ;
    LuaSkinThread *thread = [skin toNSObjectAtIndex:1] ;
    [skin pushNSObject:thread.name] ;
    return 1 ;
}

static int luaskin_getFromDictionary(__unused lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TSTRING, LS_TBREAK] ;
    LuaSkinThread *thread = [skin toNSObjectAtIndex:1] ;
    NSString *key = [skin toNSObjectAtIndex:2] ;
    id obj = [thread sharedDictionaryGetObjectForKey:key] ;
    [skin pushNSObject:obj withOptions:LS_NSUnsignedLongLongPreserveBits |
                                       LS_NSDescribeUnknownTypes         |
                                       LS_NSPreserveLuaStringExactly     |
                                       LS_NSAllowsSelfReference] ;
    return 1 ;
}

static int luaskin_setInDictionary(lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TSTRING, LS_TANY, LS_TBREAK] ;
    LuaSkinThread *thread = [skin toNSObjectAtIndex:1] ;
    NSString *key = [skin toNSObjectAtIndex:2] ;
    id value = [skin toNSObjectAtIndex:3 withOptions:LS_NSUnsignedLongLongPreserveBits |
                                                     LS_NSDescribeUnknownTypes         |
                                                     LS_NSPreserveLuaStringExactly     |
                                                     LS_NSAllowsSelfReference] ;
    if ([thread sharedDictionarySetObject:value forKey:key]) {
        lua_pushvalue(L, 1) ;
    } else {
        lua_pushnil(L) ;
    }
    return 1 ;
}

static int luaskin_keysForDictionary(__unused lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK] ;
    LuaSkinThread *thread = [skin toNSObjectAtIndex:1] ;
    NSArray *theKeys = [thread sharedDictionaryGetKeys] ;
    [skin pushNSObject:theKeys] ;
    return 1 ;
}

static int luaskin_cancelThread(lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TANY | LS_TOPTIONAL, LS_TANY | LS_TOPTIONAL, LS_TBREAK] ;
    LuaSkinThread *thread = [skin toNSObjectAtIndex:1] ;
    if (lua_type(L, 3) != LUA_TNONE) {
        thread.performCleanClose = (BOOL)lua_toboolean(L, 3) ;
    }
    [thread cancel] ;
    lua_pushvalue(L, 1) ;
    return 1 ;
}

static int luaskin_reloadLuaThread(__unused lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK] ;
    LuaSkinThread *thread = [skin toNSObjectAtIndex:1] ;
    thread.restartLuaState = YES ;
    return 0 ;
}

static int luaskin_pushResults(lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK | LS_TVARARG] ;
    LuaSkinThread *thread = [skin toNSObjectAtIndex:1] ;
    NSMutableArray *results = [[NSMutableArray alloc] init] ;
    int            n       = lua_gettop(L);
    for (int i = 2 ; i <= n ; i++) {
        id value = [skin toNSObjectAtIndex:i withOptions:LS_NSUnsignedLongLongPreserveBits |
                                                         LS_NSDescribeUnknownTypes         |
                                                         LS_NSPreserveLuaStringExactly     |
                                                         LS_NSAllowsSelfReference] ;
        if (!value) value = [NSNull null] ;
        [results addObject:value] ;
    }
    [thread returnResults:results] ;
    lua_pushvalue(L, 1) ;
    return 1 ;
}

static int luaskin_printOutput(lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK | LS_TVARARG] ;
    LuaSkinThread *thread = [skin toNSObjectAtIndex:1] ;
    NSMutableData  *output = [[NSMutableData alloc] init] ;
    int            n       = lua_gettop(L);
    size_t         size ;
    for (int i = 2 ; i <= n ; i++) {
        const void *junk = luaL_tolstring(L, i, &size) ;
        if (i > 2) [output appendBytes:"\t" length:1] ;
        [output appendBytes:junk length:size] ;
        lua_pop(L, 1) ;
    }
    [output appendBytes:"\n" length:1] ;
    [thread returnOutput:output] ;
    lua_pushvalue(L, 1) ;
    return 1 ;
}

static int luaskin_printOutputToConsole(lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK | LS_TVARARG] ;
    LuaSkinThread *thread = [skin toNSObjectAtIndex:1] ;
    NSMutableData  *output = [[NSMutableData alloc] init] ;
    int            n       = lua_gettop(L);
    size_t         size ;
    for (int i = 2 ; i <= n ; i++) {
        const void *junk = luaL_tolstring(L, i, &size) ;
        if (i > 2) [output appendBytes:"\t" length:1] ;
        [output appendBytes:junk length:size] ;
        lua_pop(L, 1) ;
    }
    [output appendBytes:"\n" length:1] ;
    dispatch_async(dispatch_get_main_queue(), ^{
        LuaSkin   *mainSkin = [LuaSkin shared] ;
        lua_State *mainL    = [mainSkin L] ;
        lua_getglobal(mainL, "print") ;
        lua_pushlstring(mainL, [output bytes], [output length]) ;
        if (lua_pcall(mainL, 1, 0,0 ) != LUA_OK) {
            [thread logAtLevel:LS_LOG_ERROR withMessage:[NSString stringWithFormat:@"%s:printToConsole error - %s", USERDATA_TAG, lua_tostring(mainL, -1)]] ;
            lua_pop(mainL, 1) ;
        }
    }) ;
    lua_pushvalue(L, 1) ;
    return 1 ;
}

static int luaskin_flushOutput(lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK] ;
    LuaSkinThread *thread = [skin toNSObjectAtIndex:1] ;
    [thread flushOutput] ;
    lua_pushvalue(L, 1) ;
    return 1 ;
}

#pragma mark - Module Constants

#pragma mark - Lua<->NSObject Conversion Functions
// These must not throw a lua error to ensure LuaSkin can safely be used from Objective-C
// delegates and blocks.

static int pushLuaSkinThread(lua_State *L, id obj) {
    LuaSkinThread *value = obj;
    void** valuePtr = lua_newuserdata(L, sizeof(LuaSkinThread *));
    *valuePtr = (__bridge_retained void *)value;
    luaL_getmetatable(L, USERDATA_TAG);
    lua_setmetatable(L, -2);
    return 1;
}

id toLuaSkinThreadFromLua(lua_State *L, int idx) {
    LuaSkin *skin = [LuaSkin threaded] ;
    LuaSkinThread *value ;
    if (luaL_testudata(L, idx, USERDATA_TAG)) {
        value = get_objectFromUserdata(__bridge LuaSkinThread, L, idx, USERDATA_TAG) ;
    } else {
        [skin logError:[NSString stringWithFormat:@"expected %s object, found %s", USERDATA_TAG,
                                                   lua_typename(L, lua_type(L, idx))]] ;
    }
    return value ;
}

#pragma mark - Hammerspoon/Lua Infrastructure

static int userdata_tostring(lua_State* L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    LuaSkinThread *obj = [skin luaObjectAtIndex:1 toClass:"LuaSkinThread"] ;
    NSString *title = obj.name ;
    [skin pushNSObject:[NSString stringWithFormat:@"%s: %@ (%p)", USERDATA_TAG, title, lua_topointer(L, 1)]] ;
    return 1 ;
}

static int userdata_eq(lua_State* L) {
// can't get here if at least one of us isn't a userdata type, and we only care if both types are ours,
// so use luaL_testudata before the macro causes a lua error
    if (luaL_testudata(L, 1, USERDATA_TAG) && luaL_testudata(L, 2, USERDATA_TAG)) {
        LuaSkin *skin = [LuaSkin threaded] ;
        LuaSkinThread *obj1 = [skin luaObjectAtIndex:1 toClass:"LuaSkinThread"] ;
        LuaSkinThread *obj2 = [skin luaObjectAtIndex:2 toClass:"LuaSkinThread"] ;
        lua_pushboolean(L, [obj1 isEqualTo:obj2]) ;
    } else {
        lua_pushboolean(L, NO) ;
    }
    return 1 ;
}

static int userdata_gc(lua_State* L) {
    LuaSkinThread *obj = get_objectFromUserdata(__bridge_transfer LuaSkinThread, L, 1, USERDATA_TAG) ;
    if (obj) {
#ifdef VERBOSE_LOGGING
        [LuaSkin logDebug:[NSString stringWithFormat:@"%s:__gc for %@", USERDATA_TAG, obj.name]] ;
#endif
        if (!obj.restartLuaState) {
            [obj cancel] ;
#ifdef VERBOSE_LOGGING
        } else {
            [LuaSkin logDebug:[NSString stringWithFormat:@"%s:__gc for thread:reload, skipping teardown", USERDATA_TAG]] ;
#endif
        }
        obj = nil ;
    }
    // Remove the Metatable so future use of the variable in Lua won't think its valid
    lua_pushnil(L) ;
    lua_setmetatable(L, 1) ;
    return 0 ;
}

// static int meta_gc(lua_State* __unused L) {
//     return 0 ;
// }

// Metatable for userdata objects
static const luaL_Reg userdata_metaLib[] = {
    {"cancel",            luaskin_cancelThread},
    {"name",              luaskin_threadName},
    {"isCancelled",       luaskin_threadIsCancelled},
    {"timestamp",         luaskin_timestamp},
    {"print",             luaskin_printOutput},
    {"printToConsole",    luaskin_printOutputToConsole},
    {"flush",             luaskin_flushOutput},
    {"reload",            luaskin_reloadLuaThread},
    {"getFromDictionary", luaskin_getFromDictionary},
    {"setInDictionary",   luaskin_setInDictionary},
    {"keysForDictionary", luaskin_keysForDictionary},
    {"push",              luaskin_pushResults},

    {"__tostring",        userdata_tostring},
    {"__eq",              userdata_eq},
    {"__gc",              userdata_gc},
    {NULL,                NULL}
};

// We need this in the instance, not in the management thread, so this doesn't belong
// in the traditional initializer.
static void registerLuaSkinThreadWithSkin(LuaSkin *skin) {
    [skin registerObject:USERDATA_TAG objectFunctions:userdata_metaLib] ;
    [skin registerPushNSHelper:pushLuaSkinThread         forClass:"LuaSkinThread"];
    [skin registerLuaObjectHelper:toLuaSkinThreadFromLua forClass:"LuaSkinThread"
                                              withUserdataMapping:USERDATA_TAG];
}

// Functions for returned object when module loads
static luaL_Reg moduleLib[] = {
    {"_initialAssignments", luaskin_initialAssignments},
    {"_new",                luaskin_newThread},
    {NULL,          NULL}
};

int luaopen_hs_luathread_luaskin_internal(lua_State* __unused L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin registerLibrary:moduleLib metaFunctions:nil] ;

    return 1;
}
