-- Wraps a handler so a bug logs once (then at most every 10 s) instead of every frame.
-- Per-frame error spam floods the log and makes the game stutter.
local core = require('openmw.core')
return function(name, fn)
    local lastLog, count = -1e9, 0
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then
            count = count + 1
            local t = core.getRealTime()
            if t - lastLog > 10 then
                lastLog = t
                print(string.format('[fitness] %s error (x%d): %s', name, count, tostring(err)))
            end
        end
    end
end
