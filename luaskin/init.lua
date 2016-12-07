--- === hs.luathread.luaskin ===
---
--- Stuff about the module

local USERDATA_TAG = "hs.luathread.luaskin"

local module   = require(USERDATA_TAG..".internal")
local objectMT = hs.getObjectMetatable(USERDATA_TAG)

-- private variables and methods -----------------------------------------

local threadInitFile = package.searchpath(USERDATA_TAG.."._threadinit", package.path)
local overridesDir   = threadInitFile:gsub("/_threadinit.lua$", "")
module._initialAssignments({
    coreinitfile         = threadInitFile,
    configdir            = hs.configdir,
    docstrings_json_file = hs.docstrings_json_file,
    processInfo          = hs.processInfo,
    path                 = overridesDir.."/?.lua"..";"..overridesDir.."/?/init.lua"..";"..package.path,
    cpath                = overridesDir.."/?.so"..";"..package.cpath,
})
module._initialAssignments = nil -- should only be called once, then never again

-- local sharedDictionaryBuilder = require(USERDATA_TAG:gsub("%.luaskin$", "").."._sharedDictionaryBuilder")

-- Public interface ------------------------------------------------------

-- Return Module Object --------------------------------------------------

return module
