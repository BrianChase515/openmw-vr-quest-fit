-- Fitness locomotion for OpenMW-VR:
--   walk / jog in place  -> forward only (W). Pace picks walk vs run. Stick does everything else.
--   jump                 -> jump
--   in water             -> breaststroke (both hands push forward together) swims forward
--   lie down on the floor-> opens the Rest window
-- The thumbstick always wins: if you push it, this script stays out of the way.

local vr = require('openmw.vr')
if not vr.isVr() then return {} end

local self = require('openmw.self')
local core = require('openmw.core')
local ui = require('openmw.ui')
local util = require('openmw.util')
local I = require('openmw.interfaces')
local types = require('openmw.types')
local input = require('openmw.input')
local async = require('openmw.async')

-- You jump for real, so the controller's jump button (left trigger) opens the map instead.
local JUMP_OPENS_MAP = require('scripts.fitness.config').jumpButtonOpensMap ~= false
if JUMP_OPENS_MAP then
    input.registerTriggerHandler('Jump', async:callback(function()
        if core.isWorldPaused() or I.UI.getMode() then return end
        I.UI.addMode(I.UI.MODE.Interface, { windows = { I.UI.WINDOW.Map } })
    end))
end

local U = I.vrspaces.unitsPerMeter -- game units per real metre (~70)

-- Tuning (metres, seconds). Adjust from playtest feedback.
local CFG = {
    bobThreshold   = 0.008, -- head bounce (peak-to-peak, m) that can count as a step in a steady rhythm
    clearStep      = 0.025, -- a bounce this big counts on its own: you start moving on the first step
    averageTime    = 1.2,   -- how quickly the "average standing height" follows you
    stepGapMin     = 0.25,  -- steps closer than this are jitter, not steps (s)
    stepGapMax     = 1.3,   -- two small bounces further apart than this aren't a rhythm (s)
    stopAfter      = 1.1,   -- stop if no step for this long
    walkCadence    = 1.2,   -- steps per second where a walk starts picking up speed
    runCadence     = 2.05,  -- steps per second at or above this = run...
    runBob         = 0.08,  -- ...or a big bounce (peak-to-peak metres) at a decent pace
    runBobCadence  = 1.6,
    jumpSpeed      = 1.2,   -- upward head speed (m/s) that counts as a real jump
    jumpRise       = 0.06,  -- and the head must be at least this far above average
    jumpCooldown   = 1.0,
    strokeReach    = 0.42,  -- swimming: both hands pushed out at least this far in front of your face...
    strokeStart    = 0.25,  -- ...starting from closer than this (hands at your chest)
    strokeTime     = 0.9,   -- ...within this many seconds, hands together (< strokeHands apart)
    strokeHands    = 0.40,
    strokeGlide    = 1.3,   -- each stroke swims you forward this long
    lieDrop        = 1.0,   -- head this far (m) below standing height = lying down (squats are ~0.5-0.8)
    lieHold        = 2.0,   -- for this long -> Rest window
    debug          = true,  -- on-screen readout for tuning
    driftWarn      = require('scripts.fitness.config').driftWarn,   -- false = off
}

local now = 0
local standZ = nil
local speedNow = 0.75
local boutHome, stillTime, driftWarnAt = nil, 0, -10
local logTimer = 0
local avgZ, lastZ = nil, nil
local phase = 0           -- -1 below average, +1 above
local stepTimes = {}      -- times of recent upward bobs
local lastJump = -10
local moving, running, cadence = false, false, 0
local hud, hudTimer = nil, 0
local lastDz, lastVz = 0, 0

local hands = {}            -- cached hand poses (swimming)
local strokeArmed, strokeArmedAt, glideUntil, lastStroke = false, -10, -10, -10
local lyingSince, restOpened = nil, false

-- Poses may only be read inside onVRFrame; cache them there for onFrame.
local cachedHead = nil
local function onVRFrame()
    local L = I.vrspaces.referenceSpaces.Local
    cachedHead = I.vrspaces.locateSpace(I.vrspaces.referenceSpaces.View, L)
    hands.left = I.vrspaces.locateSpace(I.vrspaces.actionSpaces.LeftHandGrip, L)
    hands.right = I.vrspaces.locateSpace(I.vrspaces.actionSpaces.RightHandGrip, L)
