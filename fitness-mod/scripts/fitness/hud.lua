-- Moves the VR HUD (health / magicka / fatigue) to a fixed spot in view, set in config.lua.
local vr = require('openmw.vr')
if not vr.isVr() then return {} end
local storage = require('openmw.storage')
local util = require('openmw.util')
local CFG = require('scripts.fitness.config')
local safe = require('scripts.fitness.safe')

local t, done = 0, false
local function onFrame(dt)
    if done or not CFG.hudPosition then return end
    t = t + math.max(dt, 0)
    if t < 3 then return end   -- let the VR menu script set up its layers first
    done = true
    -- Remember it in the VR settings (takes effect on later launches too)...
    local section = storage.playerSection('SpacesGroup')
    if section:get('HUDSpace') ~= CFG.hudPosition then section:set('HUDSpace', CFG.hudPosition) end
    -- ...and move it right now (same layout the VR menu uses for the HUD, different anchor).
    vr._setLayerConfig('HUD_3D', {
        backgroundOpacity = 0,
        center = util.vector2(0, 0.5),
        extent = util.vector2(0.033, 0.033),
        pixelsPerMeter = 1024,
        pixelResolution = util.vector2(1024, 768),
        autosize = true,
        space = CFG.hudPosition,
    })
    print('[fitness] HUD placed at ' .. CFG.hudPosition)
end

return { engineHandlers = { onFrame = safe('hud', onFrame) } }
