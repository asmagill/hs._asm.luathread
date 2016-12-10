--- === hs._asm.module ===
---
--- Stuff about the module

local USERDATA_TAG = "hs._asm.filelistmenu.threaded"
local ALT_USERDATA_TAG = USERDATA_TAG:match("^(.*)%.%w+$") .. "._altthread"

local module = {}
local objectMT = {}

local FN_TYPE = { FILE = 1, DIR = 2 }

local luathread   = require "hs._asm.luathread"
local menubar     = require "hs.menubar"
local application = require "hs.application"
local eventtap    = require "hs.eventtap"
local inspect     = require "hs.inspect"
local stext       = require "hs.styledtext"
local timer       = require "hs.timer"

-- private variables and methods -----------------------------------------

-- verify a function can be passed from this thread to the alternate thread
--   criteria: 1. is a lua function (not C)
--             2. has 0 or 1 up-values and that 1 is _ENV
local validateFunction = function(fn)
    local nups = debug.getinfo(fn,"u").nups
    if nups > 1 then
        error("function has up-values", 2)
    elseif nups == 1 then
        if debug.getupvalue(fn, 1) ~= "_ENV" then
            error("function up-value is not the global environment", 2)
        end
    end
    if debug.getinfo(fn, "S").what ~= "Lua" then
        error("function is not defined in Lua", 2)
    end
    return true
end

-- Hold on to this... it's the right idea, but isn't enough because we're trying to use the
-- shared dictionary too soon... need to ponder...
-- possible options: wrap sharedDictionary so it can queue up updates as well
--                   allow submission to take data as well, like push on the alt side
--                   add proper serialization to Hammerspoon
--
-- submit to thread... queues submissions until the thread is actually executing...
local submitToThread
submitToThread = function(submission)
    module.queue = module.queue or {}
    if submission ~= "-- queue recheck --" then
        table.insert(module.queue, submission)
    end
    if  module.skinReady and module.luaskin and module.luaskin:isExecuting() then
        if module.queueTimer then
            module.queueTimer:stop()
            module.queueTimer = nil
        end
        while #module.queue > 0 do
            module.luaskin:submit(table.remove(module.queue, 1))
        end
    else
        if not module.queueTimer then
            module.queueTimer = timer.doEvery(1, function() submitToThread("-- queue recheck --") end)
        end
    end
end

-- convert FN_TYPE into a real function
local buildMenuFromTemplate
buildMenuFromTemplate = function(self, menuTemplate)
    local state  = objectMT.internals[self]
--     local config = module._sharedDictionary._altthread[self.name]
    for i, v in ipairs(menuTemplate) do
        if v.fn == FN_TYPE.FILE then
            v.fn = function() state.fileTemplate(v.path) end
        elseif v.fn == FN_TYPE.DIR then
            v.fn = function() state.folderTemplate(v.path) end
        end
        if v.menu then v.menu = buildMenuFromTemplate(self, v.menu) end
    end
    return menuTemplate
end

-- updates menu title/icon view
local updateMenuView = function(self)
    local state  = objectMT.internals[self]
--     local config = module._sharedDictionary._altthread[self.name]
    if state.menuUserdata then
        if state.menuView == 0 and state.icon then
            if state.menuUserdata:setIcon(state.icon) then
                state.menuUserdata:setTitle(nil)
            else
                state.menuUserdata:setTitle(self.name)
                state.menuUserdata:setIcon(nil)
            end
        else
            state.menuUserdata:setIcon(nil)
            state.menuUserdata:setTitle(self.name)
            if state.menuView == 2 and state.icon then
                state.menuUserdata:setIcon(state.icon)
            end
        end
    end
end

-- handles showForMenu method and option menu view changes
local fnMenuViewUpdate = function(self, x)
    local state  = objectMT.internals[self]
--     local config = module._sharedDictionary._altthread[self.name]
    if type(x) ~= "nil" then
        local y = math.tointeger(x) or 0
        if y < 0 or y > 2 then y = 0 end
        if type(x) == "string" then
            if string.lower(x) == "icon"  then y = 0 end
            if string.lower(x) == "label" then y = 1 end
            if string.lower(x) == "both"  then y = 2 end
        end
        state.menuView = y
        updateMenuView(self)
        return self
    else
        return state.menuView
    end
end

-- force update from alternate thread
local doManualUpdate = function(self)
    local state  = objectMT.internals[self]
    if state.menuUserdata then
        submitToThread([[ require("]] .. ALT_USERDATA_TAG .. [[").update("]] .. self.name .. [[") ]])
    end
    return self
end

