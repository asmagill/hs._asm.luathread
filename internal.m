@import Cocoa ;
@import LuaSkin ;
#import "HSLuaThread.h"

static const char *USERDATA_TAG    = "hs.luathread" ;
static const char *THREAD_UD_TAG   = "hs.luathread.instance" ;

#ifdef VERBOSE_LOGGING
#define PORTMESSAGE_LOGGING
#endif

// message id's for messages which can be passed between manager and thread
#define MSGID_RESULT     100 // a result has been returned
#define MSGID_PRINT      101 // something has been output (printed)
#define MSGID_PRINTFLUSH 102 // output has been flushed, so do callback

#define MSGID_INPUT  200 // something has been submitted to execute
#define MSGID_CANCEL 201 // cancel the thread and shutdown

#define get_objectFromUserdata(objType, L, idx, tag) (objType*)*((void**)luaL_checkudata(L, idx, tag))

#pragma mark - Support Functions and Classes

@interface HSLuaThread ()
@property            NSTimeInterval      lockTimeout ;
@property (readonly) NSLock              *dictionaryLock ;
@property (readonly) NSMutableDictionary *sharedDictionary ;
@property (readonly) BOOL                idle ;
@property (readonly) NSPort              *inPort ;
@property (readonly) NSPort              *outPort ;
@end

@implementation HSLuaThread

- (instancetype)initWithName:(NSString *)name {
    self = [super init] ;
    if (self) {
        self.name          = name ;
        _performCleanClose = YES ;
        _idle              = NO ;
        _restartLuaState   = NO ;
        _dictionaryLock    = [[NSLock alloc] init] ;
        _lockTimeout       = 5.0 ;
        _sharedDictionary  = [[NSMutableDictionary alloc] init] ;
    }
    return self ;
}

- (void)setInPort:(NSPort *)inPort andOutPort:(NSPort *)outPort {
    _inPort  = inPort ;
    [_inPort setDelegate:self] ;
    _outPort = outPort ;
}

- (void)removeCommunicationPorts {
    [[NSRunLoop currentRunLoop] removePort:_inPort forMode:NSDefaultRunLoopMode] ;
    [_inPort setDelegate:nil] ;
    [_inPort invalidate] ;
    _inPort  = nil ;
    _outPort = nil ;
}

-(void)main {
    @autoreleasepool {
        [[NSRunLoop currentRunLoop] addPort:_inPort forMode:NSDefaultRunLoopMode] ;

        // Thread Main Loop
        if ([self startInstance]) {
            while (!self.cancelled) {
                _idle = YES ;
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
                if (_restartLuaState) [self restartInstance] ;
            }
#ifdef VERBOSE_LOGGING
            [LuaSkin logDebug:[NSString stringWithFormat:@"%s:main - exited while-runloop for %@", THREAD_UD_TAG, self.name]] ;
#endif
            [self instanceCancelled:_performCleanClose] ;
        }
        [self removeCommunicationPorts] ;
    }
}

- (void)handlePortMessage:(NSPortMessage *)portMessage {
#ifdef PORTMESSAGE_LOGGING
    [LuaSkin logDebug:[NSString stringWithFormat:@"%s:handlePortMessage: --> portMessage %d for %@", THREAD_UD_TAG, portMessage.msgid, self.name]] ;
#endif
    _idle = NO ;
    switch(portMessage.msgid) {
        case MSGID_INPUT: {
            NSData *input = [portMessage.components firstObject] ;
            [self handleIncomingData:input] ;
        }   break ;
        case MSGID_CANCEL: // do nothing, this was just to break out of the run loop
            break ;
        default: {
            [self logAtLevel:LS_LOG_INFO withMessage:[NSString stringWithFormat:@"%s:handlePortMessage: - unhandled message %d for %@", THREAD_UD_TAG, portMessage.msgid, self.name]] ;
        }   break ;
    }
}

