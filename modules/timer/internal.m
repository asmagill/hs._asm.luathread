@import Cocoa;
@import Darwin.POSIX.sys.time;
#import <LuaSkin/LuaSkin.h>
#import "../../LuaSkinThread.h"

// Common Code

static const char *USERDATA_TAG = "hs.timer";
static int refTable;

// Not so common code

typedef struct _timerUserData {
    CFRunLoopTimerRef t;
    int fn;
    BOOL started;
    BOOL continueOnError;
} timerUserData;

static void timerCallback(CFRunLoopTimerRef __unused timer, void *info) {
    timerUserData* t = info;

    LuaSkin *skin = LST_getLuaSkin(); //[LuaSkin shared] ;
    lua_State *L = skin.L;

    if (!t) {
        [skin logWarn:@"hs.timer callback fired on an invalid hs.timer object. This is a bug"];
        return;
    }

    [skin pushLuaRef:LST_getRefTable(skin, USERDATA_TAG, refTable) ref:t->fn];
    if (![skin protectedCallAndTraceback:0 nresults:0]) {
        const char *errorMsg = lua_tostring(L, -1);
        [skin logError:[NSString stringWithFormat:@"hs.timer callback error: %s", errorMsg]];
        if (!t->continueOnError) {
            CFRunLoopRemoveTimer(CFRunLoopGetCurrent(), t->t, kCFRunLoopCommonModes);
            [skin logWarn:@"hs.timer callback failed. The timer has been stopped to prevent repeated notifications of the error."];
        }
    }

}

/// hs.timer.new(interval, fn [, continueOnError]) -> timer
/// Constructor
/// Creates a new `hs.timer` object for repeating interval callbacks
///
/// Parameters:
///  * interval - A number of seconds between triggers
///  * fn - A function to call every time the timer triggers
///  * continueOnError - an optional boolean flag, defaulting to false, which indicates that the timer should not be automatically stopped if the callback function results in an error.
///
/// Returns:
///  * An `hs.timer` object
///
/// Notes:
///  * The returned object does not start its timer until its `:start()` method is called
///  * If the callback function results in an error, the timer will be stopped to prevent repeated error notifications.  This can be overriden for this constructor by passing in true for continueOnError.
static int timer_new(lua_State* L) {
    LuaSkin *skin = LST_getLuaSkin(); //[LuaSkin shared] ;
    [skin checkArgs:LS_TNUMBER, LS_TFUNCTION, LS_TBOOLEAN | LS_TNIL | LS_TOPTIONAL, LS_TBREAK];

    NSTimeInterval sec = lua_tonumber(L, 1);

    timerUserData* timer = lua_newuserdata(L, sizeof(timerUserData));
    memset(timer, 0, sizeof(timerUserData));

    lua_pushvalue(L, 2);
    timer->fn = [skin luaRef:LST_getRefTable(skin, USERDATA_TAG, refTable)];
    if (lua_isboolean(L, 3))
        timer->continueOnError = (BOOL)lua_toboolean(L, 3) ;
    else
        timer->continueOnError = NO ;

    luaL_getmetatable(L, USERDATA_TAG);
    lua_setmetatable(L, -2);

    CFRunLoopTimerContext ctx = {0, timer, NULL, NULL, NULL};
//    ctx.info = timer;
    timer->t = CFRunLoopTimerCreate(NULL, 0, sec, 0, 0, timerCallback, &ctx);

    return 1;
}

/// hs.timer:start() -> timer
/// Method
/// Starts an `hs.timer` object
///
/// Parameters:
///  * None
///
/// Returns:
///  * The `hs.timer` object
///
/// Notes:
///  * The timer will not call the callback immediately, it waits until the first trigger of the timer
///  * If the callback function results in an error, the timer will be stopped to prevent repeated error notifications.
static int timer_start(lua_State* L) {
    LuaSkin *skin = LST_getLuaSkin(); //[LuaSkin shared] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK];

    timerUserData* timer = lua_touserdata(L, 1);
    lua_settop(L, 1);

    if (timer->started) return 1;
    timer->started = YES;

    CFRunLoopTimerSetNextFireDate(timer->t, CFAbsoluteTimeGetCurrent() + CFRunLoopTimerGetInterval(timer->t));
    CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer->t, kCFRunLoopCommonModes);
    return 1;
}

