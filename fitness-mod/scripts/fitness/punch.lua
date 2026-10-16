-- Punch tracking for the player: follows both hands, classifies each landed punch
-- as jab, hook or uppercut, runs the combo meter and sends the bonus to the target.
local vr = require('openmw.vr')
if not vr.isVr() then return {} end

local self = require('openmw.self')
local core = require('openmw.core')
local ui = require('openmw.ui')
local util = require('openmw.util')
local ambient = require('openmw.ambient')
local I = require('openmw.interfaces')
local types = require('openmw.types')
local CFG = require('scripts.fitness.config')
local Actor = types.Actor
local storage = require('openmw.storage')

I.Settings.registerGroup({
    key = 'SettingsFitnessBoxing', page = 'FitnessMod', l10n = 'FitnessMod', name = 'Boxing', permanentStorage = true,
    settings = {
        { key = 'stance', renderer = 'select', name = 'Stance', default = 'Orthodox (left foot forward)',
          description = 'Your lead hand throws jabs; the rear hand throws crosses (graded harder).',
          argument = { l10n = 'FitnessMod', items = { 'Orthodox (left foot forward)', 'Southpaw (right foot forward)' } } },
    },
})
local boxing = storage.playerSection('SettingsFitnessBoxing')
local function rearHand()
    return (boxing:get('stance') or ''):find('^Southpaw') and 'left' or 'right'
end
-- A straight punch from the rear hand is a cross.
local function punchName(kind, hand)
    if kind == 'jab' and hand == rearHand() then return 'cross' end
    return kind
end

local U = I.vrspaces.unitsPerMeter
local SP = I.vrspaces.referenceSpaces
local HANDS = {
    right = { space = I.vrspaces.actionSpaces.RightHandGrip,
              haptic = '/user/hand/right/output/haptic', inward = -1 },
    left  = { space = I.vrspaces.actionSpaces.LeftHandGrip,
              haptic = '/user/hand/left/output/haptic', inward = 1 },
}
local LAUNCH_SPEED, END_SPEED = 1.5, 0.8
local MAX_REAL_SPEED = 16   -- m/s; faster than any human punch = tracking glitch

local WEAK = {   -- used only when CFG.weaknessesEnabled
    heavy = { weak = 'uppercut', resist = 'jab' },
    light = { weak = 'hook', resist = 'uppercut' },
    medium = { weak = 'jab', resist = 'hook' },
    undead = { weak = 'jab', resist = 'hook' },
    daedra = { weak = 'uppercut', resist = 'jab' },
    creature = { weak = 'hook', resist = 'uppercut' },
    humanoid = { weak = 'hook', resist = 'jab' },
}

local now = 0
local raiseFists, onSwingEnd, showSwing, classify
local headFwd = util.vector3(0, 1, 0)
local combo = { level = 0, last = nil, sameCount = 0, lastTime = -10, chain = {} }
local hudUntil = 0
local hapticUntil = { right = 0, left = 0 }

-- Poses may only be read inside onVRFrame; cache them there for onFrame.
local poseCache = {}
local function onVRFrame()
    poseCache[SP.View] = I.vrspaces.locateSpace(SP.View, SP.Local)
    for _, h in pairs(HANDS) do poseCache[h.space] = I.vrspaces.locateSpace(h.space, SP.Local) end
end
local function locate(space) return poseCache[space] end

local function toMeters(v) return v / U end

local function flat(v)
    local f = util.vector3(v.x, v.y, 0)
    local l = f:length()
    return l > 1e-4 and f / l or nil
end

-- per-hand swing state
for _, h in pairs(HANDS) do
    h.prev, h.active, h.start, h.peak, h.peakTime, h.last = nil, false, nil, 0, -10, nil
end

local AUTO_FISTS_SPEED = 2.5   -- a swing this fast brings your fists up automatically
local FISTS_DOWN_AFTER = 20    -- seconds without a punching-speed swing before fists go down
local lastPunchSwing = -100
local raisedByUs = false
local moving = false     -- from locomotion.lua (stepping in place)

-- Running arms pump low by your hips; punches finish out in front at chest height or above.
local function isPunchShape(h)
    local head = poseCache[SP.View]
    local finish = h.active and h.last or h.endPos
    if not head or not finish then return false end
    local hp = toMeters(head.position)
    local d = finish - hp
    local reach = util.vector3(d.x, d.y, 0):dot(headFwd)
    local kind = classify(h)
    h.shapeReach, h.shapeDrop = reach, d.z
    if moving then
        -- while jogging, arm pumps can rise high: only a clearly extended jab/hook counts
        return kind ~= 'uppercut' and kind ~= 'punch' and reach >= CFG.punchMinReachMoving and d.z >= -0.3
    end
    if d.z < -CFG.punchMaxDrop then return false end
    -- each punch finishes in its own place: jabs far out, hooks beside the head, uppercuts close in
    if kind == 'hook' then return reach >= (CFG.hookMinReach or 0.15) end
    if kind == 'uppercut' then return reach >= (CFG.uppercutMinReach or 0.05) end
    return reach >= CFG.punchMinReach
