@import Cocoa ;
@import LuaSkin ;

#define USERDATA_TAG  "hs._asm.luathread"
#define THREAD_UD_TAG "hs._asm.luathread._instance"

// maximum seconds to try and get a lock on the threadDictionary
#define LOCK_TIMEOUT     10

// message id's for messages which can be passed between manager and thread
#define MSGID_RESULT     100
#define MSGID_PRINTFLUSH 101

#define MSGID_INPUT      200
#define MSGID_CANCEL     201

NSDictionary *assignmentsFromParent ;

#define get_objectFromUserdata(objType, L, idx, tag) (objType*)*((void**)luaL_checkudata(L, idx, tag))

#define VERBOSE(MSG)     [LuaSkin logVerbose:[NSString stringWithFormat:@"%s:%@", ([NSThread isMainThread] ? USERDATA_TAG : THREAD_UD_TAG), MSG]]
#define DEBUG(MSG)       [LuaSkin   logDebug:[NSString stringWithFormat:@"%s:%@", ([NSThread isMainThread] ? USERDATA_TAG : THREAD_UD_TAG), MSG]]
#define INFORMATION(MSG) [LuaSkin    logInfo:[NSString stringWithFormat:@"%s:%@", ([NSThread isMainThread] ? USERDATA_TAG : THREAD_UD_TAG), MSG]]
#define ERROR(MSG)       [LuaSkin   logError:[NSString stringWithFormat:@"%s:%@", ([NSThread isMainThread] ? USERDATA_TAG : THREAD_UD_TAG), MSG]]

@interface HSASMBooleanType : NSObject
@property (readonly) BOOL value ;
@end

int getHamster(lua_State *L, id obj, NSMutableDictionary *alreadySeen) ;
id setHamster(lua_State *L, int idx, NSMutableDictionary *alreadySeen) ;

@interface HSASMLuaThread : NSThread <NSPortDelegate, LuaSkinDelegate>
@property (readonly) lua_State      *L ;
@property (readonly) int            runStringRef ;
@property            BOOL           performLuaClose ;
@property            NSLock         *dictionaryLock ;
@property            BOOL           idle ;
@property            BOOL           resetLuaState ;
@property (readonly) NSPort         *inPort ;
@property (readonly) NSPort         *outPort ;
@property (readonly) NSMutableArray *cachedOutput ;
@property (readonly) NSDictionary   *finalDictionary ;
@property (readonly) LuaSkin        *skin ;

-(instancetype)initWithPort:(NSPort *)outPort andName:(NSString *)name ;
@end

@interface HSASMLuaThreadManager : NSObject  <NSPortDelegate>
@property            int            callbackRef ;
@property            int            selfRef ;
@property (readonly) HSASMLuaThread *threadObj ;
@property (readonly) NSPort         *inPort ;
@property (readonly) NSPort         *outPort ;
@property (readonly) NSMutableArray *output ;
@property            BOOL           printImmediate ;
@property (readonly) NSString       *name ;
@end

