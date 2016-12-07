@import Cocoa ;
@import LuaSkin ;
#import "LuaSkin+Properties.h"
#import "../LuaSkin+threaded.h"

static const char *USERDATA_TAG = "hs.luathread.luaskin.skin" ;

extern NSMapTable *threadToSkinMap ;
extern NSMapTable *threadToRefTableMap ;

#define get_objectFromUserdata(objType, L, idx, tag) (objType*)*((void**)luaL_checkudata(L, idx, tag))

#pragma mark - Support Functions and Classes

#pragma mark - Module Functions

static int skin_currentLuaSkin(__unused lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TBREAK] ;
    [skin pushNSObject:skin] ;
    return 1 ;
}

#pragma mark - Module Methods

static int skin_onMainThread(lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK] ;
    LuaSkin *altSkin = [skin toNSObjectAtIndex:1] ;
    NSThread *skinThread ;

    NSEnumerator *enumerator = [threadToSkinMap keyEnumerator];
    NSThread *aThread ;
    while ((aThread = [enumerator nextObject])) {
        LuaSkin *aSkin = [threadToSkinMap objectForKey:aThread] ;
        if ([aSkin isEqualTo:altSkin]) {
            skinThread = aThread ;
            break ;
        }
    }
    if (!skinThread) {
        [LuaSkin logDebug:[NSString stringWithFormat:@"%s:onMainThread - unable to identify thread for skin", USERDATA_TAG]] ;
    }

    lua_pushboolean(L, skinThread ? [skinThread isMainThread] : NO) ;
    return 1 ;
}

static int skin_onThisThread(lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK] ;
    LuaSkin *altSkin = [skin toNSObjectAtIndex:1] ;
    lua_pushboolean(L, [skin isEqualTo:altSkin]) ;
    return 1 ;
}

static int skin_refTableReferences(__unused lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK] ;
    NSMutableDictionary *refTableMap = [threadToRefTableMap objectForKey:[NSThread currentThread]] ;
    [skin pushNSObject:refTableMap] ;
    return 1 ;
}

static int skin_NSHelperFunctions(__unused lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK] ;
    LuaSkin *altSkin = [skin toNSObjectAtIndex:1] ;
    [skin pushNSObject:altSkin.registeredNSHelperFunctions
           withOptions:LS_NSDescribeUnknownTypes | LS_NSUnsignedLongLongPreserveBits] ;
    return 1 ;
}

static int skin_NSHelperLocations(__unused lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK] ;
    LuaSkin *altSkin = [skin toNSObjectAtIndex:1] ;
    [skin pushNSObject:altSkin.registeredNSHelperLocations
           withOptions:LS_NSDescribeUnknownTypes | LS_NSUnsignedLongLongPreserveBits] ;
    return 1 ;
}

static int skin_LuaObjectHelperFunctions(__unused lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK] ;
    LuaSkin *altSkin = [skin toNSObjectAtIndex:1] ;
    [skin pushNSObject:altSkin.registeredLuaObjectHelperFunctions
           withOptions:LS_NSDescribeUnknownTypes | LS_NSUnsignedLongLongPreserveBits] ;
    return 1 ;
}

static int skin_LuaObjectHelperLocations(__unused lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK] ;
    LuaSkin *altSkin = [skin toNSObjectAtIndex:1] ;
    [skin pushNSObject:altSkin.registeredLuaObjectHelperLocations
           withOptions:LS_NSDescribeUnknownTypes | LS_NSUnsignedLongLongPreserveBits] ;
    return 1 ;
}

static int skin_LuaObjectHelperUserdataMappings(__unused lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK] ;
    LuaSkin *altSkin = [skin toNSObjectAtIndex:1] ;
    [skin pushNSObject:altSkin.registeredLuaObjectHelperUserdataMappings
           withOptions:LS_NSDescribeUnknownTypes | LS_NSUnsignedLongLongPreserveBits] ;
    return 1 ;
}

static int skin_LuaObjectHelperTableMappings(__unused lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK] ;
    LuaSkin *altSkin = [skin toNSObjectAtIndex:1] ;
    [skin pushNSObject:altSkin.registeredLuaObjectHelperTableMappings
           withOptions:LS_NSDescribeUnknownTypes | LS_NSUnsignedLongLongPreserveBits] ;
    return 1 ;
}

#pragma mark - Module Constants