- (void)returnResults:(NSArray *)results {
    NSMutableArray *encodedResults = [[NSMutableArray alloc] init] ;
    for (id object in results) {
        NSData *encoded ;
        @try {
            encoded = [NSKeyedArchiver archivedDataWithRootObject:object];
        } @catch (NSException *exception) {
            [LuaSkin logWarn:[NSString stringWithFormat:@"%s:returnResults: - exception archiving result:%@", THREAD_UD_TAG, exception]] ;
        }
        if (!encoded) encoded = [NSKeyedArchiver archivedDataWithRootObject:[NSNull null]];
        [encodedResults addObject:encoded] ;
    }
    NSPortMessage* messageObj = [[NSPortMessage alloc] initWithSendPort:_outPort
                                                            receivePort:_inPort
                                                             components:encodedResults];
    [messageObj setMsgid:MSGID_RESULT];
    [messageObj sendBeforeDate:[NSDate date]];
#ifdef PORTMESSAGE_LOGGING
    [LuaSkin logDebug:[NSString stringWithFormat:@"%s:returnResults: <-- portMessage %d for %@ with %lu results", THREAD_UD_TAG, messageObj.msgid, self.name, [encodedResults count]]] ;
#endif
}

- (void)returnOutput:(NSData *)output {
    NSPortMessage* messageObj = [[NSPortMessage alloc] initWithSendPort:_outPort
                                                            receivePort:_inPort
                                                             components:@[ output ]];
    [messageObj setMsgid:MSGID_PRINT];
    [messageObj sendBeforeDate:[NSDate date]];
#ifdef PORTMESSAGE_LOGGING
    [LuaSkin logDebug:[NSString stringWithFormat:@"%s:returnOutput: <-- portMessage %d for %@", THREAD_UD_TAG, messageObj.msgid, self.name]] ;
#endif
}

- (void)flushOutput {
    NSPortMessage* messageObj = [[NSPortMessage alloc] initWithSendPort:_outPort
                                                            receivePort:_inPort
                                                             components:nil];
    [messageObj setMsgid:MSGID_PRINTFLUSH];
    [messageObj sendBeforeDate:[NSDate date]];
#ifdef PORTMESSAGE_LOGGING
    [LuaSkin logDebug:[NSString stringWithFormat:@"%s:flushOutput <-- portMessage %d for %@", THREAD_UD_TAG, messageObj.msgid, self.name]] ;
#endif
}

- (NSArray *)sharedDictionaryGetKeys {
    NSArray *theKeys ;
    if ([_dictionaryLock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:_lockTimeout]]) {
        theKeys = [_sharedDictionary allKeys] ;
        [_dictionaryLock unlock] ;
    } else {
        [self logAtLevel:LS_LOG_ERROR withMessage:[NSString stringWithFormat:@"%s:sharedDictionaryGetKeys - unable to obtain dictionary lock", THREAD_UD_TAG]] ;
    }
    return theKeys ;
}

- (id)sharedDictionaryGetObjectForKey:(NSString *)key {
    id value ;
    if (key && [_dictionaryLock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:_lockTimeout]]) {
        value = _sharedDictionary[key] ;
        [_dictionaryLock unlock] ;
    } else {
        [self logAtLevel:LS_LOG_ERROR withMessage:[NSString stringWithFormat:@"%s:sharedDictionaryGetObjectForKey: - unable to obtain dictionary lock", THREAD_UD_TAG]] ;
    }
    return value ;
}

- (BOOL)sharedDictionarySetObject:(id)value forKey:(NSString *)key {
    BOOL status = NO ;
    if (key && [_dictionaryLock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:_lockTimeout]]) {
        _sharedDictionary[key] = value ;
        [_dictionaryLock unlock] ;
        status = YES ;
    } else {
        [self logAtLevel:LS_LOG_ERROR withMessage:[NSString stringWithFormat:@"%s:sharedDictionarySetObject:forKey: - unable to obtain dictionary lock", THREAD_UD_TAG]] ;
    }
    return status ;
}

#pragma mark * Override in subclass

- (BOOL)startInstance {
    return NO ;
}

- (void)restartInstance {
    if (![self startInstance]) {
        [LuaSkin logError:[NSString stringWithFormat:@"%s:restartInstance - exiting thread; error during reload for %@", THREAD_UD_TAG, self.name]] ;
        _performCleanClose = NO ;
        [self cancel] ;
    }
}

- (void)instanceCancelled:(__unused BOOL)cleanClose {
    [self cancel] ;
}

- (void)handleIncomingData:(__unused NSData *)input {
}

- (void)logAtLevel:(int)level withMessage:(NSString *)message {
    [LuaSkin classLogAtLevel:level withMessage:message] ;
}

@end

@interface HSLuaThreadManager : NSObject <NSPortDelegate>
@property                  int            resultsCallbackRef ;
@property                  int            printCallbackRef ;
@property                  int            selfRefCount ;
@property                  BOOL           printImmediate ;
@property (readonly)       NSMutableArray *output ;
@property (readonly)       NSString       *name ;
@property (readonly)       NSString       *type ;
@property (readonly)       HSLuaThread    *threadObj ;
@property (readonly)       NSPort         *inPort ;
@property (readonly)       NSPort         *outPort ;
@property (readonly)       NSThread       *creationThread ;
@end

