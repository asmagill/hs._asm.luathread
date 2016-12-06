@import Cocoa ;
@import LuaSkin ;

#pragma mark - Support Functions and Classes

#pragma mark - Module Functions

static int testThreadSuport(lua_State *L) {
    lua_pushboolean(L, [[LuaSkin class] respondsToSelector:@selector(threaded)]) ;
    return 1 ;
}

int luaopen_hs_luathread_supported(lua_State* L) {
    lua_pushcfunction(L, testThreadSuport) ;
    return 1;
}
