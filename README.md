**This repository is being archived**

Recent updates to Hammerspoon to properly support coroutines have made the need for this less interesting to me at this time.

The current state of the Hammerspoon modules and LuaSkin are such that truly supporting multiple threads would essentially require a fundamental refactoring of LuaSkin and rewrite of almost all modules.

If I do revisit the idea in the future, it will require a full fork of Hammerspoon. No further updates will occur within this repository.

- - -

hs._asm.luathread
============

Well, got farther this time, and have some ideas, but I'm taking a break from this for now... it's not going as well as I had hoped and still causes Hammerspoon to beachball when *any* thread is too busy, so either I'm missing something or misunderstanding something or more likely, both.

- - -

An experiment to allow Hammerspoon to run LuaSkin code in alternate threads.  Very experimental.

This is intended to replace the previous `hs._asm.luathread` which had become very outdated with a solution that is more extendable and easier to maintain.

This module aims to allow you to run independant LuaSkin instances in alternate threads, but at present, the number of supported modules is limited, but should slowly grow.

In theory, it should also be possible to add threads which support alternate versions of Lua and possibly even LuaJIT, though at present, only LuaSkin is supported.

Additional documentation will follow.

The release bundle includes the hs._asm.luathread and hs._asm.luathread.luaskin modules as well as some slightly modified core modules which are installed in a special location so that only the thread aware LuaSkin will load them.
