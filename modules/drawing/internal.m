#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <LuaSkin/LuaSkin.h>
#import "../../LuaSkinThread.h"

/// === hs.drawing ===
///
/// Primitives for drawing on the screen in various ways

// Useful definitions
#define USERDATA_TAG "hs.drawing"

int refTable;

// Lua API implementation

/// hs.drawing.disableScreenUpdates() -> None
/// Function
/// Tells the OS X window server to pause updating the physical displays for a short while.
///
/// Parameters:
///  * None
///
/// Returns:
///  * None
///
/// Notes:
///  * This method can be used to allow multiple changes which are being made to the users display appear as if they all occur simultaneously by holding off on updating the screen on the regular schedule.
///  * This method should always be balanced with a call to [hs.drawing.enableScreenUpdates](#enableScreenUpdates) when your updates have been completed.  Failure to do so will be logged in the system logs.
///
///  * The window server will only allow you to pause updates for up to 1 second.  This prevents a rogue or hung process from locking the systems display completely.  Updates will be resumed when [hs.drawing.enableScreenUpdates](#enableScreenUpdates) is encountered or after 1 second, whichever comes first.
static int disableUpdates(__unused lua_State *L) {
    [LST_getLuaSkin() checkArgs:LS_TBREAK] ;
    NSDisableScreenUpdates() ;
    return 0 ;
}

/// hs.drawing.enableScreenUpdates() -> None
/// Function
/// Tells the OS X window server to resume updating the physical displays after a previous pause.
///
/// Parameters:
///  * None
///
/// Returns:
///  * None
///
/// Notes:
///  * In conjunction with [hs.drawing.disableScreenUpdates](#disableScreenUpdates), this method can be used to allow multiple changes which are being made to the users display appear as if they all occur simultaneously by holding off on updating the screen on the regular schedule.
///
///  * The window server will only allow you to pause updates for up to 1 second.  This prevents a rogue or hung process from locking the systems display completely.  Updates will be resumed when this function is encountered  or after 1 second, whichever comes first.
static int enableUpdates(__unused lua_State *L) {
    [LST_getLuaSkin() checkArgs:LS_TBREAK] ;
    NSEnableScreenUpdates() ;
    return 0 ;
}

NSDictionary *modifyTextStyleFromStack(lua_State *L, int idx, NSDictionary *defaultStuff) {
    NSFont                  *theFont  = [[defaultStuff objectForKey:@"font"] copy] ;
    NSMutableParagraphStyle *theStyle ;
    NSColor                 *theColor = [[defaultStuff objectForKey:@"color"] copy] ;
    NSFont *tmpFont;

    if (lua_istable(L, idx)) {
        if (lua_getfield(L, -1, "font")) {
            if (lua_type(L, -1) == LUA_TTABLE) {
                theFont = [LST_getLuaSkin() luaObjectAtIndex:-1 toClass:"NSFont"] ;
            } else {
                CGFloat pointSize = theFont.pointSize;
                NSString *fontName = [NSString stringWithUTF8String:luaL_checkstring(L, -1)];
                tmpFont = [NSFont fontWithName:fontName size:pointSize];
                if (tmpFont) {
                    theFont = tmpFont;
                }
            }
        }
        lua_pop(L, 1);

        if (lua_getfield(L, -1, "size")) {
            CGFloat pointSize = lua_tonumber(L, -1);
            NSString *fontName = theFont.fontName;
            tmpFont = [NSFont fontWithName:fontName size:pointSize];
            if (tmpFont) {
                theFont = tmpFont;
            }
        }
        lua_pop(L, 1);

        if (lua_getfield(L, -1, "color")) {
            theColor = [LST_getLuaSkin() luaObjectAtIndex:-1 toClass:"NSColor"] ;
        }
        lua_pop(L, 1);

        if (lua_getfield(L, -1, "paragraphStyle")) {
            theStyle = [[LST_getLuaSkin() luaObjectAtIndex:-1 toClass:"NSParagraphStyle"] mutableCopy] ;
            lua_pop(L, 1) ;
        } else {
            lua_pop(L, 1) ;
            theStyle = [[defaultStuff objectForKey:@"style"] mutableCopy] ;
            if (lua_getfield(L, -1, "alignment")) {
                NSString *alignment = [NSString stringWithUTF8String:luaL_checkstring(L, -1)];
                if ([alignment isEqualToString:@"left"]) {
                    theStyle.alignment = NSLeftTextAlignment ;
                } else if ([alignment isEqualToString:@"right"]) {
                    theStyle.alignment = NSRightTextAlignment ;
                } else if ([alignment isEqualToString:@"center"]) {
                    theStyle.alignment = NSCenterTextAlignment ;
                } else if ([alignment isEqualToString:@"justified"]) {
                    theStyle.alignment = NSJustifiedTextAlignment ;
                } else if ([alignment isEqualToString:@"natural"]) {
                    theStyle.alignment = NSNaturalTextAlignment ;
                } else {
                    luaL_error(L, [[NSString stringWithFormat:@"invalid alignment for textStyle specified: %@", alignment] UTF8String]) ;
                    return nil ;
                }
            }
            lua_pop(L, 1);

            if (lua_getfield(L, -1, "lineBreak")) {
                NSString *lineBreak = [NSString stringWithUTF8String:luaL_checkstring(L, -1)];
                if ([lineBreak isEqualToString:@"wordWrap"]) {
                    theStyle.lineBreakMode = NSLineBreakByWordWrapping ;
                } else if ([lineBreak isEqualToString:@"charWrap"]) {
                    theStyle.lineBreakMode = NSLineBreakByCharWrapping ;
                } else if ([lineBreak isEqualToString:@"clip"]) {
                    theStyle.lineBreakMode = NSLineBreakByClipping ;
                } else if ([lineBreak isEqualToString:@"truncateHead"]) {
                    theStyle.lineBreakMode = NSLineBreakByTruncatingHead ;
                } else if ([lineBreak isEqualToString:@"truncateTail"]) {
                    theStyle.lineBreakMode = NSLineBreakByTruncatingTail ;
                } else if ([lineBreak isEqualToString:@"truncateMiddle"]) {
                    theStyle.lineBreakMode = NSLineBreakByTruncatingMiddle ;
                } else {
                    luaL_error(L, [[NSString stringWithFormat:@"invalid lineBreak for textStyle specified: %@", lineBreak] UTF8String]) ;
                    return nil ;
                }
            }
            lua_pop(L, 1);
        }

    } else {
        luaL_error(L, "invalid textStyle type specified: %s", lua_typename(L, -1)) ;
        return nil ;
    }

    return @{@"font":theFont, @"style":theStyle, @"color":theColor} ;
}

