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
    runCadence     = 2.0,   -- steps per second at or above this = run...
    runBob         = 0.08,  -- ...or a big bounce (peak-to-peak metres) at a decent pace
    runBobCadence  = 1.6,
    jumpSpeed      = 1.2,   -- upward head speed (m/s) that counts as a real jump
    jumpRise       = 0.06,  -- and the head must be at least this far above average
    jumpCooldown   = 1.0,
    leanBack       = 0.12,  -- lean back this far (m) to backpedal
    leanSide       = 0.16,  -- lean sideways this far (m) to sidestep
    leanHold       = 0.35,  -- and hold it this long, so a stray wobble doesn't steer you
    leanAfterJump  = 1.0,   -- ignore lean for this long after a jump
    centreTime     = 3.0,   -- standing centre re-settles this fast while you're still...
    centreTimeMoving = 8.0, -- ...and slowly while moving, so drifting around the room doesn't steer
    debug          = true,  -- on-screen readout for tuning
}

local now = 0
local backHeld, sideHeld, sideDir = 0, 0, 0
local logTimer = 0
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
    -- Re-centre fast while still, slowly while moving, and not at all while you're
    -- deliberately leaning (otherwise a held lean would fade away).
    local off = p - centre
    local leaning = moving and off:length() > CFG.leanBack * 0.6
    if not leaning then
        local tau = moving and CFG.centreTimeMoving or CFG.centreTime
        centre = centre + off * math.min(dt / tau, 1)
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

local bobMax, bobMin, bobAmp = -1, 1, 0
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
    running = moving and (cadence >= CFG.runCadence or (bobAmp >= CFG.runBob and cadence >= CFG.runBobCadence))
end

local function updateHud(dt)
    if not CFG.debug then return end
    hudTimer = hudTimer + dt
    if hudTimer < 0.2 then return end
    hudTimer = 0
    local text = string.format('FIT  bounce %.1fcm  cad %.1f/s  lean %+.0f/%+.0fcm  %s',
        bobAmp * 100, cadence, leanFwd * 100, leanSide * 100,
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
    bobMax, bobMin = math.max(bobMax, dz), math.min(bobMin, dz)
    if phase <= 0 and dz > h then
        phase = 1
        recordStep(now)
        bobAmp = bobAmp * 0.5 + (bobMax - bobMin) * 0.5   -- smoothed peak-to-peak per step
        bobMax, bobMin = dz, dz
    elseif phase >= 0 and dz < -h then
        phase = -1
    end
    local wasMoving = moving
    updateCadence(now)
    if moving ~= wasMoving then self.object:sendEvent('FitMoving', { moving = moving }) end
    updateLean(pose, dt)

    -- physical jump: a sharp upward burst well beyond jogging bob
    local wantJump = vz > CFG.jumpSpeed and dz > CFG.jumpRise and (now - lastJump) > CFG.jumpCooldown
    if wantJump then lastJump = now end

    -- the stick always wins
    local stickUsed = math.abs(self.controls.movement) > 0.1 or math.abs(self.controls.sideMovement) > 0.1
    -- lean only counts once held for leanHold seconds, and never right after a jump
    local leanOk = (now - lastJump) > CFG.leanAfterJump and math.abs(vz) < 0.6
    local wantBack = leanOk and leanFwd < -CFG.leanBack
    local wantSide = leanOk and math.abs(leanSide) > CFG.leanSide and (leanSide > 0 and 1 or -1) or 0
    backHeld = wantBack and backHeld + dt or 0
    if wantSide ~= 0 and wantSide == sideDir then sideHeld = sideHeld + dt else sideHeld = 0 end
    sideDir = wantSide
    if not stickUsed and moving then
        -- rhythm sets speed, lean sets direction (default: forward)
        local fwd, side = 1, 0
        if backHeld >= CFG.leanHold then fwd = -1 end
        if sideHeld >= CFG.leanHold then
            side = sideDir
            if fwd == 1 then fwd = 0 end
        end
        self.controls.movement = fwd
        self.controls.sideMovement = side
        self.controls.run = running
    end
    if wantJump then self.controls.jump = true end

    updateHud(dt)
    logTimer = logTimer + dt
    if logTimer >= 2 and (moving or cadence > 0) then
        logTimer = 0
        print(string.format('[fitness] loco cad %.2f/s amp %.1fcm lean fwd %+.0f side %+.0fcm -> %s',
            cadence, bobAmp * 100, leanFwd * 100, leanSide * 100,
            running and 'RUN' or (moving and 'WALK' or 'idle')))
    end
end

local safe = require('scripts.fitness.safe')
return {
    engineHandlers = { onFrame = safe('locomotion', onFrame), onVRFrame = safe('locomotion vr', onVRFrame) },
}