-- sort already present menu
local sortMenu
sortMenu = function(menu, behavior)
    table.sort(menu, function(c,d)
        if (behavior % 2 == 0) or (c.menu and d.menu) or not (c.menu or d.menu) then -- == 0 or 2 (ignored or mixed)
            return string.lower(c.title) < string.lower(d.title)
        else
            if behavior == 1 then                                 -- == 1 (before)
                return c.menu and true
            else                                                  -- == 3 (after)
                return d.menu and true
            end
        end
    end)
    for _,v in ipairs(menu) do
        if v.menu then sortMenu(v.menu, behavior) end
    end
end

-- handles subFolders method and option menu changes
local fnSubFolderDisplay = function(self, x)
    local state  = objectMT.internals[self]
    local sd = module._sharedDictionary._altthread
    local config = sd[self.name]
    if type(x) ~= "nil" then
        local y = math.tointeger(x) or 0
        if y < 0 or y > 3 then y = 0 end
        if type(x) == "string" then
            if string.lower(x) == "ignore" then y = 0 end
            if string.lower(x) == "before" then y = 1 end
            if string.lower(x) == "mixed"  then y = 2 end
            if string.lower(x) == "after"  then y = 3 end
        end
        local populateNeeded = (y == 0) or (config.subFolderBehavior == 0)
        config.subFolderBehavior = y
        module._sharedDictionary._altthread = sd
        if populateNeeded then
            doManualUpdate(self)
        else
            sortMenu(state.menu, config.subFolderBehavior)
        end
        return self
    else
        return config.subFolderBehavior
    end
end

-- menu callback - returns menu table
local provideMenuTable = function(self, mods)
    local state  = objectMT.internals[self]
    local config = module._sharedDictionary._altthread[self.name]
    local showControlMenu = next(state.controlMenuMods) and true or false
    for i,v in pairs(mods) do if v and not state.controlMenuMods[i] then showControlMenu = false end end
    for i,v in pairs(state.controlMenuMods) do if v and not mods[i] then showControlMenu = false end end
    if not showControlMenu and state.rightMouseControlMenu then
        showControlMenu = eventtap.checkMouseButtons()["right"]
    end

    local menuToReturn = state.menu
    if showControlMenu then
        menuToReturn = {
            { title = self.name.." fileListMenu" },
            { title = "-" },
            { title = "Sub Directories - Ignore",  checked = ( config.subFolderBehavior == 0 ), fn = function() fnSubFolderDisplay(self, 0) end },
            { title = "Sub Directories - Before",  checked = ( config.subFolderBehavior == 1 ), fn = function() fnSubFolderDisplay(self, 1) end },
            { title = "Sub Directories - Mixed",   checked = ( config.subFolderBehavior == 2 ), fn = function() fnSubFolderDisplay(self, 2) end },
            { title = "Sub Directories - After",   checked = ( config.subFolderBehavior == 3 ), fn = function() fnSubFolderDisplay(self, 3) end },
            { title = "Prune Empty Directories",   checked = ( config.pruneEmpty ), fn = function()
                local sd = module._sharedDictionary._altthread
                local config = sd[self.name]
                config.pruneEmpty = not config.pruneEmpty
                module._sharedDictionary._altthread = sd
                doManualUpdate(self)
            end },
            { title = "-" },
            { title = "Show Icon",                 checked = ( state.menuView == 0 ), fn = function() fnMenuViewUpdate(self, 0) end  },
            { title = "Show Label",                checked = ( state.menuView == 1 ), fn = function() fnMenuViewUpdate(self, 1) end  },
            { title = "Show Both",                 checked = ( state.menuView == 2 ), fn = function() fnMenuViewUpdate(self, 2) end  },
            { title = "-" },
            { title = "Repopulate Now", fn = function() doManualUpdate(self) end },
            { title = "-" },
            { title = "List generated: "..state.menuLastUpdated, disabled = true },
            { title = "Last change seen: "..config.lastChangeSeen, disabled = true },
            { title = "-" },
            { title = "Remove Menu", fn = function() self:deactivate() end, disabled = not state.menuUserdata:isInMenubar()  },
        }
        if #config.root == 1 then
            table.insert(menuToReturn, 2,
                { title = "Select "..config.root[1], fn = function() state.folderTemplate(config.root[1]) end }
            )
        end
    end
    if not menuToReturn then
        menuToReturn = {
            { title = "menu not populated yet", disabled = true }
        }
    end

    local results = {}
    if state.updating then
        table.insert(results, { title = stext.new("Updating...", {
                                    font = stext.convertFont(stext.defaultFonts.menu, stext.fontTraits.italicFont),
                                    color = { list="x11", name="coral"},
                                    paragraphStyle = { alignment = "center" },
                                  }), disabled = true
                              })
        table.insert(results, { title = "-" })
    end
    for i, v in ipairs(menuToReturn) do table.insert(results, v) end

    table.insert(results, { title = "-" })
    table.insert(results, { title = stext.new("fileListMenu for Hammerspoon\nthreaded", {
                                font = stext.convertFont(stext.defaultFonts.menu, stext.fontTraits.italicFont),
                                color = { list="x11", name="royalblue"},
                                paragraphStyle = { alignment = "right" },
                              }), disabled = true
                          })