/// hs.drawing.windowBehaviors[]
/// Constant
/// Array of window behavior labels for determining how an hs.drawing object is handled in Spaces and Exposé
///
/// * default           -- The window can be associated to one space at a time.
/// * canJoinAllSpaces  -- The window appears in all spaces. The menu bar behaves this way.
/// * moveToActiveSpace -- Making the window active does not cause a space switch; the window switches to the active space.
///
/// Only one of these may be active at a time:
///
/// * managed           -- The window participates in Spaces and Exposé. This is the default behavior if windowLevel is equal to NSNormalWindowLevel.
/// * transient         -- The window floats in Spaces and is hidden by Exposé. This is the default behavior if windowLevel is not equal to NSNormalWindowLevel.
/// * stationary        -- The window is unaffected by Exposé; it stays visible and stationary, like the desktop window.
///
/// Notes:
///  * This table has a __tostring() metamethod which allows listing it's contents in the Hammerspoon console by typing `hs.drawing.windowBehaviors`.

// the following don't apply to hs.drawing objects, but may become useful if we decide to add support for more traditional window creation in HS.
//
// /// Only one of these may be active at a time:
// ///
// /// * participatesInCycle -- The window participates in the window cycle for use with the Cycle Through Windows Window menu item.
// /// * ignoresCycle        -- The window is not part of the window cycle for use with the Cycle Through Windows Window menu item.
// ///
// /// Only one of these may be active at a time:
// ///
// /// * fullScreenPrimary   -- A window with this collection behavior has a fullscreen button in the upper right of its titlebar.
// /// * fullScreenAuxiliary -- Windows with this collection behavior can be shown on the same space as the fullscreen window.