@implementation HSLuaThreadManager

- (instancetype)initWithThreadObject:(HSLuaThread *)threadObject ofType:(NSString *)type {
    self = [super init] ;
    if (self) {
        _type                = type ;
        _threadObj           = threadObject ;
        _printCallbackRef    = LUA_NOREF ;
        _resultsCallbackRef  = LUA_NOREF ;
        _selfRefCount        = 0 ;
        _name                = threadObject.name ;
        _output              = [[NSMutableArray alloc] init] ;
        _inPort              = [NSMachPort port] ;
        _outPort             = [NSMachPort port] ;

        _creationThread      = [NSThread currentThread] ;

        [_inPort setDelegate:self] ;
        [[NSRunLoop currentRunLoop] addPort:_inPort forMode:NSDefaultRunLoopMode] ;

        [_threadObj setInPort:_outPort andOutPort:_inPort] ; // opposite of ours
        [_threadObj start] ;
    }
    return self ;
}

- (void)removeCommunicationPorts {
    [[NSRunLoop currentRunLoop] removePort:_inPort forMode:NSDefaultRunLoopMode] ;
    [_inPort setDelegate:nil] ;
    [_inPort invalidate] ;
    _inPort    = nil ;
    _outPort   = nil ;
    _threadObj = nil ;
}

- (void)performCallback:(NSDictionary *)param {
      LuaSkin   *skin  = [LuaSkin threaded] ;
      lua_State *L     = [skin L] ;

      [skin pushLuaRef:[skin refTableFor:USERDATA_TAG] ref:[param[@"callbackRef"] intValue]] ;
      [skin pushNSObject:self] ;
      [skin pushNSObject:param[@"data"] withOptions:LS_NSDescribeUnknownTypes |
                                                    LS_NSUnsignedLongLongPreserveBits] ;
      if (![skin protectedCallAndTraceback:2 nresults:0]) {
          [skin logError:[NSString stringWithFormat:@"%s:%@Callback - error: %s", USERDATA_TAG, param[@"message"], lua_tostring(L, -1)]] ;
          lua_pop(L, 1) ;
      }
}

- (void)handlePortMessage:(NSPortMessage *)portMessage {
    LuaSkin *skin = [LuaSkin threaded];
#ifdef PORTMESSAGE_LOGGING
    [skin logDebug:[NSString stringWithFormat:@"%s:handlePortMessage: --> %d for %@", USERDATA_TAG, portMessage.msgid, _name]] ;
#endif
    switch(portMessage.msgid) {
        case MSGID_RESULT: {
            NSArray *components = portMessage.components ;
            if (components) {
                NSMutableArray *results = [[NSMutableArray alloc] init] ;
                for (NSData *item in components) {
                    id realItem ;
                    @try {
                        realItem = [NSKeyedUnarchiver unarchiveObjectWithData:item] ;
                    } @catch (NSException *exception) {
                        [LuaSkin logWarn:[NSString stringWithFormat:@"%s:handlePortMessage: - exception unarchiving result:%@", USERDATA_TAG, exception]] ;
                    }
                    if (!realItem) realItem = [NSNull null] ;
                    [results addObject:realItem] ;
                }
                if (_resultsCallbackRef != LUA_NOREF) {
                    [self performSelector:@selector(performCallback:)
                                 onThread:_creationThread
                               withObject:@{
                                  @"callbackRef" : @(_resultsCallbackRef),
                                  @"message"     : @"results",
                                  @"data"        : results,
                               }
                            waitUntilDone:YES] ;
                }
            }
        }  break ;
        case MSGID_PRINT: {
            NSArray *outputBuffer = portMessage.components ;
            if (outputBuffer) {
                [_output addObjectsFromArray:outputBuffer] ;
            }
        }  break ;
        case MSGID_PRINTFLUSH: {
            if (_printCallbackRef != LUA_NOREF) {
                NSMutableData *outputCopy = [[NSMutableData alloc] init] ;
                for (NSData *obj in _output) [outputCopy appendData:obj] ;
                [_output removeAllObjects] ;
                [self performSelector:@selector(performCallback:)
                             onThread:_creationThread
                           withObject:@{
                              @"callbackRef" : @(_printCallbackRef),
                              @"message"     : @"print",
                              @"data"        : outputCopy,
                           }
                        waitUntilDone:YES] ;
            }
        }   break ;
        default:
            [skin logInfo:[NSString stringWithFormat:@"%s:handlePortMessage: - unhandled message %d for %@", USERDATA_TAG, portMessage.msgid, _name]] ;
            break ;
    }
}

