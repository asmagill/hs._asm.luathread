#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import <LuaSkin/LuaSkin.h>
#import "../../LuaSkinThread.h"

/// === hs.fs.volume ===
///
/// Interact with OS X filesystem volumes
///
/// This is distinct from hs.fs in that hs.fs deals with UNIX filesystem operations, while hs.fs.volume interacts with the higher level OS X concept of volumes


/// hs.fs.volume.didMount
/// Constant
/// A volume was mounted

/// hs.fs.volume.didUnmount
/// Constant
/// A volume was unmounted

/// hs.fs.volume.willUnmount
/// Constant
/// A volume is about to be unmounted

/// hs.fs.volume.didRename
/// Constant
/// A volume changed either its name or mountpoint (or more likely, both)

// Common Code

#define USERDATA_TAG "hs.fs.volume"
// Modules which support luathread have to store refTable in the threadDictionary rather than a static,
// but we can keep this around, since the macros defined in LuaSkinThread.h will expect it when a module
// is written to seamlessly work in both environments
static int refTable = LUA_NOREF;

// Not so common code

typedef struct _VolumeWatcher_t {
    bool running;
    int fn;
    void* obj;
} VolumeWatcher_t;

typedef enum _event_t {
    didMount = 0,
    didUnmount,
    willUnmount,
    didRename,
} event_t;

@interface LST_VolumeWatcher : NSObject
@property VolumeWatcher_t* object;
@property NSThread       *myMainThread ;

- (id)initWithObject:(VolumeWatcher_t*)object;
@end

@implementation LST_VolumeWatcher
- (id)initWithObject:(VolumeWatcher_t*)object {
    if (self = [super init]) {
        _object = object;
        _myMainThread = [NSThread currentThread] ;
    }
    return self;
}

// Call the lua callback function and pass the application name and event type.
- (void)callback:(NSDictionary *)dict withEvent:(event_t)event {
    LuaSkin *skin = LST_getLuaSkin(); //[LuaSkin shared] ;
    lua_State *L = skin.L;

    [skin pushLuaRef:LST_getRefTable(skin, USERDATA_TAG, refTable) ref:self.object->fn];
    lua_pushinteger(L, event); // Parameter 1: the event type

    NSMutableDictionary *tableArg = [[NSMutableDictionary alloc] init];

    switch (event) {
        case didMount:
        case didUnmount:
        case willUnmount:
            [tableArg setObject:[dict objectForKey:@"NSDevicePath"] forKey:@"path"];
            break;

        case didRename:
            [tableArg setObject:[dict objectForKey:NSWorkspaceVolumeURLKey] forKey:@"path"];
            [tableArg setObject:[dict objectForKey:NSWorkspaceVolumeLocalizedNameKey] forKey:@"name"];
            [tableArg setObject:[dict objectForKey:NSWorkspaceVolumeOldURLKey] forKey:@"oldPath"];
            [tableArg setObject:[dict objectForKey:NSWorkspaceVolumeOldLocalizedNameKey] forKey:@"oldName"];
            break;

        default:
            break;
    }

    [skin pushNSObject:tableArg];

    if (![skin protectedCallAndTraceback:2 nresults:0]) {
        const char *errorMsg = lua_tostring(L, -1);
        [skin logError:[NSString stringWithFormat:@"hs.fs.volume callback error: %s", errorMsg]];
    }
}

- (void)onProperThread:(NSDictionary *)arguments {
    [self callback:[arguments  objectForKey:@"dict"]
         withEvent:[[arguments objectForKey:@"event"] unsignedIntValue]];
}

- (void)volumeDidMount:(NSNotification*)notification {
    [self performSelector:@selector(onProperThread:)
                 onThread:_myMainThread
               withObject:@{
                              @"dict"  : [notification userInfo] ? [notification userInfo] : [NSNull null],
                              @"event" : @(didMount)
                          }
            waitUntilDone:YES];
//     [self callback:[notification userInfo] withEvent:didMount];
}