--     print(inspect(menuToReturn))
    return results
end

-- create menu in menubar and set callback function
local activateMenu = function(self)
    local state  = objectMT.internals[self]
--     local config = module._sharedDictionary._altthread[self.name]
    if not state.menuUserdata then
        submitToThread([[ require("]] .. ALT_USERDATA_TAG .. [[").new("]] .. self.name .. [[") ]])
        state.menuUserdata = menubar.new()

        updateMenuView(self)
        state.menuUserdata:setMenu(function(mods) return provideMenuTable(self, mods) end)
        submitToThread([[ require("]] .. ALT_USERDATA_TAG .. [[").start("]] .. self.name .. [[") ]])
        submitToThread([[ require("]] .. ALT_USERDATA_TAG .. [[").update("]] .. self.name .. [[") ]])
    end
    return self
end

local deactivateMenu = function(self)
    local state  = objectMT.internals[self]
--     local config = module._sharedDictionary._altthread[self.name]
    if state.menuUserdata then
        submitToThread([[ require("]] .. ALT_USERDATA_TAG .. [[").delete("]] .. self.name .. [[") ]])
        state.menuUserdata:delete()
    end
    state.menu = nil
    state.menuUserdata = nil
    setmetatable(self, nil)
end


-- receives output from alternate thread
local handleOutput = function(obj, output)
    if #output > 0 then
        if output:match("\n-- Done.\n$") then
            module.skinReady = true
        else
            print(string.format("~~ unexpected output: <%s>", output))
        end
    end
end

-- receives results from alternate thread (menu updates)
local handleResults = function(obj, results)
    if #results > 0 then
        if results[1] == "_beginUpdate" then
            local name = results[2]
            local self = objectMT.internals[name]
            local state  = objectMT.internals[self]
            state.updating = true
        elseif results[1] == "_endUpdate" then
            local name, menuTemplate = results[2], results[3]
            local self = objectMT.internals[name]
            local state  = objectMT.internals[self]
            state.menu = buildMenuFromTemplate(self, menuTemplate)