- (NSArray *)sharedDictionaryGetKeys {
    return [_threadObj sharedDictionaryGetKeys] ;
}

- (id)sharedDictionaryGetObjectForKey:(NSString *)key {
    return [_threadObj sharedDictionaryGetObjectForKey:key] ;
}

- (BOOL)sharedDictionarySetObject:(id)value forKey:(NSString *)key {
    return [_threadObj sharedDictionarySetObject:value forKey:key] ;
}

@end

int luathread_managerForThreadWithType(lua_State *L, id threadObject, NSString *type) {
    LuaSkin *skin = [LuaSkin threaded] ;
    if (![threadObject isKindOfClass:[HSLuaThread class]]) {
        return luaL_error(L, "thread must be subclass of HSLuaThread") ;
    }
    HSLuaThreadManager *threadManager = [[HSLuaThreadManager alloc] initWithThreadObject:threadObject
                                                                                  ofType:type] ;
    [skin pushNSObject:threadManager] ;
    return 1 ;
}

#pragma mark - Module Functions

#pragma mark - Module Methods

static int luathread_threadIsExecuting(lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK] ;
    HSLuaThreadManager *threadManager = [skin toNSObjectAtIndex:1] ;
    lua_pushboolean(L, threadManager.threadObj.executing) ;
    return 1 ;
}

static int luathread_threadIsIdle(lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK] ;
    HSLuaThreadManager *threadManager = [skin toNSObjectAtIndex:1] ;
    lua_pushboolean(L, threadManager.threadObj.idle) ;
    return 1 ;
}

static int luathread_printCallback(lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TFUNCTION | LS_TNIL, LS_TBREAK] ;
    HSLuaThreadManager *threadManager = [skin toNSObjectAtIndex:1] ;

    // in either case, we need to remove an existing callback, so...
    threadManager.printCallbackRef = [skin luaUnref:[skin refTableFor:USERDATA_TAG] ref:threadManager.printCallbackRef] ;
    if (lua_type(L, 2) == LUA_TFUNCTION) {
        lua_pushvalue(L, 2) ;
        threadManager.printCallbackRef = [skin luaRef:[skin refTableFor:USERDATA_TAG]] ;
    }
    lua_pushvalue(L, 1) ;
    return 1 ;
}

static int luathread_resultsCallback(lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TFUNCTION | LS_TNIL, LS_TBREAK] ;
    HSLuaThreadManager *threadManager = [skin toNSObjectAtIndex:1] ;

    // in either case, we need to remove an existing callback, so...
    threadManager.resultsCallbackRef = [skin luaUnref:[skin refTableFor:USERDATA_TAG] ref:threadManager.resultsCallbackRef] ;
    if (lua_type(L, 2) == LUA_TFUNCTION) {
        lua_pushvalue(L, 2) ;
        threadManager.resultsCallbackRef = [skin luaRef:[skin refTableFor:USERDATA_TAG]] ;
    }
    lua_pushvalue(L, 1) ;
    return 1 ;
}

static int luathread_cancelThread(lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TANY | LS_TOPTIONAL, LS_TANY | LS_TOPTIONAL, LS_TBREAK] ;
    HSLuaThreadManager *threadManager = [skin toNSObjectAtIndex:1] ;
    if (threadManager.threadObj.executing) {
        if (lua_type(L, 3) != LUA_TNONE) {
            threadManager.threadObj.performCleanClose = (BOOL)lua_toboolean(L, 3) ;
        }
        [threadManager.threadObj cancel] ;
        NSPortMessage* messageObj = [[NSPortMessage alloc] initWithSendPort:threadManager.outPort
                                                                receivePort:threadManager.inPort
                                                                 components:nil];
        [messageObj setMsgid:MSGID_CANCEL];
        [messageObj sendBeforeDate:[NSDate date]];
#ifdef PORTMESSAGE_LOGGING
        [skin logDebug:[NSString stringWithFormat:@"%s:cancel <-- portMessage %d for %@", USERDATA_TAG, messageObj.msgid, threadManager.threadObj.name]] ;
#endif
        lua_pushvalue(L, 1) ;
    } else {
        return luaL_error(L, "thread inactive") ;
    }
    return 1 ;
}