end

local GREEN, YELLOW, RED = util.color.rgb(0.3, 1, 0.35), util.color.rgb(1, 0.9, 0.2), util.color.rgb(1, 0.3, 0.25)
local function grade(kind, speed)
    local g = (CFG.speedGrades or {})[kind] or { green = 7, yellow = 5 }
    if speed >= g.green then return GREEN, 'good' end
    if speed >= g.yellow then return YELLOW, 'ok' end
    return RED, 'weak'
end

local function emptyHanded()
    local w = Actor.getEquipment(self, Actor.EQUIPMENT_SLOT.CarriedRight)
    return w == nil or not types.Weapon.objectIsInstance(w)
end

raiseFists = function()
    if Actor.isSwimming(self) then return end   -- breaststroke, not a fight
    lastPunchSwing = now
    if Actor.getStance(self) == Actor.STANCE.Nothing and emptyHanded()
        and types.Player.getControlSwitch(self, types.Player.CONTROL_SWITCH.Fighting) then
        Actor.setStance(self, Actor.STANCE.Weapon)
        raisedByUs = true
    end
end

local function maybeLowerFists()
    if raisedByUs and Actor.isSwimming(self) and Actor.getStance(self) == Actor.STANCE.Weapon then
        Actor.setStance(self, Actor.STANCE.Nothing)
        raisedByUs = false
        return
    end
    local idle = now - lastPunchSwing
    if raisedByUs and (idle > FISTS_DOWN_AFTER or (moving and idle > 1.5)) then
        if Actor.getStance(self) == Actor.STANCE.Weapon and emptyHanded() then
            Actor.setStance(self, Actor.STANCE.Nothing)
        end
        raisedByUs = false
    end
end

onSwingEnd = function(name, h)
    if h.peak < AUTO_FISTS_SPEED then return end
    if not isPunchShape(h) then
        print(string.format('[fitness] swing %s %s %.1f m/s REJECTED (reach %.2f m, height %.2f m, moving %s)',
            name, classify(h, name), h.peak, h.shapeReach or -1, h.shapeDrop or -1, tostring(moving)))
        return
    end
    self.object:sendEvent('FitTally', { punches = 1 })
    raiseFists()
    local kind = punchName(classify(h, name), name)
    local color, verdict = grade(kind, h.peak)
    print(string.format('[fitness] swing %s %s %.1f m/s %s (reach %.2f m)', name, kind, h.peak, verdict, h.shapeReach or -1))
    if CFG.showSwings and not moving then
        showSwing(string.format('%s %s   %.1f m/s', name == 'left' and 'L' or 'R', kind:upper(), h.peak), color)
    end
end

local function updateHand(name, h, dt)
    local pose = locate(h.space)
    if not pose then h.prev = nil; return end
    local p = toMeters(pose.position)
    if h.prev then
        local speed = (p - h.prev):length() / dt
        if speed > MAX_REAL_SPEED then
            -- tracking glitch (controller lost / jumped): throw the swing away
            h.active, h.fast, h.prev = false, 0, p
            return
        end
        h.fast = speed > LAUNCH_SPEED and (h.fast or 0) + 1 or 0
        if not h.active and h.fast >= 2 then       -- needs 2+ frames of real speed
            h.active, h.start, h.peak, h.peakTime = true, h.prev, speed, now
        end
        if h.active then
            if speed > h.peak then h.peak, h.peakTime = speed, now end
            h.last = p
            if speed < END_SPEED or now - h.peakTime > 0.5 then
                h.active = false
                h.endPos, h.endTime = p, now
                onSwingEnd(name, h)
            end
        end
    end
    h.prev = p
end

classify = function(h, name)
    local finish = h.active and h.last or h.endPos
    if not h.start or not finish then return 'punch' end
    local d = finish - h.start
    local right = util.vector3(headFwd.y, -headFwd.x, 0)
    local fwd, side, up = d:dot(headFwd), d:dot(right), d.z
    local inward = side * h.inward          -- positive = hand crossing toward the body's centre
    if up > 0.12 and up >= 0.8 * math.abs(fwd) and up > math.abs(side) then return 'uppercut' end
    if inward > 0.12 and inward >= 0.9 * math.abs(fwd) and inward > up then return 'hook' end
    if fwd > 0.12 then return 'jab' end
    return 'punch'
