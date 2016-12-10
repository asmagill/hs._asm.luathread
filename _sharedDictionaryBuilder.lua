
return function(tagName)
    return function(self)
        local name = self.name and self:name() or "<unnamed>"
        local _sharedTable = {}
        local ptr = tostring(_sharedTable):match("^table: (.+)$")
        return setmetatable(_sharedTable, {
            __index    = function(t, k) return self:getFromDictionary(k) end,
            __newindex = function(t, k, v) self:setInDictionary(k, v) end,
            __pairs    = function(t)
                local keys = self:keysForDictionary()
                return function(t, i)
                    i = table.remove(keys, 1)
                    if i then
                        return i, self:getFromDictionary(i)
                    else
                        return nil
                    end
                end, t, nil
            end,
            __tostring = function(t) return string.format("%s:sharedDictionary %s (%s)", tagName, name, ptr) end,
        })
    end
end