#pragma mark - Lua<->NSObject Conversion Functions
// These must not throw a lua error to ensure LuaSkin can safely be used from Objective-C
// delegates and blocks.

static int pushLuaSkin(lua_State *L, id obj) {
    LuaSkin *value = obj;
    void** valuePtr = lua_newuserdata(L, sizeof(LuaSkin *));
    *valuePtr = (__bridge_retained void *)value;
    luaL_getmetatable(L, USERDATA_TAG);
    lua_setmetatable(L, -2);
    return 1;
}

id toLuaSkinFromLua(lua_State *L, int idx) {
    LuaSkin *skin = [LuaSkin threaded] ;
    LuaSkin *value ;
    if (luaL_testudata(L, idx, USERDATA_TAG)) {
        value = get_objectFromUserdata(__bridge LuaSkin, L, idx, USERDATA_TAG) ;
    } else {
        [skin logError:[NSString stringWithFormat:@"expected %s object, found %s", USERDATA_TAG,
                                                   lua_typename(L, lua_type(L, idx))]] ;
    }
    return value ;
}

#pragma mark - Hammerspoon/Lua Infrastructure

static int userdata_tostring(lua_State* L) {
    LuaSkin *skin = [LuaSkin threaded] ;
//     LuaSkin *obj = [skin luaObjectAtIndex:1 toClass:"LuaSkin"] ;
    [skin pushNSObject:[NSString stringWithFormat:@"%s: (%p)", USERDATA_TAG, lua_topointer(L, 1)]] ;
    return 1 ;
}

static int userdata_eq(lua_State* L) {
// can't get here if at least one of us isn't a userdata type, and we only care if both types are ours,
// so use luaL_testudata before the macro causes a lua error
    if (luaL_testudata(L, 1, USERDATA_TAG) && luaL_testudata(L, 2, USERDATA_TAG)) {
        LuaSkin *skin = [LuaSkin threaded] ;
        LuaSkin *obj1 = [skin luaObjectAtIndex:1 toClass:"LuaSkin"] ;
        LuaSkin *obj2 = [skin luaObjectAtIndex:2 toClass:"LuaSkin"] ;
        lua_pushboolean(L, [obj1 isEqualTo:obj2]) ;
    } else {
        lua_pushboolean(L, NO) ;
    }
    return 1 ;
}

static int userdata_gc(lua_State* L) {
    LuaSkin *obj = get_objectFromUserdata(__bridge_transfer LuaSkin, L, 1, USERDATA_TAG) ;
    if (obj) obj = nil ;
    lua_pushnil(L) ;
    lua_setmetatable(L, 1) ;
    return 0 ;
}

// Metatable for userdata objects
static const luaL_Reg userdata_metaLib[] = {
    {"onMainThread",        skin_onMainThread},
    {"onThisThread",        skin_onThisThread},
    {"refTableIndexes",     skin_refTableReferences},
    {"nsHelperFunctions",   skin_NSHelperFunctions},
    {"nsHelperLocations",   skin_NSHelperLocations},
    {"luaHelperFunctions",  skin_LuaObjectHelperFunctions},
    {"luaHelperLocations",  skin_LuaObjectHelperLocations},
    {"luaUserdataMappings", skin_LuaObjectHelperUserdataMappings},
    {"luaTableMappings",    skin_LuaObjectHelperTableMappings},

    {"__tostring",          userdata_tostring},
    {"__eq",                userdata_eq},
    {"__gc",                userdata_gc},
    {NULL,                  NULL}
};

// // Functions for returned object when module loads
// static luaL_Reg moduleLib[] = {
//     {NULL,   NULL}
// };

int luaopen_hs_luathread_luaskin_skin(lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin registerObject:USERDATA_TAG objectFunctions:userdata_metaLib];

    [skin registerPushNSHelper:pushLuaSkin         forClass:"LuaSkin"];
    [skin registerLuaObjectHelper:toLuaSkinFromLua forClass:"LuaSkin"
                                        withUserdataMapping:USERDATA_TAG];

    // we're returning only a function, since it's the only one... and this module can
    // stand alone -- it's in hs.luathread.luaskin because it's conceptually most useful
    // for debugging hs.luathread.luaskin, but it doesn't really require any of it.
    lua_pushcfunction(L, skin_currentLuaSkin) ;
    return 1;
}
