/*

    Private Interface to LuaSkinThread sub-class of LuaSkin

    These methods are generally not to be used outside of `hs._asm.luathread` and LuaSkinThread
    itself, as they can royally screw things up if you're not careful.

    Unless you have a specific need, it is highly suggested that you do not include this header
    in your projects and limit yourself to the methods and macros defined in LuaSkinThread.h

    You have been warned!

*/

#import "LuaSkinThread.h"
#import "luathread.h"

#pragma mark - LuaSkin internal extension not published in LuaSkin.h

// Extension to LuaSkin class to allow private modification of the lua_State property
@interface LuaSkin ()
@property (readwrite, assign) lua_State *L;
@end

#pragma mark - LuaSkinThread class private extension

@interface LuaSkinThread ()
@property (weak) HSASMLuaThread      *threadForThisSkin ;

// Inject a new class method for use as a replacement for [LuaSkin shared] in a threaded instance.
+(BOOL)inject ;

// Tools for manipulating references from another thread... not sure these will stick around, since its
// a pretty big risk, but I want to play with hs._asm.luaskinpokeytool a little more before I decide...
-(int)getRefForLabel:(const char *)label inModule:(const char *)module inThread:(NSThread *)thread ;
-(BOOL)setRef:(int)refNumber forLabel:(const char *)label inModule:(const char *)module inThread:(NSThread *)thread ;
@end
