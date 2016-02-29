
-- local imagemod    = require("hs.image") -- make sure we know about hsimage userdata for image functions

local module      = require("hs.drawing.internal")
module.color      = require("hs.drawing.color")
-- local styledtext  = require("hs.styledtext")

local _kMetaTable = {}
_kMetaTable._k = {}
_kMetaTable.__index = function(obj, key)
        if _kMetaTable._k[obj] then
            if _kMetaTable._k[obj][key] then
                return _kMetaTable._k[obj][key]
            else
                for k,v in pairs(_kMetaTable._k[obj]) do
                    if v == key then return k end
                end
            end
        end
        return nil
    end
_kMetaTable.__newindex = function(obj, key, value)
        error("attempt to modify a table of constants",2)
        return nil
    end
_kMetaTable.__pairs = function(obj) return pairs(_kMetaTable._k[obj]) end
_kMetaTable.__tostring = function(obj)
        local result = ""
        if _kMetaTable._k[obj] then
            local width = 0
            for k,v in pairs(_kMetaTable._k[obj]) do width = width < #k and #k or width end
            for k,v in require("hs.fnutils").sortByKeys(_kMetaTable._k[obj]) do
                result = result..string.format("%-"..tostring(width).."s %s\n", k, tostring(v))
            end
        else
            result = "constants table missing"
        end
        return result
    end
_kMetaTable.__metatable = _kMetaTable -- go ahead and look, but don't unset this

local _makeConstantsTable = function(theTable)
    local results = setmetatable({}, _kMetaTable)
    _kMetaTable._k[results] = theTable
    return results
end

local fnutils = require("hs.fnutils")

-- module.fontTraits      = _makeConstantsTable(module.fontTraits)
module.windowBehaviors = _makeConstantsTable(module.windowBehaviors)
module.windowLevels    = _makeConstantsTable(module.windowLevels)

-- module.fontNames =           styledtext.fontNames
-- module.fontNamesWithTraits = styledtext.fontNamesWithTraits
-- module.fontTraits =          styledtext.fontTraits

return module
