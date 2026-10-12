-- Fitness locomotion: walk / jog in place and physical jump for OpenMW-VR.
-- Head bob drives forward movement; bob cadence picks walk vs run.
-- The thumbstick always wins: if you push it, this script stays out of the way.

local vr = require('openmw.vr')
if not vr.isVr() then return {} end

local self = require('openmw.self')
local core = require('openmw.core')
local ui = require('openmw.ui')
local util = require('openmw.util')
local I = require('openmw.interfaces')

local U = I.vrspaces.unitsPerMeter -- game units per real metre (~70)

-- Tuning (metres, seconds). Adjust from playtest feedback.
local CFG = {
    bobThreshold   = 0.020, -- head must rise/fall this far from its average to count as a bob
    averageTime    = 0.8,   -- how quickly the "average standing height" follows you
    minSteps       = 2,     -- bobs in a row before you start moving (rejects single nods)
    stopAfter      = 0.6,   -- stop if no bob for this long
    runCadence     = 2.4,   -- steps per second at or above this = run
    jumpSpeed      = 1.2,   -- upward head speed (m/s) that counts as a real jump
    jumpRise       = 0.06,  -- and the head must be at least this far above average
    jumpCooldown   = 1.0,
    leanThreshold  = 0.08,  -- lean this far from your centre to steer back / sideways
    centreTime     = 3.0,   -- how quickly your standing centre re-settles while you're still
    debug          = true,  -- on-screen readout for tuning
}

local now = 0
local avgZ, lastZ = nil, nil
local phase = 0           -- -1 below average, +1 above
local stepTimes = {}      -- times of recent upward bobs
local lastJump = -10
local moving, running, cadence = false, false, 0
local hud, hudTimer = nil, 0
local lastDz, lastVz = 0, 0

local centre = nil          -- standing centre (metres, horizontal)
local leanFwd, leanSide = 0, 0
local util_v3 = util.vector3

-- Poses may only be read inside onVRFrame; cache them there for onFrame.
local cachedHead = nil
local function onVRFrame()
    cachedHead = I.vrspaces.locateSpace(I.vrspaces.referenceSpaces.View, I.vrspaces.referenceSpaces.Local)
end
local function headPose() return cachedHead end

local function updateLean(pose, dt)
    local p = util.vector2(pose.position.x, pose.position.y) / U
    if not centre then centre = p end
    if not moving then
        -- re-centre slowly while standing still, so drifting around the room doesn't count as leaning
        centre = centre + (p - centre) * math.min(dt / CFG.centreTime, 1)
    end
    local f3 = pose.orientation * util_v3(0, 1, 0)
    local f = util.vector2(f3.x, f3.y)
    if f:length() < 1e-3 then return end
    f = f:normalize()
    local r = util.vector2(f.y, -f.x)
    local d = p - centre
    leanFwd, leanSide = d:dot(f), d:dot(r)
end

local function recordStep(t)
    table.insert(stepTimes, t)
    while #stepTimes > 6 do table.remove(stepTimes, 1) end
end

local function updateCadence(t)
    -- drop steps that are too old to matter
    while #stepTimes > 0 and t - stepTimes[1] > 2.5 do table.remove(stepTimes, 1) end
    local n = #stepTimes
    if n >= 2 then
        cadence = (n - 1) / math.max(stepTimes[n] - stepTimes[1], 0.05)
    else
        cadence = 0
    end
    local recent = n > 0 and (t - stepTimes[n]) < CFG.stopAfter
    moving = recent and n >= CFG.minSteps
    running = moving and cadence >= CFG.runCadence
end

local function updateHud(dt)
    if not CFG.debug then return end
    hudTimer = hudTimer + dt
    if hudTimer < 0.2 then return end
    hudTimer = 0
    local text = string.format('FIT  bob %+.1fcm  vz %+.2fm/s  cad %.1f/s  lean %+.0f/%+.0fcm  %s',
        lastDz * 100, lastVz, cadence, leanFwd * 100, leanSide * 100,
        running and 'RUN' or (moving and 'WALK' or 'idle'))
    if not hud then
        hud = ui.create({
            layer = 'HUD',
            type = ui.TYPE.Text,
            props = {
                text = text, textSize = 22, textColor = util.color.rgb(1, 0.9, 0.3),
                relativePosition = util.vector2(0.5, 0.15), anchor = util.vector2(0.5, 0),
            },
        })
    else
        hud.layout.props.text = text
        hud:update()
    end
end

local function onFrame(dt)
    if dt <= 0 or core.isWorldPaused() or I.UI.getMode() then return end
    now = now + dt

    local pose = headPose()
    if not pose then return end
    local z = pose.position.z / U
    if not avgZ then avgZ, lastZ = z, z end

    -- slow-moving average of head height; the bob is the difference from it
    local a = math.min(dt / CFG.averageTime, 1)
    avgZ = avgZ + (z - avgZ) * a
    local dz = z - avgZ
    local vz = (z - lastZ) / dt
    lastZ, lastDz, lastVz = z, dz, vz

    -- step detection with hysteresis: one step per rise above the band
    local h = CFG.bobThreshold / 2
    if phase <= 0 and dz > h then
        phase = 1
        recordStep(now)
    elseif phase >= 0 and dz < -h then
        phase = -1
    end
    updateCadence(now)
    updateLean(pose, dt)

    -- physical jump: a sharp upward burst well beyond jogging bob
    local wantJump = vz > CFG.jumpSpeed and dz > CFG.jumpRise and (now - lastJump) > CFG.jumpCooldown
    if wantJump then lastJump = now end

    -- the stick always wins
    local stickUsed = math.abs(self.controls.movement) > 0.1 or math.abs(self.controls.sideMovement) > 0.1
    if not stickUsed and moving then
        -- rhythm sets speed, lean sets direction (default: forward)
        local fwd, side = 1, 0
        if leanFwd < -CFG.leanThreshold then fwd = -1 end
        if math.abs(leanSide) > CFG.leanThreshold then
            side = leanSide > 0 and 1 or -1
            if leanFwd > -CFG.leanThreshold then fwd = 0 end
        end
        self.controls.movement = fwd
        self.controls.sideMovement = side
        self.controls.run = running
    end
    if wantJump then self.controls.jump = true end

    updateHud(dt)
end

local safe = require('scripts.fitness.safe')
return {
    engineHandlers = { onFrame = safe('locomotion', onFrame), onVRFrame = safe('locomotion vr', onVRFrame) },
}