static int pushCollectionTypeTable(lua_State *L) {
    lua_newtable(L) ;
        lua_pushinteger(L, NSWindowCollectionBehaviorDefault) ;             lua_setfield(L, -2, "default") ;
        lua_pushinteger(L, NSWindowCollectionBehaviorCanJoinAllSpaces) ;    lua_setfield(L, -2, "canJoinAllSpaces") ;
        lua_pushinteger(L, NSWindowCollectionBehaviorMoveToActiveSpace) ;   lua_setfield(L, -2, "moveToActiveSpace") ;
        lua_pushinteger(L, NSWindowCollectionBehaviorManaged) ;             lua_setfield(L, -2, "managed") ;
        lua_pushinteger(L, NSWindowCollectionBehaviorTransient) ;           lua_setfield(L, -2, "transient") ;
        lua_pushinteger(L, NSWindowCollectionBehaviorStationary) ;          lua_setfield(L, -2, "stationary") ;
//         lua_pushinteger(L, NSWindowCollectionBehaviorParticipatesInCycle) ; lua_setfield(L, -2, "participatesInCycle") ;
//         lua_pushinteger(L, NSWindowCollectionBehaviorIgnoresCycle) ;        lua_setfield(L, -2, "ignoresCycle") ;
//         lua_pushinteger(L, NSWindowCollectionBehaviorFullScreenPrimary) ;   lua_setfield(L, -2, "fullScreenPrimary") ;
//         lua_pushinteger(L, NSWindowCollectionBehaviorFullScreenAuxiliary) ; lua_setfield(L, -2, "fullScreenAuxiliary") ;
    return 1 ;
}

/// hs.drawing.windowLevels
/// Constant
/// A table of predefined window levels usable with `hs.drawing:setLevel(...)`
///
/// Predefined levels are:
///  * _MinimumWindowLevelKey - lowest allowed window level
///  * desktop
///  * desktopIcon            - `hs.drawing:sendToBack()` is equivalent to this - 1
///  * normal                 - normal application windows
///  * tornOffMenu
///  * floating               - equivalent to `hs.drawing:bringToFront(false)`, where "Always Keep On Top" windows are usually set
///  * modalPanel             - modal alert dialog
///  * utility
///  * dock                   - level of the Dock
///  * mainMenu               - level of the Menubar
///  * status
///  * popUpMenu              - level of a menu when displayed (open)
///  * overlay
///  * help
///  * dragging
///  * screenSaver            - equivalent to `hs.drawing:bringToFront(true)`
///  * assistiveTechHigh
///  * cursor
///  * _MaximumWindowLevelKey - highest allowed window level
///
/// Notes:
///  * This table has a __tostring() metamethod which allows listing it's contents in the Hammerspoon console by typing `hs.drawing.windowLevels`.
///  * These key names map to the constants used in CoreGraphics to specify window levels and may not actually be used for what the name might suggest. For example, tests suggest that an active screen saver actually runs at a level of 2002, rather than at 1000, which is the window level corresponding to kCGScreenSaverWindowLevelKey.
///  * Each drawing level is sorted separately and `hs.drawing:orderAbove(...)` and hs.drawing:orderBelow(...)` only arrange windows within the same level.
///  * If you use Dock hiding (or in 10.11, Menubar hiding) please note that when the Dock (or Menubar) is popped up, it is done so with an implicit orderAbove, which will place it above any items you may also draw at the Dock (or MainMenu) level.
static int cg_windowLevels(lua_State *L) {
    lua_newtable(L) ;
//       lua_pushinteger(L, CGWindowLevelForKey(kCGBaseWindowLevelKey)) ;              lua_setfield(L, -2, "kCGBaseWindowLevelKey") ;
      lua_pushinteger(L, CGWindowLevelForKey(kCGMinimumWindowLevelKey)) ;           lua_setfield(L, -2, "_MinimumWindowLevelKey") ;
      lua_pushinteger(L, CGWindowLevelForKey(kCGDesktopWindowLevelKey)) ;           lua_setfield(L, -2, "desktop") ;
//       lua_pushinteger(L, CGWindowLevelForKey(kCGBackstopMenuLevelKey)) ;            lua_setfield(L, -2, "kCGBackstopMenuLevelKey") ;
      lua_pushinteger(L, CGWindowLevelForKey(kCGNormalWindowLevelKey)) ;            lua_setfield(L, -2, "normal") ;
      lua_pushinteger(L, CGWindowLevelForKey(kCGFloatingWindowLevelKey)) ;          lua_setfield(L, -2, "floating") ;
      lua_pushinteger(L, CGWindowLevelForKey(kCGTornOffMenuWindowLevelKey)) ;       lua_setfield(L, -2, "tornOffMenu") ;
      lua_pushinteger(L, CGWindowLevelForKey(kCGDockWindowLevelKey)) ;              lua_setfield(L, -2, "dock") ;
      lua_pushinteger(L, CGWindowLevelForKey(kCGMainMenuWindowLevelKey)) ;          lua_setfield(L, -2, "mainMenu") ;
      lua_pushinteger(L, CGWindowLevelForKey(kCGStatusWindowLevelKey)) ;            lua_setfield(L, -2, "status") ;
      lua_pushinteger(L, CGWindowLevelForKey(kCGModalPanelWindowLevelKey)) ;        lua_setfield(L, -2, "modalPanel") ;
      lua_pushinteger(L, CGWindowLevelForKey(kCGPopUpMenuWindowLevelKey)) ;         lua_setfield(L, -2, "popUpMenu") ;
      lua_pushinteger(L, CGWindowLevelForKey(kCGDraggingWindowLevelKey)) ;          lua_setfield(L, -2, "dragging") ;
      lua_pushinteger(L, CGWindowLevelForKey(kCGScreenSaverWindowLevelKey)) ;       lua_setfield(L, -2, "screenSaver") ;
      lua_pushinteger(L, CGWindowLevelForKey(kCGMaximumWindowLevelKey)) ;           lua_setfield(L, -2, "_MaximumWindowLevelKey") ;
      lua_pushinteger(L, CGWindowLevelForKey(kCGOverlayWindowLevelKey)) ;           lua_setfield(L, -2, "overlay") ;
      lua_pushinteger(L, CGWindowLevelForKey(kCGHelpWindowLevelKey)) ;              lua_setfield(L, -2, "help") ;
      lua_pushinteger(L, CGWindowLevelForKey(kCGUtilityWindowLevelKey)) ;           lua_setfield(L, -2, "utility") ;
      lua_pushinteger(L, CGWindowLevelForKey(kCGDesktopIconWindowLevelKey)) ;       lua_setfield(L, -2, "desktopIcon") ;
      lua_pushinteger(L, CGWindowLevelForKey(kCGCursorWindowLevelKey)) ;            lua_setfield(L, -2, "cursor") ;
      lua_pushinteger(L, CGWindowLevelForKey(kCGAssistiveTechHighWindowLevelKey)) ; lua_setfield(L, -2, "assistiveTechHigh") ;
//       lua_pushinteger(L, CGWindowLevelForKey(kCGNumberOfWindowLevelKeys)) ;         lua_setfield(L, -2, "kCGNumberOfWindowLevelKeys") ;
    return 1 ;
}

