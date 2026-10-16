-- The game's own wrist HUD (health bars, minimap, equipped weapon/spell icons).
-- The fitness HUD already shows health / magicka / fatigue in a fixed spot, so by default the
-- wrist panel is hidden. Only that panel: item tooltips and message pop-ups are separate and stay.
-- config.lua: hudPosition = 'hidden' (default), or 'LeftWristTop', 'HUDBottomLeft', ... to show it.
local vr = require('openmw.vr')
if not vr.isVr() then return {} end
local storage = require('openmw.storage')
local util = require('openmw.util')
local I = require('openmw.interfaces')
local CFG = require('scripts.fitness.config')
local safe = require('scripts.fitness.safe')

local t, done = 0, false
local function onFrame(dt)
    if done or not CFG.hudPosition then return end
    t = t + math.max(dt, 0)
    if t < 3 then return end   -- let the VR menu script set up its layers first
    done = true
    local layout = {
        backgroundOpacity = 0,
        center = util.vector2(0, 0.5),
        extent = util.vector2(0.033, 0.033),
        pixelsPerMeter = 1024,
        pixelResolution = util.vector2(1024, 768),
        autosize = true,
    }
    if CFG.hudPosition == 'hidden' then
        -- park the panel far below you and shrink it to nothing: never seen, costs nothing
        I.vrspaces.createDerivedSpace('FitnessHiddenHud', I.vrspaces.referenceSpaces.View,
            { position = util.vector3(0, 0, -10000) })
        layout.space = 'FitnessHiddenHud'
        layout.pixelsPerMeter = 1000000
        vr._setLayerConfig('HUD_3D', layout)
        print('[fitness] wrist HUD hidden (fitness HUD shows your stats)')
        return
    end
    -- show it somewhere specific; remember it in the VR settings too
    local section = storage.playerSection('SpacesGroup')
    if section:get('HUDSpace') ~= CFG.hudPosition then section:set('HUDSpace', CFG.hudPosition) end
    layout.space = CFG.hudPosition
    vr._setLayerConfig('HUD_3D', layout)
    print('[fitness] HUD placed at ' .. CFG.hudPosition)
end

return { engineHandlers = { onFrame = safe('hud', onFrame) } }
