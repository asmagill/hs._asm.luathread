hs.luathread
============

An experiment to allow Hammerspoon to run LuaSkin code in alternate threads.  Very experimental and requires threadable branch of Hammerspoon at https://github.com/asmagill/hammerspoon/tree/threadable.

This is intended to replace the previous `hs._asm.luathread` which had become very outdated with a solution that is more extendable and easier to maintain.

The primary application thread runs LuaSkin which is based on Lua 5.3 and your current configuration should run as is without modification.

This module aims to allow you to run independant LuaSkin instances in alternate threads, but at present, the number of supported modules is limited, but should slowly grow.

In theory, it should also be possible to add threads which support alternate versions of Lua and possibly even LuaJIT, though at present, only LuaSkin is supported.

Additional documentation will follow.