/// hs.drawing.defaultTextStyle() -> `hs.styledtext` attributes table
/// Function
/// Returns a table containing the default font, size, color, and paragraphStyle used by `hs.drawing` for text drawing objects.
///
/// Parameters:
///  * None
///
/// Returns:
///  * a table containing the default style attributes `hs.drawing` uses for text drawing objects in the `hs.styledtext` attributes table format.
///
/// Notes:
///  * This method returns the default font, size, color, and paragraphStyle used by `hs.drawing` for text objects.  If you modify a drawing object's defaults with `hs.drawing:setColor`, `hs.drawing:setTextFont`, or `hs.drawing:setTextSize`, the changes will not be reflected by this function.
static int default_textAttributes(lua_State *L) {
    lua_newtable(L) ;
// NOTE: Change this if you change the defaults in [HSDrawingViewText initWithFrame:]
      [LST_getLuaSkin() pushNSObject:[NSFont systemFontOfSize: 27]] ;                    lua_setfield(L, -2, "font") ;
      [LST_getLuaSkin() pushNSObject:[NSColor colorWithCalibratedWhite:1.0 alpha:1.0]] ; lua_setfield(L, -2, "color") ;
      [LST_getLuaSkin() pushNSObject:[NSParagraphStyle defaultParagraphStyle]] ;         lua_setfield(L, -2, "paragraphStyle") ;
    return 1 ;
}