/// hs.timer.doAfter(sec, fn) -> timer
/// Constructor
/// Calls a function after a delay
///
/// Parameters:
///  * sec - A number of seconds to wait before calling the function
///  * fn - The function to call
///
/// Returns:
///  * An `hs.timer` object
///
/// Notes:
///  * The callback can be cancelled by calling the `:stop()` method on the returned object before `sec` seconds have passed.
///  * If the callback function results in an error, the timer will be stopped to prevent repeated error notifications.
static int timer_doAfter(lua_State* L) {
    LuaSkin *skin = LST_getLuaSkin(); //[LuaSkin shared] ;
    [skin checkArgs:LS_TNUMBER, LS_TFUNCTION, LS_TBREAK];

    NSTimeInterval sec = lua_tonumber(L, 1);

    timerUserData* timer = lua_newuserdata(L, sizeof(timerUserData));
    memset(timer, 0, sizeof(timerUserData));

    lua_pushvalue(L, 2);
    timer->fn = [skin luaRef:LST_getRefTable(skin, USERDATA_TAG, refTable)];

    luaL_getmetatable(L, USERDATA_TAG);
    lua_setmetatable(L, -2);

    CFRunLoopTimerContext ctx = {0, timer, NULL, NULL, NULL};
//    ctx.info = timer;
    timer->t = CFRunLoopTimerCreate(NULL, 0, 0, 0, 0, timerCallback, &ctx);
    timer->started = YES;

    CFRunLoopTimerSetNextFireDate(timer->t, CFAbsoluteTimeGetCurrent() + sec);
    CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer->t, kCFRunLoopCommonModes);
    return 1;
}

/// hs.timer.usleep(microsecs)
/// Function
/// Blocks Lua execution for the specified time
///
/// Parameters:
///  * microsecs - A number containing a time in microseconds to block for
///
/// Returns:
///  * None
///
/// Notes:
///  * Use of this function is strongly discouraged, as it blocks all main-thread execution in Hammerspoon. This means no hotkeys or events will be processed in that time. This is only provided as a last resort, or for extremely short sleeps. For all other purposes, you really should be splitting up your code into multiple functions and calling `hs.timer.doAfter()`
static int timer_usleep(lua_State* L) {
    LuaSkin *skin = LST_getLuaSkin(); //[LuaSkin shared] ;
    [skin checkArgs:LS_TNUMBER, LS_TBREAK];
    useconds_t microsecs = (useconds_t)lua_tointeger(L, 1);
    usleep(microsecs);

    return 0;
}

/// hs.timer:running() -> boolean
/// Method
/// Returns a boolean indicating whether or not the timer is currently running.
///
/// Parameters:
///  * None
///
/// Returns:
///  * A boolean value indicating whether or not the timer is currently running.
static int timer_running(lua_State* L) {
    LuaSkin *skin = LST_getLuaSkin(); //[LuaSkin shared] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK];
    timerUserData* timer = lua_touserdata(L, 1);

    lua_pushboolean(L, CFRunLoopContainsTimer(CFRunLoopGetCurrent(), timer->t, kCFRunLoopCommonModes));
    return 1;
}

/// hs.timer:nextTrigger() -> number
/// Method
/// Returns the number of seconds until the timer will next trigger
///
/// Parameters:
///  * None
///
/// Returns:
///  * A number containing the number of seconds until the next firing.
///
/// Notes:
///  * The return value may be a negative integer in two circumstances:
///   * Hammerspoon's runloop is backlogged and is catching up on missed timer triggers
///   * The timer object is not currently running. In this case, the return value of this method is the number of seconds since the last firing (you can check if the timer is running or not, with `hs.timer:running()`
static int timer_nextTrigger(lua_State *L) {
    LuaSkin *skin = LST_getLuaSkin(); //[LuaSkin shared] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK];
    timerUserData* timer = lua_touserdata(L, 1);

    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    CFAbsoluteTime next = CFRunLoopTimerGetNextFireDate(timer->t);

    lua_pushnumber(L, next - now);

    return 1;
}

/// hs.timer:setNextTrigger(seconds) -> timer
/// Method
/// Sets the next trigger time of a timer
///
/// Parameters:
///  * seconds - A number containing the number of seconds after which to trigger the timer
///
/// Returns:
///  * The `hs.timer` object
static int timer_setNextTrigger(lua_State *L) {
    LuaSkin *skin = LST_getLuaSkin(); //[LuaSkin shared] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TNUMBER, LS_TBREAK];
    timerUserData* timer = lua_touserdata(L, 1);
    double seconds = lua_tonumber(L, 2);

    CFRunLoopTimerSetNextFireDate(timer->t, CFAbsoluteTimeGetCurrent() + seconds);

    lua_pushvalue(L, 1);
    return 1;
}