static int luathread_threadName(__unused lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TANY | LS_TOPTIONAL, LS_TANY | LS_TOPTIONAL, LS_TBREAK] ;
    HSLuaThreadManager *threadManager = [skin toNSObjectAtIndex:1] ;
    [skin pushNSObject:threadManager.name] ;
    return 1 ;
}

static int luathread_getOutput(__unused lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK] ;
    HSLuaThreadManager *threadManager = [skin toNSObjectAtIndex:1] ;
    [skin pushNSObject:threadManager.output] ;
    return 1 ;
}

static int luathread_flushOutput(lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK] ;
    HSLuaThreadManager *threadManager = [skin toNSObjectAtIndex:1] ;

    [threadManager.output removeAllObjects] ;
    lua_pushvalue(L, 1) ;
    return 1 ;
}

static int luathread_submitInput(lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TSTRING, LS_TBREAK] ;
    HSLuaThreadManager *threadManager = [skin toNSObjectAtIndex:1] ;

    if (threadManager.threadObj.executing) {
        NSData *input = [skin toNSObjectAtIndex:2 withOptions:LS_NSLuaStringAsDataOnly] ;

        NSPortMessage* messageObj = [[NSPortMessage alloc] initWithSendPort:threadManager.outPort
                                                                receivePort:threadManager.inPort
                                                                 components:@[input]];
        [messageObj setMsgid:MSGID_INPUT];
        [messageObj sendBeforeDate:[NSDate date]];
#ifdef PORTMESSAGE_LOGGING
        [skin logDebug:[NSString stringWithFormat:@"%s:submit <-- portMessage %d for %@", USERDATA_TAG, messageObj.msgid, threadManager.threadObj.name]] ;
#endif
        lua_pushvalue(L, 1) ;
    } else {
        return luaL_error(L, "thread inactive") ;
    }
    return 1 ;
}

static int luathread_getFromDictionary(__unused lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TSTRING, LS_TBREAK] ;
    HSLuaThreadManager *threadManager = [skin toNSObjectAtIndex:1] ;
    NSString *key = [skin toNSObjectAtIndex:2] ;
    id obj = [threadManager sharedDictionaryGetObjectForKey:key] ;
    [skin pushNSObject:obj withOptions:LS_NSUnsignedLongLongPreserveBits |
                                       LS_NSDescribeUnknownTypes         |
                                       LS_NSPreserveLuaStringExactly     |
                                       LS_NSAllowsSelfReference] ;
    return 1 ;
}

static int luathread_setInDictionary(lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TSTRING, LS_TANY, LS_TBREAK] ;
    HSLuaThreadManager *threadManager = [skin toNSObjectAtIndex:1] ;
    NSString *key = [skin toNSObjectAtIndex:2] ;
    id value = [skin toNSObjectAtIndex:3 withOptions:LS_NSUnsignedLongLongPreserveBits |
                                                     LS_NSDescribeUnknownTypes         |
                                                     LS_NSPreserveLuaStringExactly     |
                                                     LS_NSAllowsSelfReference] ;
    if (threadManager.threadObj.executing) {
        if ([threadManager sharedDictionarySetObject:value forKey:key]) {
            lua_pushvalue(L, 1) ;
        } else {
            lua_pushnil(L) ;
        }
    } else {
        return luaL_error(L, "thread inactive") ;
    }
    return 1 ;
}

static int luathread_keysForDictionary(__unused lua_State *L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK] ;
    HSLuaThreadManager *threadManager = [skin toNSObjectAtIndex:1] ;
    NSArray *theKeys = [threadManager sharedDictionaryGetKeys] ;
    [skin pushNSObject:theKeys] ;
    return 1 ;
}

#pragma mark - Module Constants

#pragma mark - Lua<->NSObject Conversion Functions
// These must not throw a lua error to ensure LuaSkin can safely be used from Objective-C
// delegates and blocks.

static int pushHSLuaThreadManager(lua_State *L, id obj) {
    HSLuaThreadManager *value = obj;
    value.selfRefCount++ ;
    void** valuePtr = lua_newuserdata(L, sizeof(HSLuaThreadManager *));
    *valuePtr = (__bridge_retained void *)value;
    luaL_getmetatable(L, USERDATA_TAG);
    lua_setmetatable(L, -2);
    return 1;
}

