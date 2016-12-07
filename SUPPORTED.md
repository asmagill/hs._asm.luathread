### Summary of Support

This is a brief summary of what has been updated, either in this module, or in the threadable branch of Hammerspoon at https://github.com/asmagill/hammerspoon/tree/threadable.

Inclusion here just indicates that the known necessary changes have been made -- additional testing is still required and you should procede with extreme caution.

Module                                | Status  | Notes
--------------------------------------|---------|------
hs                                    | Partial | See below
hs._coresetup                         |   YES   | Wrapped by `_threadinit.lua`
hs.alert                              |   NO    |   Needs thread safe drawing
hs.appfinder                          |   NO    | Requires application, window
hs.applescript                        |   NO    | Requires osascript
hs.application                        |   NO    | Requires window
hs.application.watcher                |   NO    |
hs.audiodevice                        |   NO    |
hs.audiodevice.datasource             |   NO    |
hs.audiodevice.watcher                |   NO    |
hs.base64                             |   YES   |
hs.battery                            |   YES   |
hs.battery.watcher                    |   YES   |
hs.brightness                         |   YES   |
hs.caffeinate                         |   NO    | Requires applescript
hs.caffeinate.watcher                 |   NO    |
hs.chooser                            |   NO    |   NSView should be created on main thread only
hs.console                            |   NO    | Requires webview.toolbar
hs.crash                              |   YES   |
hs.distributednotifications           |   NO    |
hs.doc                                |   YES   | Except for hsdocs submodule
hs.doc.hsdocs                         |   NO    | Requires webview, httpserver, urlevent
hs.doc.markdown                       |   YES   |
hs.dockicon                           |   YES   |
hs.drawing                            | Partial | Non-drawing functions and constants only
hs.drawing.color                      |   YES   |
hs.eventtap                           |   NO    |
hs.eventtap.event                     |   NO    |
hs.expose                             |   NO    |   Needs thread safe drawing
hs.fnutils                            |   YES   |
hs.fs                                 |   YES   |
hs.fs.volume                          |   YES   |
hs.geometry                           |   YES   |
hs.grid                               |   NO    |   Needs thread safe drawing
hs.hash                               |   YES   |
hs.hints                              |   NO    |   NSView should be created on main thread only
hs.host                               |   YES   |
hs.hotkey                             |   NO    |
hs.hotkey.modal                       |   NO    |
hs.http                               |   NO    |
hs.httpserver                         |   NO    |
hs.httpserver.hsminweb                |   NO    |
hs.httpserver.hsminweb.cgilua         |   NO    |
hs.httpserver.hsminweb.cgilua.lp      |   NO    |
hs.httpserver.hsminweb.cgilua.urlcode |   NO    |
hs.image                              |   YES   |
hs.inspect                            |   YES   |
hs.ipc                                |   NO    | Can we make MachPort selectable so can use cli to access different skins?
hs.itunes                             |   NO    | Requires alert, applescript, application
hs.javascript                         |   NO    | Requires osascript
hs.json                               |   YES   |
hs.keycodes                           |   YES   |
hs.layout                             |   NO    |
hs.location                           |   NO    |
hs.location.geocoder                  |   NO    |
hs.logger                             |   YES   |
hs.menubar                            |   NO    |
hs.messages                           |   NO    | Requires applescript
hs.milight                            |   NO    |
hs.mjomatic                           |   NO    |
hs.mouse                              |   NO    |
hs.network                            |   NO    |
hs.network.configuration              |   NO    |
hs.network.host                       |   NO    |
hs.network.ping                       |   NO    |
hs.network.ping.echoRequest           |   NO    |
hs.network.reachability               |   NO    |
hs.noises                             |   NO    |
hs.notify                             |   NO    |
hs.osascript                          |   NO    |
hs.pasteboard                         |   NO    |
hs.pathwatcher                        |   YES   |
hs.redshift                           |   NO    | Requires window.filter
hs.screen                             |   YES   |
hs.screen.watcher                     |   YES   |
hs.settings                           |   YES   |
hs.sharing                            |   NO    |
hs.socket                             |   NO    |
hs.socket.udp                         |   NO    |
hs.sound                              |   NO    |
hs.spaces                             |   NO    |
hs.speech                             |   NO    |
hs.speech.listener                    |   NO    |
hs.spotify                            |   NO    | Requires alert, applescript, application
hs.styledtext                         |   YES   |
hs.tabs                               |   NO    |   Needs thread safe drawing
hs.task                               |   NO    |
hs.timer                              |   YES   |
hs.timer.delayed                      |   YES   |
hs.uielement                          |   NO    |
hs.uielement.watcher                  |   NO    |
hs.urlevent                           |   NO    |
hs.usb                                |   YES   |
hs.usb.watcher                        |   YES   |
hs.utf8                               |   YES   |
hs.vox                                |   NO    | Requires alert, applescript, application
hs.webview                            |   NO    |   NSView should be created on main thread only
hs.webview.datastore                  |   NO    |
hs.webview.toolbar                    |   NO    |
hs.webview.usercontent                |   NO    |
hs.wifi                               |   YES   |
hs.wifi.watcher                       |   YES   |
hs.window                             |   NO    | Requires application
hs.window.filter                      |   NO    | Requires application, window, uielement.watcher, spaces
hs.window.highlight                   |   NO    |   Needs thread safe drawing
hs.window.layout                      |   NO    | Requires window.filter, eventtap
hs.window.switcher                    |   NO    |   Needs thread safe drawing
hs.window.tiling                      |   YES   |