- (void)volumeDidUnmount:(NSNotification*)notification {
    [self performSelector:@selector(onProperThread:)
                 onThread:_myMainThread
               withObject:@{
                              @"dict"  : [notification userInfo] ? [notification userInfo] : [NSNull null],
                              @"event" : @(didUnmount)
                          }
            waitUntilDone:YES];
//     [self callback:[notification userInfo] withEvent:didUnmount];
}

- (void)volumeWillUnmount:(NSNotification*)notification {
    [self performSelector:@selector(onProperThread:)
                 onThread:_myMainThread
               withObject:@{
                              @"dict"  : [notification userInfo] ? [notification userInfo] : [NSNull null],
                              @"event" : @(willUnmount)
                          }
            waitUntilDone:YES];
//     [self callback:[notification userInfo]  withEvent:willUnmount];
}

- (void)volumeDidRename:(NSNotification*)notification {
    [self performSelector:@selector(onProperThread:)
                 onThread:_myMainThread
               withObject:@{
                              @"dict"  : [notification userInfo] ? [notification userInfo] : [NSNull null],
                              @"event" : @(didRename)
                          }
            waitUntilDone:YES];
//     [self callback:[notification userInfo] withEvent:didRename];
}

@end

/// hs.fs.volume.eject(path) -> boolean
/// Function
/// Unmounts and ejects a volume
///
/// Parameters:
///  * path - An absolute path to the volume you wish to eject
///
/// Returns:
///  * A boolean, true if the volume was ejected, otherwise false
static int volume_eject(lua_State *L) {
    LuaSkin *skin = LST_getLuaSkin(); //[LuaSkin shared] ;
    [skin checkArgs:LS_TSTRING, LS_TBREAK];

    NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
    BOOL result = [workspace unmountAndEjectDeviceAtPath:[skin toNSObjectAtIndex:1]];

    lua_pushboolean(L, result);
    return 1;
}

/// hs.fs.volume.new(fn) -> watcher
/// Constructor
/// Creates a watcher object for volume events
///
/// Parameters:
///  * fn - A function that will be called when volume events happen. It should accept two parameters:
///   * An event type (see the constants defined above)
///   * A table that will contain relevant information
///
/// Returns:
///  * An `hs.fs.volume` object
static int volume_watcher_new(lua_State* L) {
    LuaSkin *skin = LST_getLuaSkin(); //[LuaSkin shared] ;
    [skin checkArgs:LS_TFUNCTION, LS_TBREAK];

    VolumeWatcher_t* watcher = lua_newuserdata(L, sizeof(VolumeWatcher_t));
    memset(watcher, 0, sizeof(VolumeWatcher_t));

    lua_pushvalue(L, 1);
    watcher->fn = [skin luaRef:LST_getRefTable(skin, USERDATA_TAG, refTable)];
    watcher->running = NO;
    watcher->obj = (__bridge_retained void*) [[LST_VolumeWatcher alloc] initWithObject:watcher];

    luaL_getmetatable(L, USERDATA_TAG);
    lua_setmetatable(L, -2);
    return 1;
}

// Register the VolumeWatcher as observer for application specific events.
static void register_observer(LST_VolumeWatcher* observer) {
    // It is crucial to use the shared workspace notification center here.
    // Otherwise the will not receive the events we are interested in.
    NSNotificationCenter* center = [[NSWorkspace sharedWorkspace] notificationCenter];
    [center addObserver:observer
               selector:@selector(volumeDidMount:)
                   name:NSWorkspaceDidMountNotification
                 object:nil];
    [center addObserver:observer
               selector:@selector(volumeDidUnmount:)
                   name:NSWorkspaceDidUnmountNotification
                 object:nil];
    [center addObserver:observer
               selector:@selector(volumeWillUnmount:)
                   name:NSWorkspaceWillUnmountNotification
                 object:nil];
    [center addObserver:observer
               selector:@selector(volumeDidRename:)
                   name:NSWorkspaceDidRenameVolumeNotification
                 object:nil];
}

