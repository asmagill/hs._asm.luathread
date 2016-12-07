hs.luathread
============

An experiment to allow Hammerspoon to run LuaSkin code in alternate threads.  Very experimental.

This is intended to replace the previous `hs._asm.luathread` which had become very outdated with a solution that is more extendable and easier to maintain.

This module aims to allow you to run independant LuaSkin instances in alternate threads, but at present, the number of supported modules is limited, but should slowly grow.

In theory, it should also be possible to add threads which support alternate versions of Lua and possibly even LuaJIT, though at present, only LuaSkin is supported.

Additional documentation will follow.

The release bundle includes the hs.luathread and hs.luaskin modules as well as some slightly modified core modules which are installed in a special location so that only the thread aware LuaSkin will load them.