--             print(inspect(menuTemplate))
            state.updating = false
            state.menuLastUpdated = os.date()
        else
            print(string.format("~~ %d unexpected results pushed: %s", #results, (inspect(results)))) -- :gsub("[%s+]", " "))))
        end
    end
end

objectMT.internals = setmetatable({}, { mode = "kv" })

-- Public interface ------------------------------------------------------

module.luaskin = luathread.newLuaSkin(USERDATA_TAG):resultsCallback(handleResults)
                                                   :printCallback(handleOutput)
-- submitToThread("hs._threadPrintResults = false")

-- local startTime = os.time()
-- while not module.luaskin:isExecuting() and (os.time() - startTime) < 10 do
--     timer.usleep(10000)
-- end
-- if not module.luaskin:isExecuting() then
--     error("LuaSkin taking too long to start", 2)
-- end

module._sharedDictionary = module.luaskin:sharedDictionary()
module._sharedDictionary._altthread = {}

module.new = function(name)
    name = tostring(name)
    assert(not objectMT.internals[name], "label must be unique")
    local self = { name = name }
    objectMT.internals[self] = {
        fileTemplate          = function(x) application.launchOrFocus(x) end,
        folderTemplate        = function(x) os.execute([[open -a Finder "]]..x..[["]]) end,
        menuLastUpdated       = "not yet",
        menuView              = 0,
        controlMenuMods       = { ["ctrl"]=true },
        rightMouseControlMenu = true,
        updating              = false,
    }
    objectMT.internals[name] = self
    local sd = module._sharedDictionary._altthread
    sd[name] = {
        matchCriteria     = { "([^/]+)%.app$" },
        root              = { "/Applications" },
        warnings          = false,
        pruneEmpty        = true,
        maxDepth          = 10,
        subFolderBehavior = 0,
        lastChangeSeen    = "not yet",
    }
    module._sharedDictionary._altthread = sd
    return setmetatable(self, objectMT)
end

objectMT.activate = activateMenu

objectMT.deactivate = deactivateMenu

objectMT.showForMenu = fnMenuViewUpdate

objectMT.subFolders = fnSubFolderDisplay

objectMT.menuIcon = function(self, ...)
    local state  = objectMT.internals[self]
--     local config = module._sharedDictionary._altthread[self.name]
    local x = table.pack(...)
    if x.n > 0 then
        x = x[1]
        if type(x) ~= "string" and type(x) ~= "userdata" and type(x) ~= "nil" then
            state.icon = tostring(x)
        else
            state.icon = x
        end
        updateMenuView(self)
        return self
    else
        return state.icon
    end
end
-- will break _altthread until we come up with a plan
-- objectMT.menuLabel = function(self, ...)
-- --     local state  = objectMT.internals[self]
-- --     local config = module._sharedDictionary._altthread[self.name]
--     local x = table.pack(...)
--     if x.n > 0 then
--         x = x[1]
--         if type(x) ~= "string" and type(x) ~= "nil" then
--             self.name = tostring(x)
--         else
--             self.name = x
--         end
--         updateMenuView(self)
--         return self
--     else
--         return self.name
--     end
-- end

objectMT.subFolderDepth = function(self, x)
--     local state  = objectMT.internals[self]
    local sd = module._sharedDictionary._altthread
    local config = sd[self.name]
    if type(x) == "number" then
        config.maxDepth = x
        module._sharedDictionary._altthread = sd
        doManualUpdate(self)
        return self
    else
        return config.maxDepth
    end
end

objectMT.showWarnings = function(self, x)
--     local state  = objectMT.internals[self]
    local sd = module._sharedDictionary._altthread
    local config = sd[self.name]
    if type(x) == "boolean" then
        config.warnings = x
        module._sharedDictionary._altthread = sd
        return self
    else
        return config.warnings
    end
end

objectMT.controlMenu = function(self, x)
    local state  = objectMT.internals[self]
--     local config = module._sharedDictionary._altthread[self.name]
    if type(x) == "table" then
        state.controlMenuMods = x
        return self
    else
        return state.controlMenuMods
    end
end

objectMT.rightButtonSupport = function(self, x)
    local state  = objectMT.internals[self]
--     local config = module._sharedDictionary._altthread[self.name]
    if type(x) == "boolean" then
        state.rightMouseControlMenu = x
        return self
    else
        return state.rightMouseControlMenu
    end
end

objectMT.pruneEmptyDirs = function(self, x)
--     local state  = objectMT.internals[self]
    local sd = module._sharedDictionary._altthread
    local config = sd[self.name]
    if type(x) ~= "nil" then
        config.pruneEmpty = x
        module._sharedDictionary._altthread = sd
        doManualUpdate(self)
        return self
    else
        return config.pruneEmpty
    end
end

objectMT.actionFunction = function(self, ...)
    local state  = objectMT.internals[self]
--     local config = module._sharedDictionary._altthread[self.name]
    local args = table.pack(...)
    local x = args[1]
    if type(x) == "function" then
        state.fileTemplate = x
    elseif type(x) == "nil" and args.n == 1 then
        state.fileTemplate = function() end
    end
    return self
end

objectMT.folderFunction = function(self, ...)
    local state  = objectMT.internals[self]
--     local config = module._sharedDictionary._altthread[self.name]
    local args = table.pack(...)
    local x = args[1]
    if type(x) == "function" then
        state.folderTemplate = x
    elseif type(x) == "nil" and args.n == 1 then
        state.folderTemplate = function() end
    end
    return self
end

objectMT.rootDirectory = function(self, x)
--     local state  = objectMT.internals[self]
    local sd = module._sharedDictionary._altthread
    local config = sd[self.name]
    if type(x) == "string" then
        config.root = { x }
    elseif type(x) == "table" then
        config.root = x
    else
        return config.root
    end
    module._sharedDictionary._altthread = sd
    doManualUpdate(self)
    return self
end

objectMT.menuCriteria = function(self, ...)
--     local state  = objectMT.internals[self]
    local sd = module._sharedDictionary._altthread
    local config = sd[self.name]
    local args = table.pack(...)
    local x = args[1]
    if type(x) == "string" then
        config.matchCriteria = { x }
    elseif type(x) == "table" then
        config.matchCriteria = x
    elseif type(x) == "fn" then
        if validateFunction(x) then
            config.matchCriteria = string.dump(x)
        end
    elseif type(x) == "nil" and args.n == 1 then
        config.matchCriteria = { }
    else
        return config.matchCriteria
    end
    module._sharedDictionary._altthread = sd
    doManualUpdate(self)
    return self
end

objectMT.populate = function(self)
    doManualUpdate(self)
    return self
end

objectMT.__index = function(self, key)
    if objectMT[key] then
        return objectMT[key]
    elseif objectMT.internals[self][key] then
        return objectMT.internals[self][key]
    elseif module._sharedDictionary._altthread[self.name][key] then
        return module._sharedDictionary._altthread[self.name][key]
    else
        return nil
    end
end

objectMT.__gc = function(self)
    return self:deactivate()
end

objectMT.__tostring = function(self)
    return "This is the state data for menu "..self.name.."."
end

-- Return Module Object --------------------------------------------------

return module