// Unregister the VolumeWatcher as observer for all events.
static void unregister_observer(LST_VolumeWatcher* observer) {
    NSNotificationCenter* center = [[NSWorkspace sharedWorkspace] notificationCenter];
    [center removeObserver:observer name:NSWorkspaceDidMountNotification object:nil];
    [center removeObserver:observer name:NSWorkspaceDidUnmountNotification object:nil];
    [center removeObserver:observer name:NSWorkspaceWillUnmountNotification object:nil];
    [center removeObserver:observer name:NSWorkspaceDidRenameVolumeNotification object:nil];
}

/// hs.fs.volume:start()
/// Method
/// Starts the volume watcher
///
/// Parameters:
///  * None
///
/// Returns:
///  * An `hs.fs.volume` object
static int volume_watcher_start(lua_State* L) {
    LuaSkin *skin = LST_getLuaSkin(); //[LuaSkin shared] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK];

    VolumeWatcher_t* watcher = lua_touserdata(L, 1);
    lua_settop(L, 1);

    if (watcher->running)
        return 1;

    watcher->running = YES;
    register_observer((__bridge LST_VolumeWatcher*)watcher->obj);
    return 1;
}

/// hs.fs.volume:stop()
/// Method
/// Stops the volume watcher
///
/// Parameters:
///  * None
///
/// Returns:
///  * An `hs.fs.volume` object
static int volume_watcher_stop(lua_State* L) {
    LuaSkin *skin = LST_getLuaSkin(); //[LuaSkin shared] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK];

    VolumeWatcher_t* watcher = lua_touserdata(L, 1);
    lua_settop(L, 1);

    if (!watcher->running)
        return 1;

    watcher->running = NO;
    unregister_observer((__bridge id)watcher->obj);
    return 1;
}

// Perform cleanup if the VolumeWatcher is not required anymore.
static int volume_watcher_gc(lua_State* L) {
    LuaSkin *skin = LST_getLuaSkin(); //[LuaSkin shared] ;

    VolumeWatcher_t* watcher = luaL_checkudata(L, 1, USERDATA_TAG);

    volume_watcher_stop(L);

    watcher->fn = [skin luaUnref:LST_getRefTable(skin, USERDATA_TAG, refTable) ref:watcher->fn];

    LST_VolumeWatcher* object = (__bridge_transfer LST_VolumeWatcher*)watcher->obj;
    object = nil;
    return 0;
}

static int userdata_tostring(lua_State* L) {
    lua_pushstring(L, [[NSString stringWithFormat:@"%s: (%p)", USERDATA_TAG, lua_topointer(L, 1)] UTF8String]) ;
    return 1 ;
}

static int meta_gc(lua_State* __unused L) {
    return 0;
}

// Add a single event enum value to the lua table.
static void add_event_value(lua_State* L, event_t value, const char* name) {
    lua_pushinteger(L, value);
    lua_setfield(L, -2, name);
}

// Add the event_t enum to the lua table.
static void add_event_enum(lua_State* L) {
    add_event_value(L, didMount, "didMount");
    add_event_value(L, didUnmount, "didUnmount");
    add_event_value(L, willUnmount, "willUnmount");
    add_event_value(L, didRename, "didRename");
}

// Metatable for created objects when _new invoked
static const luaL_Reg metaLib[] = {
    {"start",   volume_watcher_start},
    {"stop",    volume_watcher_stop},
    {"__gc",    volume_watcher_gc},
    {"__tostring", userdata_tostring},
    {NULL,      NULL}
};

// Functions for returned object when module loads
static const luaL_Reg appLib[] = {
    {"new",     volume_watcher_new},
    {"eject",   volume_eject},
    {NULL,      NULL}
};

// Metatable for returned object when module loads
static const luaL_Reg metaGcLib[] = {
    {"__gc",    meta_gc},
    {NULL,      NULL}
};

// Called when loading the module. All necessary tables need to be registered here.
int luaopen_hs_fs_volume(lua_State* L __unused) {
    LuaSkin *skin = LST_getLuaSkin(); //[LuaSkin shared] ;

    LST_setRefTable(skin, USERDATA_TAG, refTable,
        [skin registerLibraryWithObject:USERDATA_TAG
                              functions:appLib
                          metaFunctions:metaGcLib
                        objectFunctions:metaLib]) ;

    add_event_enum(skin.L);

    return 1;
}


