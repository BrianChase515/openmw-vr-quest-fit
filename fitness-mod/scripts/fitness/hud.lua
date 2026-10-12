-- Moves the VR HUD (health / magicka / fatigue) to a fixed spot in view, set in config.lua.
local vr = require('openmw.vr')
if not vr.isVr() then return {} end
local storage = require('openmw.storage')
local CFG = require('scripts.fitness.config')
local safe = require('scripts.fitness.safe')

local done = false
local function apply()
    if done then return end
    done = true
    if not CFG.hudPosition then return end
    local section = storage.playerSection('SpacesGroup')   -- the VR menu's "spaces" settings
    if section:get('HUDSpace') ~= CFG.hudPosition then
        section:set('HUDSpace', CFG.hudPosition)
        print('[fitness] HUD moved to ' .. CFG.hudPosition)
    end
end

return { engineHandlers = { onFrame = safe('hud', function() apply() end) } }