/// hs.drawing.getTextDrawingSize(styledTextObject or theText, [textStyle]) -> sizeTable | nil
/// Method
/// Get the size of the rectangle necessary to fully render the text with the specified style so that is will be completely visible.
///
/// Parameters:
///  * styledTextObject - an object created with the hs.styledtext module or its table representation (see `hs.styledtext`).
///
///  The following simplified style format is supported for use with `hs.drawing:setText` and `hs.drawing.setTextStyle`.
///
///  * theText   - the text which is to be displayed.
///  * textStyle - a table containing one or more of the following keys to set for the text of the drawing object (if textStyle is nil or missing, the `hs.drawing` defaults are used):
///    * font      - the name of the font to use (default: the system font)
///    * size      - the font point size to use (default: 27.0)
///    * color     - ignored, but accepted for compatibility with `hs.drawing:setTextStyle()`
///    * alignment - a string of one of the following indicating the texts alignment within the drawing objects frame:
///      * "left"      - the text is visually left aligned.
///      * "right"     - the text is visually right aligned.
///      * "center"    - the text is visually center aligned.
///      * "justified" - the text is justified
///      * "natural"   - (default) the natural alignment of the text’s script
///    * lineBreak - a string of one of the following indicating how to wrap text which exceeds the drawing object's frame:
///      * "wordWrap"       - (default) wrap at word boundaries, unless the word itself doesn’t fit on a single line
///      * "charWrap"       - wrap before the first character that doesn’t fit
///      * "clip"           - do not draw past the edge of the drawing object frame
///      * "truncateHead"   - the line is displayed so that the end fits in the frame and the missing text at the beginning of the line is indicated by an ellipsis
///      * "truncateTail"   - the line is displayed so that the beginning fits in the frame and the missing text at the end of the line is indicated by an ellipsis
///      * "truncateMiddle" - the line is displayed so that the beginning and end fit in the frame and the missing text in the middle is indicated by an ellipsis
///
/// Returns:
///  * sizeTable - a table containing the Height and Width necessary to fully display the text drawing object, or nil if an error occurred
///
/// Notes:
///  * This function assumes the default values specified for any key which is not included in the provided textStyle.
///  * The size returned is an approximation and may return a width that is off by about 4 points.  Use the returned size as a minimum starting point. Sometimes using the "clip" or "truncateMiddle" lineBreak modes or "justified" alignment will fit, but its safest to add in your own buffer if you have the space in your layout.
///  * Multi-line text (separated by a newline or return) is supported.  The height will be for the multiple lines and the width returned will be for the longest line.
static int drawing_getTextDrawingSize(lua_State *L) {
    [LST_getLuaSkin() checkArgs:LS_TANY, LS_TTABLE | LS_TNIL | LS_TOPTIONAL, LS_TBREAK] ;

    NSSize theSize ;
    switch(lua_type(L, 1)) {
        case LUA_TSTRING:
        case LUA_TNUMBER: {
                NSString *theText  = [NSString stringWithUTF8String:lua_tostring(L, 1)];

                if (lua_isnoneornil(L, 2)) {
                    if (lua_isnil(L, 2)) lua_remove(L, 2) ;
                    lua_pushcfunction(L, default_textAttributes) ; lua_call(L, 0, 1) ;
                }

                NSDictionary *myStuff = modifyTextStyleFromStack(L, 2, @{
                                            @"style":[NSParagraphStyle defaultParagraphStyle],
                                            @"font" :[NSFont systemFontOfSize: 27],
                                            @"color":[NSColor colorWithCalibratedWhite:1.0 alpha:1.0]
                                        });
                if (!myStuff) {
                    lua_pushnil(L);
                    return 1;
                }

                theSize = [theText sizeWithAttributes:@{
                              NSFontAttributeName:[myStuff objectForKey:@"font"],
                    NSParagraphStyleAttributeName:[myStuff objectForKey:@"style"]
                }] ;
            } break ;
        case LUA_TUSERDATA:
        case LUA_TTABLE:  {
                NSAttributedString *theText = [LST_getLuaSkin() luaObjectAtIndex:1 toClass:"NSAttributedString"] ;
                theSize = [theText size] ;
            } break ;
        default:
            return luaL_argerror(L, 1, "string or hs.styledtext object expected") ;
    }

    lua_newtable(L) ;
        lua_pushnumber(L, ceil(theSize.height)) ; lua_setfield(L, -2, "h") ;
        lua_pushnumber(L, ceil(theSize.width)) ; lua_setfield(L, -2, "w") ;

    return 1 ;
}

// Lua metadata

static const luaL_Reg drawinglib[] = {
    {"getTextDrawingSize", drawing_getTextDrawingSize},
    {"defaultTextStyle",   default_textAttributes},
    {"disableScreenUpdates", disableUpdates},
    {"enableScreenUpdates", enableUpdates},

    {NULL,                 NULL}
};

static const luaL_Reg drawing_metalib[] = {
    {NULL, NULL}
};

int luaopen_hs_drawing_internal(lua_State *L) {
    LuaSkin *skin = LST_getLuaSkin();
    LST_setRefTable(skin, USERDATA_TAG, refTable,
        [skin registerLibraryWithObject:USERDATA_TAG
                              functions:drawinglib
                          metaFunctions:nil
                        objectFunctions:drawing_metalib]);

    pushCollectionTypeTable(L);
    lua_setfield(L, -2, "windowBehaviors") ;

    cg_windowLevels(L) ;
    lua_setfield(L, -2, "windowLevels") ;

    return 1;
}
