--- === hs.luathread ===
---
--- Stuff about the module

local USERDATA_TAG = "hs.luathread"

local knownThreadTypes = {
    luaSkin = USERDATA_TAG..".luaskin",

-- maybe someday, if this works well...
--     lua51   = USERDATA_TAG..".lua51",
--     lua52   = USERDATA_TAG..".lua52",
--     lua53   = USERDATA_TAG..".lua53",
--     luajit  = USERDATA_TAG..".luajit",
}

package.loadlib(package.searchpath(USERDATA_TAG..".threadSupportInjection", package.cpath), "*")
local injector = require(USERDATA_TAG..".threadSupportInjection")
if injector.onMainThread and not injector.injectionStatus then
    error("injecting thread extensions into LuaSkin failed; Hammerspoon will probably crash soon unless you quit and restart", 2)
    return nil
end

-- we have to open the internal library globally first so sub-modules can see it
package.loadlib(package.searchpath(USERDATA_TAG..".internal", package.cpath), "*")

-- now load it for this module
local module   = require(USERDATA_TAG..".internal")
local objectMT = hs.getObjectMetatable(USERDATA_TAG)

-- private variables and methods -----------------------------------------

local sharedDictionaryBuilder = require(USERDATA_TAG.."._sharedDictionaryBuilder")

local runningThreads = setmetatable({}, { __mode = "v" })

-- Public interface ------------------------------------------------------

objectMT.sharedDictionary  = sharedDictionaryBuilder(USERDATA_TAG)

module.runningThreads = function()
    return runningThreads
end

-- Return Module Object --------------------------------------------------

setmetatable(module, {
    __index = function(self, key)
        for k, v in pairs(knownThreadTypes) do
            local constructor = "new"..k:sub(1,1):upper()..k:sub(2, #k)
            if key == constructor then
                local contructorFunction = require(knownThreadTypes[k])._new
                local wrappedFunction = function(...)
                    local result = contructorFunction(...)
                    if result then table.insert(runningThreads, result) end
                    return result
                end
                rawset(self, constructor, wrappedFunction)
                break
            end
        end
        return rawget(self, key)
    end,
})

return module
