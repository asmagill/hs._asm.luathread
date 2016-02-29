Supported Hammerspoon Modules
=============================

This document contains information about what the status of various Hammerspoon modules is within a luathread instance provided by this module.  If you find any discrepancies or errors, please let me know!

Module auto-loading is not currently enabled.  This may be added once enough modules have been ported to justify it.

Individual modules can be installed by entering the appropriate subdirectory in `modules/` and using the same `make` command that you would use for building the LuaThread module itself;  they are also present in the v0.2 (and later) precompiled package and will be installed when you install it as described in README.md.

Note that these modules install themselves in a subdirectory of the `hs._asm.luathread` module, so the modified versions are only available from within a lua thread (your core application and any code you run normally with Hammerspoon are untouched).

### Special Consideration

There are many concerns that go into making something "*thread safe*".  The modules which have been ported to `hs._asm.luathread` or have been/will be written with `hs._asm.luathread` compatibility in mind take into account many of these considerations, but I cannot be positive that absolutely everything has been considered or taken into account.

Some of the considerations when working with threaded code include making sure that custom and sub-object names are unique, making sure that any use of run-loop or thread submission code targets the correct destination, that reference tables for modules are stored in the correct Lua instance, and that shared objects between threads (most notably the shared dictionary) obey proper locking behaviors, just to name a few.

I have verified that each of the modules marked with a status of `yes` load, that at least a few of their more useful functions work, and that any objects that use callbacks can be created and that the callbacks do fire, but I do not pretend that I have covered every possibility or tested them thoroughly.  I will note any limitations or changes as I find them and will update with fixes as I can.  Reports and help are appreciated.

However, some Objective-C objects and OS X libraries are not thread safe themselves, or expect to be run on a specific thread or only one thread at a time... and while I have tried to verify and work with this, I am sure that I've missed a few.

If you encounter any problems with a module in an `hs._asm.luathread` instance, check to see if the exact same use of the module works in Hammerspoon without `hs._asm.luathread` involved at all (this will be one of the first things asked, if you don't specify it in any error report).  Report problems that involve the use of `hs._asm.luathread` to this repository, not to the Hammerspoon one -- `hs._asm.luathread` is not, and probably never will be, a part of the Hammerspoon core.

### Core Hammerspoon Modules

Module             | Status   | Notes
-------------------|----------|------
hs.alert           | yes      | as of v0.3; given a dark blue background to distinguish source of visible alerts
hs.base64          | yes      | as of v0.3
hs.battery         | yes      | as of v0.6
hs.caffeinate      | yes      | as of v0.6
hs.crash           | yes      | as of v0.3
hs.doc             | yes      | as of v0.2; requires json and fs
hs.drawing         | limited  | as of v0.6, color module, defaultTextStyle, disableScreenUpdates, enableScreenUpdates, and getTextDrawingSize supported.  Uncertain if more will be added.
hs.fnutils         | yes      |
hs.fs              | yes      | volume fully supported as of v0.6
hs.geometry        | yes      |
hs.hash            | yes      | as of v0.3
hs.host            | yes      | as of v0.2
hs.inspect         | yes      |
hs.json            | yes      | as of v0.2
hs.logger          | yes      |
hs.pathwatcher     | yes      | as of v0.2
hs.settings        | yes      | as of v0.6
hs.spaces          | yes      | as of v0.7
hs.timer           | yes      | as of v0.6
hs.usb             | yes      | as of v0.2
hs.utf8            | yes      |
hs.wifi            | yes      | as of v0.6

Module             | Status   | Notes
-------------------|----------|------
hs.appfinder       | no       | requires application and window
hs.applescript     | no       | to be replaced with osascript
hs.application     | no       |
hs.audiodevice     | no       | uses `dispatch_get_main_queue`, no simple workaround yet
hs.brightness      | no       |
hs.chooser         | no       |
hs.console         | no       |
hs.dockicon        | no       |
hs.eventtap        | no       |
hs.expose          | no       |
hs.grid            | no       |
hs.hints           | no       |
hs.hotkey          | no       |
hs.http            | no       |
hs.httpserver      | no       | uses `dispatch_get_main_queue`, no simple workaround yet
hs.image           | no       | required for pasteboard
hs.ipc             | no       |
hs.itunes          | no       | requires alert, applescript, application
hs.javascript      | no       | to be replaced with osascript
hs.keycodes        | no       | probably not, unless eventtap is added
hs.layout          | no       |
hs.location        | no       |
hs.menubar         | no       | IIRC some NSMenu stuff must be in main thread; will check
hs.messages        | no       | requires applescript
hs.milight         | no       |
hs.mjomatic        | no       |
hs.mouse           | no       |
hs.network         | no       | uses `dispatch_get_main_queue`, no simple workaround yet
hs.notify          | no       |
hs.osascript       | no       |
hs.pasteboard      | no       | requires styledtext, drawing.color, image, sound
hs.redshift        | no       |
hs.screen          | no       | uses `dispatch_get_main_queue`, no simple workaround yet
hs.sound           | no       | required for pasteboard, uses `dispatch_get_main_queue`, no simple workaround yet
hs.speech          | no       |
hs.spotify         | no       | requires alert, applescript, application
hs.styledtext      | no       | required for pasteboard
hs.tabs            | no       |
hs.task            | no       | uses `dispatch_get_main_queue`, no simple workaround yet
hs.uielement       | no       |
hs.urlevent        | no       |
hs.webview         | no       |
hs.window          | no       |

### Core Functions

Function                        | Status   | Notes
--------------------------------|----------|------
hs._notify                      | yes      | as of v0.7, if you have the `hs._luathreadcoreadditions` module, used by showError
hs.cleanUTF8forConsole          | yes      | if you have the `hs._luathreadcoreadditions` module
hs.configdir                    | yes      | just copied from Hammerspoon
hs.docstrings_json_file         | yes      | just copied from Hammerspoon
hs.execute                      | yes      | included in module `_threadinit.lua`
hs.focus                        | yes      | as of v0.7, if you have the `hs._luathreadcoreadditions` module, used by showError
hs.getObjectMetatable           | yes      | if you have the `hs._luathreadcoreadditions` module
hs.help                         | yes      | not included by default; add `hs.help = require("hs.doc")` to `~/.hammerspoon/_init.lua`
hs.openConsole                  | yes      | as of v0.7, if you have the `hs._luathreadcoreadditions` module, used by showError
hs.printf                       | yes      | included in module `_threadinit.lua`
hs.processInfo                  | yes      | just copied from Hammerspoon
hs.rawprint                     | yes      | included in module `_threadinit.lua`
hs.reload                       | yes      | included in module `_threadinit.lua`
hs.showError                    | yes      | as of v0.7, if you have the `hs._luathreadcoreadditions` module

The following are unlikely to be added unless there is interest, as they concern visible aspects of Hammerspoon and don't directly apply to a background thread process.

Function                        | Status   | Notes
--------------------------------|----------|------
hs.accessibilityState           | no       |
hs.autoLaunch                   | no       |
hs.automaticallyCheckForUpdates | no       |
hs.checkForUpdates              | no       |
hs.completionsForInputString    | no       | no need in non-console thread
hs.consoleOnTop                 | no       |
hs.dockIcon                     | no       |
hs.menuIcon                     | no       |
hs.openAbout                    | no       |
hs.openPreferences              | no       |
hs.shutdownCallback             | no       |
hs.toggleConsole                | no       |