end

local function pickHand()
    -- the hand whose swing peaked most recently (the one that just connected)
    local best, bestName
    for name, h in pairs(HANDS) do
        if (h.active or now - (h.endTime or -10) < 0.4) and (not best or h.peakTime > best.peakTime) then
            best, bestName = h, name
        end
    end
    return best, bestName
end

local ORANGE, GREY = util.color.rgb(1, 0.65, 0.25), util.color.rgb(0.85, 0.85, 0.85)
local function showHud(text, secs, color)
    hudUntil = now + (secs or 1.2)
    self.object:sendEvent('FitCoach', { slot = 'status', text = text, secs = secs or 1.2, color = color or ORANGE })
end

showSwing = function(text, color)
    self.object:sendEvent('FitCoach', { slot = 'speed', text = text, secs = 1.5, color = color or GREY })
end

local function buzz(name, strength, secs)
    hapticUntil[name] = now + secs
    HANDS[name].buzz = strength
end

local function onPunchLanded(data)
    self.object:sendEvent('FitTally', { hits = 1 })
    local h, name = pickHand()
    local kind = h and punchName(classify(h, name), name) or 'punch'
    -- Left and right count as different moves (a 1-2 is L JAB > R JAB).
    local move = ((name == 'left') and 'L ' or (name == 'right') and 'R ' or '') .. kind:upper()

    -- combo bookkeeping
    if now - combo.lastTime > CFG.comboWindow then
        combo.level, combo.last, combo.sameCount, combo.chain = 0, nil, 0, {}
    end
    local mult
    if kind ~= 'punch' and move == combo.last then
        combo.sameCount = combo.sameCount + 1
    else
        combo.sameCount = 1
        if combo.last and kind ~= 'punch' then
            combo.level = math.min(combo.level + 1, CFG.comboMaxLevel)
        end
    end
    if combo.sameCount >= CFG.staleAfter then
        combo.level = 0
        mult = CFG.staleMult
    else
        mult = 1 + CFG.comboStep * combo.level
    end
    combo.last, combo.lastTime = move, now
    table.insert(combo.chain, move)
    while #combo.chain > 4 do table.remove(combo.chain, 1) end

    -- optional enemy weakness
    local tag = ''
    if CFG.weaknessesEnabled then
        local w = WEAK[data.kind]
        if w and w.weak == kind then mult = mult * CFG.weaknessMult; tag = '  WEAK SPOT'
        elseif w and w.resist == kind then mult = mult * CFG.resistMult; tag = '  resisted' end
    end

    local extraFatigue = data.fatigue * (mult - 1)
    local extraHealth = data.health * (mult - 1)
    if CFG.brawler then
        extraHealth = extraHealth + data.fatigue * CFG.brawlerHealthShare * mult
    end
    if extraFatigue ~= 0 or extraHealth ~= 0 then
        data.victim:sendEvent('FitPunchBonus', { fatigue = extraFatigue, health = extraHealth })
    end

    -- feedback
    if name then buzz(name, mult > 1.05 and 1.0 or 0.5, mult > 1.05 and 0.12 or 0.06) end
    if combo.level >= 2 and mult > 1.05 then pcall(ambient.playSound, 'critical damage') end
    local label
    if mult < 1 then
        label = string.format('%s (stale) x%.1f  - mix it up', move, mult)
    elseif combo.level > 0 then
        label = string.format('COMBO %d   %s   x%.1f%s', combo.level + 1, table.concat(combo.chain, ' > '), mult, tag)
    else
        label = string.format('%s%s', move, tag)
    end
    showHud(label, 1.2)
end

local function onFrame(dt)
    if dt <= 0 or core.isWorldPaused() then return end
    now = now + dt
    local head = locate(SP.View)
    if head then
        local f = flat(head.orientation * util.vector3(0, 1, 0))
        if f then headFwd = f end
    end
    for name, h in pairs(HANDS) do
        updateHand(name, h, dt)
        if now < hapticUntil[name] then pcall(I.vrinputs.setOutputValue, h.haptic, h.buzz or 0.5) end
    end
    maybeLowerFists()
end

local safe = require('scripts.fitness.safe')
return {
    engineHandlers = { onFrame = safe('punch', onFrame), onVRFrame = safe('punch vr', onVRFrame) },
    eventHandlers = {
        FitPunchLanded = safe('punch landed', onPunchLanded),
        FitMoving = function(d) moving = d.moving end,
        FitPunchWeak = function(d)
            if moving then return end   -- arm pumps brushing past someone while jogging: stay quiet
            showHud(string.format('too soft (%.0f%%) - commit to it', (d.strength or 0) * 100), 0.8, GREY)
        end,
    },
}
