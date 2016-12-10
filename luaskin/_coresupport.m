@import Cocoa ;
@import LuaSkin ;
#import "../LuaSkin+threaded.h"

#pragma mark - Support Functions and Classes

#pragma mark * MJUserNotificationManager.h
@interface MJUserNotificationManager : NSObject

+ (MJUserNotificationManager*) sharedManager;

- (void) sendNotification:(NSString*)title handler:(dispatch_block_t)handler;

@end

#pragma mark * MJConsoleWindowController.h
@interface MJConsoleWindowController : NSWindowController

+ (instancetype) singleton;
- (void) setup;

#pragma mark - NSTextFieldDelegate
- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command;
@end

#pragma mark - MJPreferencesWindowController.h
@interface MJPreferencesWindowController : NSWindowController

+ (instancetype) singleton;

@end

extern BOOL MJConsoleWindowAlwaysOnTop(void);
extern void MJConsoleWindowSetAlwaysOnTop(BOOL alwaysOnTop);

#pragma mark * MJAccessibility.h
extern BOOL MJAccessibilityIsEnabled(void);
extern void MJAccessibilityOpenPanel(void);

#pragma mark * MJAutoLaunch.h
extern BOOL MJAutoLaunchGet(void);
extern void MJAutoLaunchSet(BOOL opensAtLogin);

#pragma mark * MJMenuIcon.h
extern void MJMenuIconSetup(NSMenu* menu);
extern BOOL MJMenuIconVisible(void);
extern void MJMenuIconSetVisible(BOOL visible);

#pragma mark - Module Functions

static int core_consoleontop(lua_State* L) {
    if (lua_isboolean(L, -1)) { MJConsoleWindowSetAlwaysOnTop((BOOL)lua_toboolean(L, -1)); }
    lua_pushboolean(L, MJConsoleWindowAlwaysOnTop()) ;
    return 1;
}

static int core_openabout(lua_State* __unused L) {
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
    [[NSApplication sharedApplication] performSelectorOnMainThread:@selector(orderFrontStandardAboutPanel:)
                                                        withObject:nil
                                                     waitUntilDone:NO];
    return 0;
}

static int core_openpreferences(lua_State* __unused L) {
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
    [[MJPreferencesWindowController singleton] performSelectorOnMainThread:@selector(showWindow:)
                                                                withObject:nil
                                                             waitUntilDone:NO];

    return 0 ;
}

static int core_getObjectMetatable(lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TSTRING, LS_TBREAK];
    luaL_getmetatable(L, lua_tostring(L,1));
    return 1;
}

static int core_cleanUTF8(__unused lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TANY, LS_TBREAK] ;
    [skin pushNSObject:[skin getValidUTF8AtIndex:1]] ;
    return 1 ;
}

static int core_openconsole(lua_State* L) {
    if (!(lua_isboolean(L,1) && !lua_toboolean(L, 1))) {
        [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
    }
    [[MJConsoleWindowController singleton] performSelectorOnMainThread:@selector(showWindow:)
                                                            withObject:nil
                                                         waitUntilDone:NO];
    return 0;
}

static int core_focus(__unused lua_State* L) {
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
    return 0;
}

static int core_notify(lua_State* L) {
    size_t len;
    const char* s = lua_tolstring(L, 1, &len);
    NSString* str = [[NSString alloc] initWithData:[NSData dataWithBytes:s length:len] encoding:NSUTF8StringEncoding];
    [[MJUserNotificationManager sharedManager] sendNotification:str handler:^{
        [[MJConsoleWindowController singleton] showWindow: nil];
    }];
    return 0;
}

static int core_accessibilityState(lua_State* L) {
    BOOL shouldprompt = (BOOL)lua_toboolean(L, 1);
    BOOL enabled = MJAccessibilityIsEnabled();
    if (shouldprompt && !enabled) {
        dispatch_async(dispatch_get_main_queue(), ^{
            MJAccessibilityOpenPanel();
        }) ;
    }
    lua_pushboolean(L, enabled);
    return 1;
}

static int core_autolaunch(lua_State* L) {
    if (lua_isboolean(L, -1)) { MJAutoLaunchSet((BOOL)lua_toboolean(L, -1)); }
    lua_pushboolean(L, MJAutoLaunchGet()) ;
    return 1;
}

static int core_menuicon(lua_State* L) {
    if (lua_isboolean(L, -1)) { MJMenuIconSetVisible((BOOL)lua_toboolean(L, -1)); }
    lua_pushboolean(L, MJMenuIconVisible()) ;
    return 1;
}

static int automaticallyChecksForUpdates(lua_State* L) {
    [[LuaSkin threaded] logWarn:@"hs.automaticallyChecksForUpdates not available outside main thread"] ;
    lua_pushboolean(L, NO) ;
    return 1 ;
}

static int checkForUpdates(__unused lua_State* L) {
    [[LuaSkin threaded] logWarn:@"hs.checkForUpdates not available outside main thread"] ;
    return 0 ;
}

static int canCheckForUpdates(lua_State *L) {
    [[LuaSkin threaded] logWarn:@"hs.canCheckForUpdates not available outside main thread"] ;
    lua_pushboolean(L, NO) ;
    return 1 ;
}

#pragma mark - Module Constants

#pragma mark - Hammerspoon/Lua Infrastructure

// static int meta_gc(lua_State* __unused L) {
//     return 0 ;
// }

// Functions for returned object when module loads
static luaL_Reg moduleLib[] = {
    {"openConsole", core_openconsole},
    {"consoleOnTop", core_consoleontop},
    {"openAbout", core_openabout},
    {"menuIcon", core_menuicon},
    {"openPreferences", core_openpreferences},
    {"autoLaunch", core_autolaunch},
    {"automaticallyCheckForUpdates", automaticallyChecksForUpdates},
    {"checkForUpdates", checkForUpdates},
    {"canCheckForUpdates", canCheckForUpdates},
//     {"reload", core_reload},                 // defined in _threadinit.lua
    {"focus", core_focus},
    {"accessibilityState", core_accessibilityState},
    {"getObjectMetatable", core_getObjectMetatable},
    {"cleanUTF8forConsole", core_cleanUTF8},
//     {"_exit", core_exit},                    // defined in _threadinit.lua
//     {"_logmessage", core_logmessage},        // defined in _threadinit.lua
    {"_notify", core_notify},
    {NULL, NULL}
};

// // Metatable for module, if needed
// static const luaL_Reg module_metaLib[] = {
//     {"__gc", meta_gc},
//     {NULL,   NULL}
// };

// NOTE: ** Make sure to change luaopen_..._internal **
int luaopen_hs__asm_luathread_luaskin__coresupport(lua_State* __unused L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin registerLibrary:moduleLib metaFunctions:nil] ; // or module_metaLib
    return 1;
}
