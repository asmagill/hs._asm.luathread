#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CGWindow.h>
#import <LuaSkin/LuaSkin.h>
#import "../../LuaSkinThread.h"

/// === hs.spaces.watcher ===
///
/// Watches for the current Space being changed
/// NOTE: This extension determines the number of a Space, using OS X APIs that have been deprecated since 10.8 and will likely be removed in a future release. You should not depend on Space numbers being around forever!

#define USERDATA_TAG "hs.spaces.watcher"
int refTable;

typedef struct _spacewatcher_t {
    int self;
    bool running;
    int fn;
    void* obj;
} spacewatcher_t;

@interface LST_SpaceWatcher : NSObject
@property        spacewatcher_t* object;
@property (weak) NSThread      *myMainThread ;

- (id)initWithObject:(spacewatcher_t*)object;
@end

@implementation LST_SpaceWatcher
- (id)initWithObject:(spacewatcher_t*)object {
    if (self = [super init]) {
        _object       = object;
        _myMainThread = [NSThread currentThread] ;
    }
    return self;
}

// Call the lua callback function.
- (void)callback:(NSDictionary* __unused)dict withSpace:(int)space {
    LuaSkin *skin = LST_getLuaSkin();
    lua_State *L = skin.L;

    [skin pushLuaRef:LST_getRefTable(skin, USERDATA_TAG, refTable) ref:self.object->fn];
    lua_pushinteger(L, space);

    if (![skin protectedCallAndTraceback:1 nresults:0]) {
        const char *errorMsg = lua_tostring(L, -1);
        [skin logError:[NSString stringWithFormat:@"hs.spaces.watcher callback error: %s", errorMsg]];
    }
}

- (void) _spaceChanged:(id)notification {
    [self performSelector:@selector(spaceChanged:)
                 onThread:_myMainThread
               withObject:notification
            waitUntilDone:YES];
}

- (void)spaceChanged:(NSNotification*)notification {
    int currentSpace = -1;
    // Get an array of all the windows in the current space.
    NSArray *windowsInSpace = (__bridge_transfer NSArray *)CGWindowListCopyWindowInfo(kCGWindowListOptionAll | kCGWindowListOptionOnScreenOnly, kCGNullWindowID);

    // Now loop over the array looking for a window with the kCGWindowWorkspace key.
    for (NSMutableDictionary *thisWindow in windowsInSpace) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        if ([thisWindow objectForKey:(id)kCGWindowWorkspace]) {
            currentSpace = [[thisWindow objectForKey:(id)kCGWindowWorkspace] intValue];
#pragma clang diagnostic pop
            break;
        }
    }

    [self callback:[notification userInfo] withSpace:currentSpace];
}
@end

/// hs.spaces.watcher.new(handler) -> watcher
/// Constructor
/// Creates a new watcher for Space change events
///
/// Parameters:
///  * handler - A function to be called when the active Space changes. It should accept one argument, which will be the number of the new Space (or -1 if the number cannot be determined)
///
/// Returns:
///  * An `hs.spaces.watcher` object
static int space_watcher_new(lua_State* L) {
    LuaSkin *skin = LST_getLuaSkin();

    luaL_checktype(L, 1, LUA_TFUNCTION);

    spacewatcher_t* spaceWatcher = lua_newuserdata(L, sizeof(spacewatcher_t));

    lua_pushvalue(L, 1);
    spaceWatcher->fn = [skin luaRef:LST_getRefTable(skin, USERDATA_TAG, refTable)];
    spaceWatcher->running = NO;
    spaceWatcher->obj = (__bridge_retained void*) [[LST_SpaceWatcher alloc] initWithObject:spaceWatcher];

    luaL_getmetatable(L, USERDATA_TAG);
    lua_setmetatable(L, -2);
    return 1;
}

/// hs.spaces.watcher:start()
/// Method
/// Starts the Spaces watcher
///
/// Parameters:
///  * None
///
/// Returns:
///  * The watcher object
static int space_watcher_start(lua_State* L) {
    LuaSkin *skin = LST_getLuaSkin();

    spacewatcher_t* spaceWatcher = luaL_checkudata(L, 1, USERDATA_TAG);
    lua_settop(L, 1);
    lua_pushvalue(L, 1);

    if (spaceWatcher->running)
        return 1;

    spaceWatcher->self = [skin luaRef:LST_getRefTable(skin, USERDATA_TAG, refTable)];
    spaceWatcher->running = YES;

    NSNotificationCenter* center = [[NSWorkspace sharedWorkspace] notificationCenter];
    LST_SpaceWatcher* observer = (__bridge LST_SpaceWatcher*)spaceWatcher->obj;
    [center addObserver:observer
               selector:@selector(_spaceChanged:)
                   name:NSWorkspaceActiveSpaceDidChangeNotification
                 object:nil];

    lua_pushvalue(L, 1);
    return 1;
}

/// hs.spaces.watcher:stop()
/// Method
/// Stops the Spaces watcher
///
/// Parameters:
///  * None
///
/// Returns:
///  * The watcher object
static int space_watcher_stop(lua_State* L) {
    spacewatcher_t* spaceWatcher = luaL_checkudata(L, 1, USERDATA_TAG);
    lua_settop(L, 1);
    lua_pushvalue(L, 1);

    if (!spaceWatcher->running)
        return 1;

    spaceWatcher->running = NO;
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:(__bridge LST_SpaceWatcher*)spaceWatcher->obj];
    return 1;
}

static int space_watcher_gc(lua_State* L) {
    LuaSkin *skin = LST_getLuaSkin();

    spacewatcher_t* spaceWatcher = luaL_checkudata(L, 1, USERDATA_TAG);

    space_watcher_stop(L);

    spaceWatcher->fn = [skin luaUnref:LST_getRefTable(skin, USERDATA_TAG, refTable) ref:spaceWatcher->fn];

    LST_SpaceWatcher* object = (__bridge_transfer LST_SpaceWatcher*)spaceWatcher->obj;
    object = nil;
    return 0;
}

static int userdata_tostring(lua_State* L) {
    lua_pushstring(L, [[NSString stringWithFormat:@"%s: (%p)", USERDATA_TAG, lua_topointer(L, 1)] UTF8String]) ;
    return 1 ;
}

static const luaL_Reg watcherlib[] = {
    {"new", space_watcher_new},
    {NULL, NULL}
};

static const luaL_Reg watcher_objectlib[] = {
    {"start", space_watcher_start},
    {"stop", space_watcher_stop},
    {"__tostring", userdata_tostring},
    {"__gc", space_watcher_gc},
    {NULL, NULL}
};

int luaopen_hs_spaces_watcher(lua_State* L __unused) {
    LuaSkin *skin = LST_getLuaSkin();
    LST_setRefTable(skin, USERDATA_TAG, refTable,
        [skin registerLibraryWithObject:USERDATA_TAG functions:watcherlib metaFunctions:nil objectFunctions:watcher_objectlib]);

    return 1;
}