end
local function headPose() return cachedHead end

local function recordStep(t)
    table.insert(stepTimes, t)
    while #stepTimes > 6 do table.remove(stepTimes, 1) end
end
local strongStep = false   -- the latest step was a clear one
local stepNow, inSquat, activityTimer = false, false, 0
local function tally(t) self.object:sendEvent('FitTally', t) end
local troughDz = 0

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
    -- one clear step starts you; small bounces need a second one in rhythm
    local rhythm = n >= 2 and (stepTimes[n] - stepTimes[n - 1]) <= CFG.stepGapMax
    moving = recent and (strongStep or rhythm or (moving and n >= 1))
    running = moving and (cadence >= CFG.runCadence or (bobAmp >= CFG.runBob and cadence >= CFG.runBobCadence))
end

local function updateHud(dt)
    if not require('scripts.fitness.config').debugHud then return end
    hudTimer = hudTimer + dt
    if hudTimer < 0.25 then return end
    hudTimer = 0
    self.object:sendEvent('FitCoach', { slot = 'status', secs = 0.5, text = string.format(
        'bounce %.1fcm  cad %.1f/s  %s', bobAmp * 100, cadence,
        running and 'RUN' or (moving and 'WALK' or 'idle')) })
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
        local p2p = bobMax - bobMin
        local last = stepTimes[#stepTimes]
        if not last or now - last >= CFG.stepGapMin then
            recordStep(now)
            stepNow = true
            strongStep = p2p >= CFG.clearStep
            bobAmp = bobAmp * 0.5 + p2p * 0.5   -- smoothed peak-to-peak per step
        end
        bobMax, bobMin = dz, dz
    elseif phase >= 0 and dz < -h then
        phase = -1
        troughDz = dz
    end
    if phase < 0 then troughDz = math.min(troughDz, dz) end
    -- a clear rise (from the last low point, or from standing still) counts straight away,
    -- so the first real step starts you instead of waiting for the second
    if phase > 0 and not strongStep and (dz - math.min(troughDz, 0)) >= CFG.clearStep * 0.6 then
        strongStep = true
    end
    local wasMoving = moving
    updateCadence(now)
    if stepNow then
        stepNow = false
        if moving then tally({ steps = (not wasMoving and #stepTimes >= 2) and 2 or 1 }) end
    end
    if moving ~= wasMoving then self.object:sendEvent('FitMoving', { moving = moving }) end

    -- Jogging in place tends to creep forward. Warn before you reach the Guardian boundary.
    local here = util.vector2(pose.position.x, pose.position.y) / U
    if moving then
        stillTime = 0
        if not boutHome then boutHome = here end
        local drift = (here - boutHome):length()
        if CFG.driftWarn and drift > CFG.driftWarn and now - driftWarnAt > 2 then
            driftWarnAt = now
            self.object:sendEvent('FitCoach', { slot = 'centre', secs = 1.8, color = util.color.rgb(1, 0.4, 0.3),
                text = string.format('DRIFTING %.1fm - STEP BACK', drift) })
        end
    else
        stillTime = stillTime + dt
        if stillTime > 3 then boutHome = nil end
    end

    -- physical jump: a sharp upward burst well beyond jogging bob
    -- standing height: learned only while upright, so it stays put while you squat
    if not standZ then standZ = z end
    if z > standZ - 0.08 and math.abs(vz) < 0.3 then
        standZ = standZ + (z - standZ) * math.min(dt / 2.0, 1)
    end
    -- a jump has to take your head clearly ABOVE standing height; rising out of a squat doesn't count
    local wantJump = vz > CFG.jumpSpeed and z > standZ + CFG.jumpRise and (now - lastJump) > CFG.jumpCooldown
    if wantJump then lastJump = now; tally({ jumps = 1 }) end

    -- squat counter: down at least 30 cm, back up to standing (not lying down)
    if standZ then
        local drop = standZ - z
        if drop > 0.30 and drop < CFG.lieDrop then inSquat = true end
        if lyingSince then inSquat = false end
        if inSquat and drop < 0.10 then inSquat = false; tally({ squats = 1 }) end
    end

    local swimming = types.Actor.isSwimming(self)
    -- the stick always wins
    local stickUsed = math.abs(self.controls.movement) > 0.1 or math.abs(self.controls.sideMovement) > 0.1

    if swimming then
        -- Breaststroke: both hands start at your chest, push out in front together = one stroke.
        local l, r2 = hands.left, hands.right
        if l and r2 then
            local f3 = pose.orientation * util.vector3(0, 1, 0)
            local f = util.vector2(f3.x, f3.y)
            if f:length() > 1e-3 then
                f = f:normalize()
                local hp = util.vector2(pose.position.x, pose.position.y) / U
                local lr = (util.vector2(l.position.x, l.position.y) / U - hp):dot(f)
                local rr = (util.vector2(r2.position.x, r2.position.y) / U - hp):dot(f)
                local apart = (l.position - r2.position):length() / U
                if lr < CFG.strokeStart and rr < CFG.strokeStart then
                    strokeArmed, strokeArmedAt = true, now
                elseif strokeArmed and lr > CFG.strokeReach and rr > CFG.strokeReach and apart < CFG.strokeHands then
                    strokeArmed = false
                    if now - strokeArmedAt <= CFG.strokeTime then
                        glideUntil = now + CFG.strokeGlide
                        lastStroke = now
                    end
                end
            end
        end
        if not stickUsed and now < glideUntil then
            self.controls.movement = 1
            self.controls.run = false
        end
    elseif not stickUsed and moving then
        -- Forward only. Pace sets speed smoothly: an easy march = steady walk, picking it up =
        -- brisk walk, a real jog = run. (Movement values below 1 make the character go slower.)
        local walkFrom, runAt = CFG.walkCadence, CFG.runCadence
        local pace = math.max(0, math.min(1, (cadence - walkFrom) / (runAt - walkFrom)))
        local target = running and 1 or (0.75 + 0.25 * pace)
        speedNow = speedNow + (target - speedNow) * math.min(dt / 0.15, 1)
        self.controls.movement = speedNow
        self.controls.run = running
    else
        speedNow = 0.8
    end

    -- Lie down on the floor -> Rest. (Squats don't go this low.)
    if not swimming and standZ and standZ - z > CFG.lieDrop then
        lyingSince = lyingSince or now
        if not restOpened and now - lyingSince > CFG.lieHold then
            restOpened = true
            print('[fitness] lying down -> rest')
            I.UI.addMode('Rest')
        end
    elseif standZ and standZ - z < CFG.lieDrop * 0.5 then
        lyingSince, restOpened = nil, false
    end
    if wantJump and not lyingSince then
        self.controls.jump = true
    elseif JUMP_OPENS_MAP and not swimming then
        self.controls.jump = false   -- the button opens the map; only a real jump jumps (it still swims you up)
    end

    -- what you're doing, for the calorie estimate
    activityTimer = activityTimer - dt
    if activityTimer <= 0 then
        activityTimer = 0.5
        local state = (swimming and now < glideUntil + 1) and 'swim' or lyingSince and 'rest'
            or running and 'run' or moving and 'walk' or 'idle'
        local pace = math.max(0, math.min(1, (cadence - CFG.walkCadence) / (CFG.runCadence - CFG.walkCadence)))
        self.object:sendEvent('FitActivity', { state = state, pace = pace })
    end

    updateHud(dt)
    logTimer = logTimer + dt
    if logTimer >= 2 and (moving or cadence > 0) then
        logTimer = 0
        print(string.format('[fitness] loco cad %.2f/s amp %.1fcm -> %s',
            cadence, bobAmp * 100,
            running and 'RUN' or (moving and 'WALK' or 'idle')))
    end
end

local safe = require('scripts.fitness.safe')
return {
    engineHandlers = { onFrame = safe('locomotion', onFrame), onVRFrame = safe('locomotion vr', onVRFrame) },
}
