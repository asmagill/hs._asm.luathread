// "Private" properties defined in Skin.m

extern NSMapTable *threadToSkinMap ;

@interface LuaSkin ()
@property (readwrite, assign, atomic) lua_State *L;
@property (readonly, atomic)  NSMutableDictionary *registeredNSHelperFunctions ;
@property (readonly, atomic)  NSMutableDictionary *registeredNSHelperLocations ;
@property (readonly, atomic)  NSMutableDictionary *registeredLuaObjectHelperFunctions ;
@property (readonly, atomic)  NSMutableDictionary *registeredLuaObjectHelperLocations ;
@property (readonly, atomic)  NSMutableDictionary *registeredLuaObjectHelperUserdataMappings;
@property (readonly, atomic)  NSMutableDictionary *registeredLuaObjectHelperTableMappings;
@property (readonly, atomic)  NSMutableDictionary *refTableReferences ;
@end