/// hs.timer:stop() -> timer
/// Method
/// Stops an `hs.timer` object
///
/// Parameters:
///  * None
///
/// Returns:
///  * The `hs.timer` object
static int timer_stop(lua_State* L) {
    LuaSkin *skin = LST_getLuaSkin(); //[LuaSkin shared] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK];
    timerUserData* timer = lua_touserdata(L, 1);
    lua_settop(L, 1);

    if (!timer->started) return 1;
    timer->started = NO;

    CFRunLoopRemoveTimer(CFRunLoopGetCurrent(), timer->t, kCFRunLoopCommonModes);
    return 1;
}

static int timer_gc(lua_State* L) {
    LuaSkin *skin = LST_getLuaSkin(); //[LuaSkin shared] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK];
    timerUserData* timer = lua_touserdata(L, 1);

    if (timer) {
        timer->fn = [skin luaUnref:LST_getRefTable(skin, USERDATA_TAG, refTable) ref:timer->fn];

        timer->started = NO;

        if (CFRunLoopContainsTimer(CFRunLoopGetCurrent(), timer->t, kCFRunLoopCommonModes)) {
            CFRunLoopRemoveTimer(CFRunLoopGetCurrent(), timer->t, kCFRunLoopCommonModes);
        }

        if (CFRunLoopTimerIsValid(timer->t)) {
            CFRunLoopTimerInvalidate(timer->t);
        }

        CFRelease(timer->t);
        timer->t = nil;
        timer = nil;
    }

    return 0;
}

static int meta_gc(lua_State* __unused L) {
    return 0;
}

static int userdata_tostring(lua_State* L) {
    LuaSkin *skin = LST_getLuaSkin(); //[LuaSkin shared] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK];
    timerUserData* timer = lua_touserdata(L, 1);
    NSString* title ;

    if (!timer->t || !CFRunLoopTimerIsValid(timer->t)) {
        title = @"invalid";
    } else if (CFRunLoopContainsTimer(CFRunLoopGetCurrent(), timer->t, kCFRunLoopCommonModes)) {
        title = @"running";
    } else {
        title = @"stopped";
    }

    lua_pushstring(L, [[NSString stringWithFormat:@"%s: %@ (%p)", USERDATA_TAG, title, lua_topointer(L, 1)] UTF8String]) ;
    return 1 ;
}

/// hs.timer.secondsSinceEpoch() -> sec
/// Function
/// Gets the number of seconds since the UNIX epoch (January 1, 1970), including the fractional part; this has much better precision than `os.time()`, which is limited to whole seconds.
///
/// Parameters:
///  * None
///
/// Returns:
///  * The number of seconds since the epoch
static int timer_getSecondsSinceEpoch(lua_State *L) {
    LuaSkin *skin = LST_getLuaSkin(); //[LuaSkin shared] ;
    [skin checkArgs:LS_TBREAK];

    struct timeval v;
    gettimeofday(&v, (struct timezone *) NULL);
    /* Unix Epoch time (time since January 1, 1970 (UTC)) */
    lua_pushnumber(L, v.tv_sec + v.tv_usec/1.0e6);
    return 1;
}


// Metatable for created objects when _new invoked
static const luaL_Reg timer_metalib[] = {
    {"start",   timer_start},
    {"stop",    timer_stop},
    {"running", timer_running},
    {"nextTrigger", timer_nextTrigger},
    {"setNextTrigger", timer_setNextTrigger},
    {"__tostring", userdata_tostring},
    {"__gc",    timer_gc},
    {NULL,      NULL}
};

// Functions for returned object when module loads
static const luaL_Reg timerLib[] = {
    {"doAfter",    timer_doAfter},
    {"new",        timer_new},
    {"usleep",     timer_usleep},
    {"secondsSinceEpoch",       timer_getSecondsSinceEpoch},
    {NULL,          NULL}
};

// Metatable for returned object when module loads
static const luaL_Reg meta_gcLib[] = {
    {"__gc",    meta_gc},
    {NULL,      NULL}
};

int luaopen_hs_timer_internal(lua_State* L __unused) {
    LuaSkin *skin = LST_getLuaSkin(); //[LuaSkin shared] ;

    LST_setRefTable(skin, USERDATA_TAG, refTable,
        [skin registerLibrary:timerLib metaFunctions:meta_gcLib]);

    [skin registerObject:USERDATA_TAG objectFunctions:timer_metalib];

    return 1;
}