Members of `hs`                 | Status  | Notes
--------------------------------|---------|------
hs.accessibilityState           |   YES   | included in hs.luathread.luaskin._coresupport
hs.assert                       |   YES   |
hs.autoLaunch                   |   YES   | included in hs.luathread.luaskin._coresupport
hs.automaticallyCheckForUpdates |   NO    | No-OP included in hs.luathread.luaskin._coresupport
hs.canCheckForUpdates           |   NO    | No-OP included in hs.luathread.luaskin._coresupport
hs.checkForUpdates              |   NO    | No-OP included in hs.luathread.luaskin._coresupport
hs.cleanUTF8forConsole          |   YES   | included in hs.luathread.luaskin._coresupport
hs.completionsForInputString    |   NO    | No-OP included in module `_threadinit.lua`
hs.configdir                    |   YES   |
hs.consoleOnTop                 |   YES   | included in hs.luathread.luaskin._coresupport
hs.dockIcon                     |   YES   |
hs.docstrings_json_file         |   YES   |
hs.execute                      |   YES   |
hs.focus                        |   YES   | included in hs.luathread.luaskin._coresupport
hs.getObjectMetatable           |   YES   | included in hs.luathread.luaskin._coresupport
hs.handleLogMessage             |   YES   | override in module `_threadinit.lua`
hs.help                         |   YES   |
hs.hsdocs                       |   NO    | No-OP included in module `_threadinit.lua`
hs.luaSkinLog                   |   YES   |
hs.menuIcon                     |   YES   | included in hs.luathread.luaskin._coresupport
hs.openAbout                    |   YES   | included in hs.luathread.luaskin._coresupport
hs.openConsole                  |   YES   | included in hs.luathread.luaskin._coresupport
hs.openPreferences              |   YES   | included in hs.luathread.luaskin._coresupport
hs.printf                       |   YES   |
hs.processInfo                  |   YES   | included in module `_threadinit.lua`
hs.rawprint                     |   YES   |
hs.reload                       |   YES   | included in module `_threadinit.lua`
hs.showError                    |   YES   | override in module `_threadinit.lua`
hs.shutdownCallback             |   NO    | * Requires change in cancel/reload code
hs.toggleConsole                |   NO    | * Requires application, window
hs._exit                        |   YES   | included in module `_threadinit.lua`
hs._extensions                  |   YES   |
hs._logmessage                  |   YES   | included in module `_threadinit.lua`
hs._notify                      |   YES   | included in hs.luathread.luaskin._coresupport