static id toHSLuaThreadManagerFromLua(lua_State *L, int idx) {
    LuaSkin *skin = [LuaSkin threaded];
    HSLuaThreadManager *value ;
    if (luaL_testudata(L, idx, USERDATA_TAG)) {
        value = get_objectFromUserdata(__bridge HSLuaThreadManager, L, idx, USERDATA_TAG) ;
    } else {
        [skin logError:[NSString stringWithFormat:@"expected %s object, found %s", USERDATA_TAG,
                                                  lua_typename(L, lua_type(L, idx))]] ;
    }
    return value ;
}

#pragma mark - Hammerspoon/Lua Infrastructure

static int userdata_tostring(lua_State* L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    HSLuaThreadManager *obj = [skin luaObjectAtIndex:1 toClass:"HSLuaThreadManager"] ;
    NSString *title = obj.threadObj.name ;
    [skin pushNSObject:[NSString stringWithFormat:@"%s: %@ (%p)", USERDATA_TAG, title, lua_topointer(L, 1)]] ;
    return 1 ;
}

static int userdata_eq(lua_State* L) {
// can't get here if at least one of us isn't a userdata type, and we only care if both types are ours,
// so use luaL_testudata before the macro causes a lua error
    LuaSkin *skin = [LuaSkin threaded] ;
    if (luaL_testudata(L, 1, USERDATA_TAG) && luaL_testudata(L, 2, USERDATA_TAG)) {
        HSLuaThreadManager *obj1 = [skin luaObjectAtIndex:1 toClass:"HSLuaThreadManager"] ;
        HSLuaThreadManager *obj2 = [skin luaObjectAtIndex:1 toClass:"HSLuaThreadManager"] ;
        lua_pushboolean(L, [obj1 isEqualTo:obj2]) ;
    } else {
        lua_pushboolean(L, NO) ;
    }
    return 1 ;
}

static int userdata_gc(lua_State* L) {
    HSLuaThreadManager *obj = get_objectFromUserdata(__bridge_transfer HSLuaThreadManager, L, 1, USERDATA_TAG) ;
#ifdef VERBOSE_LOGGING
    [[LuaSkin threaded] logDebug:[NSString stringWithFormat:@"%s:__gc for %@", USERDATA_TAG, obj.threadObj.name]] ;
#endif
    if (obj) {
        obj.selfRefCount-- ;
        if (obj.selfRefCount == 0) {
            LuaSkin *skin = [LuaSkin threaded] ;
            obj.printCallbackRef = [skin luaUnref:[skin refTableFor:USERDATA_TAG] ref:obj.printCallbackRef] ;
            obj.resultsCallbackRef = [skin luaUnref:[skin refTableFor:USERDATA_TAG] ref:obj.resultsCallbackRef] ;
            [obj removeCommunicationPorts] ;
            [obj.threadObj cancel] ;
            obj = nil ;
        }
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
    {"name",              luathread_threadName},
    {"submit",            luathread_submitInput},
    {"isExecuting",       luathread_threadIsExecuting},
    {"isIdle",            luathread_threadIsIdle},
    {"getOutput",         luathread_getOutput},
    {"flushOutput",       luathread_flushOutput},
    {"printCallback",     luathread_printCallback},
    {"resultsCallback",   luathread_resultsCallback},
    {"cancel",            luathread_cancelThread},

    {"getFromDictionary", luathread_getFromDictionary},
    {"setInDictionary",   luathread_setInDictionary},
    {"keysForDictionary", luathread_keysForDictionary},

    {"__tostring",        userdata_tostring},
    {"__eq",              userdata_eq},
    {"__gc",              userdata_gc},
    {NULL,                NULL}
};

// Functions for returned object when module loads
static luaL_Reg moduleLib[] = {
    {NULL,                  NULL}
};

// // Metatable for module, if needed
// static const luaL_Reg module_metaLib[] = {
//     {"__gc", meta_gc},
//     {NULL,   NULL}
// };

int luaopen_hs_luathread_internal(lua_State* __unused L) {
    LuaSkin *skin = [LuaSkin threaded] ;
    [skin registerLibraryWithObject:USERDATA_TAG
                          functions:moduleLib
                      metaFunctions:nil    // or module_metaLib
                    objectFunctions:userdata_metaLib];

    [skin registerPushNSHelper:pushHSLuaThreadManager         forClass:"HSLuaThreadManager"];
    [skin registerLuaObjectHelper:toHSLuaThreadManagerFromLua forClass:"HSLuaThreadManager"
                                                   withUserdataMapping:USERDATA_TAG];

    return 1;
}
