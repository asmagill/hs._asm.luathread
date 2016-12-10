--- === hs._asm.module ===
---
--- Stuff about the module

-- _sharedDictionary._altthread = {
--     name = {
--         root              = { label = path, ... }
--         matchCriteria     = { string, ... } or string.dump(function(name, path, type)),
--         warnings          = boolean
--         maxDepth          = integer
--         subFolderBehavior = 0 ignored, 1 before, 2 mixed, 3 after
--         pruneEmpty        = boolean
--     },
-- }

local USERDATA_TAG = "hs._asm.filelistmenu._altthread"
local module = {}
local objectMT = {}

local FN_TYPE = { FILE = 1, DIR = 2 }

if not _instance then
    error("sub module " .. USERDATA_TAG .. " must be run in an alternate thread", 2)
end

local pathwatcher = require "hs.pathwatcher"
local fs          = require "hs.fs"

-- private variables and methods -----------------------------------------

objectMT.internals = setmetatable({}, { mode = "k" })

local generateMenuTemplate
generateMenuTemplate = function(self, startDir, depth)
    local state = objectMT.internals[self]
    local config = _sharedDictionary._altthread[state.name]
    depth = depth or 1
    local results, subdirs = {}, {}
    if depth > config.maxDepth then
        if config.warnings then
            print(USERDATA_TAG .. ": Maximum search depth of " .. config.maxDepth .." reached for menu " .. state.name .. " at " .. startDir)
        end
    else
--         print(startDir, depth)
        for name in fs.dir(startDir) do
            local label, acceptAsFile
            if type(config.matchCriteria) == "table" then
                for _, expression in ipairs(config.matchCriteria) do
                    label = name:match(expression)
                    if label then break end
                end
            elseif type(config.matchCriteria) == "string" then
                acceptAsFile, label = load(config.matchCriteria)(name, startDir, "file")
                if acceptAsFile and not label then label = name end
                if not acceptAsFile then label = nil end
            end
            if label then
                acceptAsFile = true
                table.insert(results, {
                    title = label,
                    fn    = FN_TYPE.FILE,
                    path  = startDir .. "/" .. name
                })
            end
            -- check subdirectories only if the directory was not accepted as a "file"
            if not acceptAsFile and fs.attributes(startDir.."/"..name, "mode") == "directory" then
                if config.subFolderBehavior ~= 0 and not (name == "." or name == "..") then
                    local label, checkSubDirs
                    if type(config.matchCriteria) == "table" then
                        checkSubDirs, label = true, name
                    elseif type(config.matchCriteria) == "string" then
                        checkSubDirs, label = load(config.matchCriteria)(name, startDir, "directory")
                        if checkSubDirs and not label then label = name end
                        if not checkSubDirs then label = nil end
                    end
                    if checkSubDirs then
                        local subResults = generateMenuTemplate(self, startDir .. "/" .. name, depth + 1)
                        if next(subResults) or not config.pruneEmpty then
                            table.insert(results, {
                                title = label,
                                menu  = next(subResults) and subResults,
                                fn    = FN_TYPE.DIR,
                                path  = startDir .. "/" .. name
                            })
                        end
                    end
                end
            end
        end
    end
    table.sort(results, function(c,d)
        -- == 0 or 2 (ignored or mixed) or both are the same type, then sort by title
        if (config.subFolderBehavior % 2 == 0) or (c.menu and d.menu) or not (c.menu or d.menu) then
            return string.lower(c.title) < string.lower(d.title)
        else
            if config.subFolderBehavior == 1 then -- == 1 (before)
                return c.menu and true
            else                                  -- == 3 (after)
                return d.menu and true
            end
        end
    end)
    return results
end

local buildMenuTable = function(self)
    local state = objectMT.internals[self]
    local config = _sharedDictionary._altthread[state.name]
    _instance:push("_beginUpdate", state.name)
    local menu = {}
    for i, v in pairs(config.root) do
        table.insert(menu, { title = tostring(i), menu = generateMenuTemplate(self, v), fn = FN_TYPE.DIR, path = v })
    end
    local key, value = next(menu)
    -- if there was only one root given, then drop the label for it
    if not next(menu, key) then
        menu = value.menu
    end
    _instance:push("_endUpdate", state.name, menu)
end

local changeWatcher = function(self, paths)
print("entered change watcher")
    local state = objectMT.internals[self]
    local sd = _sharedDictionary._altthread
    local config = sd[state.name]
    local name, path
    for _, v in ipairs(paths) do
        name = string.sub(v,string.match(v, '^.*()/')+1)
        path = string.sub(v, 1, string.match(v, '^.*()/')-1)
        if type(config.matchCriteria) == "table" then
            for __, v2 in ipairs(config.matchCriteria) do
                if name:match(v2) then
                    doUpdate = true
                    break
                end
            end
            if doUpdate then break end
        elseif type(config.matchCriteria) == "string" then
            local accept, _ = load(config.matchCriteria)(name, path, "update")
            if accept then
                doUpdate = true
                break
            end
        end
    end
    if doUpdate then
        config.lastChangeSeen = os.date()
        if config.warnings then print(USERDATA_TAG .. ": Menu " .. state.name .." Updated: " .. path .. "/" .. name) end
        buildMenuTable(self)
        _sharedDictionary._altthread = sd
    end
end

local _new = function(name)
    local self = {}
    objectMT.internals[self] = {
        name = name
    }
    return setmetatable(self, objectMT)
end

-- Public interface ------------------------------------------------------

objectMT.start = function(self)
    local state = objectMT.internals[self]
    local config = _sharedDictionary._altthread[state.name]
    if not state.watchers then
        state.watchers = {}
        for _, v in pairs(config.root) do
            table.insert(state.watchers, pathwatcher.new(v, function(paths)
                changeWatcher(self, paths)
            end):start())
        end
    end
    buildMenuTable(self)
    return self
end

objectMT.stop = function(self)
    local state = objectMT.internals[self]
--     local config = _sharedDictionary._altthread[state.name]
    if state.watchers then
        for _, v in ipairs(state.watchers) do
            v:stop()
        end
        state.watchers = nil
    end
    return self
end

objectMT.update = function(self)
    buildMenuTable(self)
end

objectMT.__index = objectMT

module.menus = {}

module.new = function(name)
    assert(type(name) == "string", "name must be provided and must be a string")
    assert(not module.menus[name], "name must be unique")
    assert(_sharedDictionary._altthread[name], "configuration must exist in _sharedDictionary")
    module.menus[name] = _new(name)
end

module.start = function(name)
    assert(type(name) == "string", "name must be provided and must be a string")
    assert(module.menus[name], "name must first be created with new")
    module.menus[name]:start()
end

module.stop = function(name)
    assert(type(name) == "string", "name must be provided and must be a string")
    assert(module.menus[name], "name must first be created with new")
    module.menus[name]:stop()
end

module.update = function(name)
    assert(type(name) == "string", "name must be provided and must be a string")
    assert(module.menus[name], "name must first be created with new")
    module.menus[name]:update()
end

module.delete = function(name)
    assert(type(name) == "string", "name must be provided and must be a string")
    assert(module.menus[name], "name must first be created with new")
    module.menus[name]:stop()
    module.menus[name] = nil
end

-- Return Module Object --------------------------------------------------

return module
