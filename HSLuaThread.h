
// #define VERBOSE_LOGGING

extern int luathread_managerForThreadWithType(lua_State *L, id threadObject, NSString *type) ;

@interface HSLuaThread : NSThread <NSPortDelegate>
@property            BOOL                performCleanClose ;
@property            BOOL                restartLuaState ;

// Use to report back to the initiating thread
- (void)returnResults:(NSArray *)results ;
- (void)returnOutput:(NSData *)output ;
- (void)flushOutput ;

// Use for accessing shared dictionary
- (NSArray *)sharedDictionaryGetKeys ;
- (id)sharedDictionaryGetObjectForKey:(NSString *)key ;
- (BOOL)sharedDictionarySetObject:(id)value forKey:(NSString *)key ;

// Override in subclass, but make sure to invoke superclass during init:
- (instancetype)initWithName:(NSString *)name ;

// Override in subclass, invoking superclass optional
- (BOOL)startInstance ;
// If you don't override, calls [self startInstance] and cancels thread if this fails
- (void)restartInstance ;
// If you don't override, just cancels thread so runloop will fall through
- (void)instanceCancelled:(BOOL)cleanClose ;
// If you don't override, does nothing
- (void)handleIncomingData:(NSData *)input ;
// Invoke superclass to also log to main thread LuaSkin
- (void)logAtLevel:(int)level withMessage:(NSString *)message ;
@end
