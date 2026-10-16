-- The game's own wrist HUD (health bars, minimap, equipped weapon/spell icons).
-- The fitness HUD already shows health / magicka / fatigue in a fixed spot, so the wrist panel is
-- hidden - except when you check it like a watch: raise your left forearm across in front of you,
-- inside of the wrist toward your face, and hold it a moment. The panel (with the minimap) appears
-- on your wrist and you can keep walking while you read it. Drop the arm and it goes away.
-- Only that panel: item tooltips and message pop-ups are separate and stay.
-- config.lua: hudPosition = 'watch' (default), 'hidden', or 'LeftWristTop', 'HUDBottomLeft', ... to always show it.
local vr = require('openmw.vr')
if not vr.isVr() then return {} end
local storage = require('openmw.storage')
local util = require('openmw.util')
local I = require('openmw.interfaces')
local CFG = require('scripts.fitness.config')
local core = require('openmw.core')
local safe = require('scripts.fitness.safe')

local SP = I.vrspaces.referenceSpaces
local AIM = I.vrspaces.actionSpaces.LeftHandAim
local U = I.vrspaces.unitsPerMeter

local t, ready, shown = 0, false, nil
local watchFor, notFor = 0, 0
local lastHand, lastT, handSpeed = nil, nil, 0

local function baseLayout()
    return {
        backgroundOpacity = 0,
        center = util.vector2(0, 0.5),
        extent = util.vector2(0.033, 0.033),
        pixelsPerMeter = 1024,
        pixelResolution = util.vector2(1024, 768),
        autosize = true,
    }
end

local function setVisible(visible)
    if shown == visible then return end
    shown = visible
    local layout = baseLayout()
    if visible then
        layout.space = CFG.watchSpace or 'LeftWristInner'
        layout.pixelsPerMeter = CFG.watchPixelsPerMeter or 1024
    else
        layout.space = 'FitnessHiddenHud'
        layout.pixelsPerMeter = 1000000
    end
    vr._setLayerConfig('HUD_3D', layout)
end

-- Is the left arm held up like you're checking a watch?
local watchPose = false
local function onVRFrame()
    if not ready or CFG.hudPosition ~= 'watch' then return end
    local head = I.vrspaces.locateSpace(SP.View, SP.Local)
    local hand = I.vrspaces.locateSpace(AIM, SP.Local)
    if not head or not hand then watchPose = false; return end
    local hp, p = head.position / U, hand.position / U
    local now = core.getRealTime()
    if lastHand and lastT and now > lastT then handSpeed = (p - lastHand):length() / (now - lastT) end
    lastHand, lastT = p, now
    local fwd = head.orientation * util.vector3(0, 1, 0)
    fwd = util.vector3(fwd.x, fwd.y, 0)
    if fwd:length() < 1e-3 then watchPose = false; return end
    fwd = fwd:normalize()
    local right = util.vector3(fwd.y, -fwd.x, 0)
    local d = p - hp
    local ahead, up = d:dot(fwd), d.z
    local aim = hand.orientation * util.vector3(0, 1, 0)   -- where the controller points
    -- forearm across the body: the left controller points toward your right, roughly level
    local across = aim:dot(right)
    watchPose = ahead > 0.10 and ahead < 0.70 and up > -0.65 and up < 0.10
        and across > 0.55 and handSpeed < 1.2
end

local function onFrame(dt)
    if not CFG.hudPosition then return end
    t = t + math.max(dt, 0)
    if t < 3 then return end   -- let the VR menu script set up its layers first
    if not ready then
        ready = true
        -- The VR menu script re-applies its own wrist layout every time a menu opens; tell it hands off.
        if I.vrui and I.vrui.overrideLayerConfig then I.vrui.overrideLayerConfig('HUD_3D', true) end
        if CFG.hudPosition == 'hidden' or CFG.hudPosition == 'watch' then
            -- a place to park the panel when it's not wanted: far below you, shrunk to nothing
            I.vrspaces.createDerivedSpace('FitnessHiddenHud', SP.View, { position = util.vector3(0, 0, -10000) })
            setVisible(false)
            print('[fitness] wrist HUD ' .. (CFG.hudPosition == 'watch' and 'shows when you check your left wrist' or 'hidden'))
            return
        end
        -- always show it somewhere specific; remember it in the VR settings too
        local section = storage.playerSection('SpacesGroup')
        if section:get('HUDSpace') ~= CFG.hudPosition then section:set('HUDSpace', CFG.hudPosition) end
        local layout = baseLayout()
        layout.space = CFG.hudPosition
        vr._setLayerConfig('HUD_3D', layout)
        print('[fitness] HUD placed at ' .. CFG.hudPosition)
        return
    end
    if CFG.hudPosition ~= 'watch' then return end
    -- small delays so a punch or a passing arm doesn't flash it
    local wallDt = math.max(dt, 1 / 72)
    if watchPose then watchFor, notFor = watchFor + wallDt, 0 else watchFor, notFor = 0, notFor + wallDt end
    if not shown and watchFor > 0.3 then setVisible(true) end
    if shown and notFor > 0.5 then setVisible(false) end
end

return { engineHandlers = { onFrame = safe('hud', onFrame), onVRFrame = safe('hud vr', onVRFrame) } }
