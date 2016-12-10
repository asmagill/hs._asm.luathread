local instanceName, assignments = ...

local customInitName = instanceName:match("^([^::]+)")

if _instance then
    debug.sethook(function(t,l)
        if (_instance:isCancelled()) then
            error("** thread cancelled")
        end
    end, "", 1000)

    package.path  = assignments.path
    package.cpath = assignments.cpath

    local settings = require("hs.settings")
    local autoload_extensions = settings.get("HSAutoLoadExtensionsInThread")
    if type(autoload_extensions) == "nil" then
        autoload_extensions = settings.get("HSAutoLoadExtensions")
    end
    if type(autoload_extensions) == "nil" then autoload_extensions = true end

    hs = require("hs._asm.luathread.luaskin._coresupport")
    hs._threadPrintResults = true
    hs.processInfo = assignments.processInfo
    hs.reload      = function(...) _instance:reload(...) end
    hs._exit       = function(...) _instance:cancel(...) end

    hs._logmessage = function(s) _instance:print(tostring(s):match("^(.-)\n?$")) end

    local custominit = assignments.configdir.."/_init."..customInitName..".lua"
    if not os.execute("[ -f "..custominit.." ]") then
        custominit = assignments.configdir.."/_init.lua"
        if not os.execute("[ -f "..custominit.." ]") then
            custominit = nil
        end
    end

    _sharedDictionary = require("hs._asm.luathread._sharedDictionaryBuilder")("hs._asm.luathread.luaskin")(_instance)

    hs._logmessage("-- ".._VERSION..", Hammerspoon instance "..instanceName)
    local retval = { require("hs._coresetup").setup(hs.processInfo.resourcePath .. "/extensions",
                                                    tostring(custominit),
                                                    custominit, -- if nil, loadfile returns an empty fn
                                                    assignments.configdir,
                                                    assignments.docstrings_json_file,
                                                    true, -- we don't want a dialog displayed, even if they don't
                                                    autoload_extensions) }


    -- make sure logs get flushed to calling thread immediately
    local handleLogMessage = hs.handleLogMessage
    hs.handleLogMessage = function(...)
        handleLogMessage(...)
        _instance:flush()
    end

    -- requires threadsafe webview, which is not likely soon, if ever
    hs.hsdocs = setmetatable({}, {
        __call     = function(...) return "hs.hsdocs not available outside main thread" end,
        __tostring = function(...) return "hs.hsdocs not available outside main thread" end,
        __index    = function(self, key) return self end
    })

    -- console auto-complete for a thread?
    hs.completionsForInputString = setmetatable({}, {
        __call     = function(...) return "hs.completionsForInputString not available outside main thread" end,
        __tostring = function(...) return "hs.completionsForInputString not available outside main thread" end,
        __index    = function(self, key) return self end
    })

    function hs.showError(err)
        hs._notify("Hammerspoon error in thread " .. customInitName)
        print("*** ERROR: "..err)
        hs.focus()
        hs.openConsole()
        hs._TERMINATED=true
    end

    -- default runstring doesn't return results or flush, so we ignore it and create our own
    local runstring = function(s)
        if hs._consoleInputPreparser then
          if type(hs._consoleInputPreparser) == "function" then
            local status, s2 = pcall(hs._consoleInputPreparser, s)
            if status then
              s = s2
            else
              hs.luaSkinLog.ef("console preparse error: %s", s2)
            end
          else
              hs.luaSkinLog.e("console preparser must be a function or nil")
          end
        end

        --print("runstring")
        local fn, err = load("return " .. s)
        if not fn then fn, err = load(s) end
        if not fn then
            print(err)
            return tostring(err)
        end

        local str = ""
        local startTime = _instance:timestamp()
        local results   = table.pack(xpcall(fn,debug.traceback))
        local endTime   = _instance:timestamp()

        local sharedResults = { n = results.n - 1 }
        for i = 2,results.n do
            if i > 2 then str = str .. "\t" end
            str = str .. tostring(results[i])
            sharedResults[i - 1] = results[i]
        end

        -- this could error out if we can't get a lock on the sharedDictionary
        local _, err = pcall(function()
            _sharedDictionary._results = { start = startTime, stop = endTime, results = sharedResults }
        end)
        if not _ then logger.e(err) end
        if hs._threadPrintResults or not results[1] then print(str) end
        return table.unpack(sharedResults)
    end

    _instance:flush()
    return runstring
else
    error("_instance not defined, or not in child thread")
end
