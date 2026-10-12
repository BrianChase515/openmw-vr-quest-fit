-- Boxing-style defence. Enemies telegraph their attacks (target.lua sends FitIncoming
-- as the wind-up starts, and slows the wind-up a little). The screen calls the dodge:
--   SQUAT        overhead/horizontal swings, creature lunges: drop your head
--   SLIP LEFT/RIGHT  thrusts and chops: move your head sideways that way
-- The right dodge gives a good chance to avoid the hit (otherwise it's halved); the wrong
-- move or a half-hearted one only softens it. Spamming dodges wears the chance down.
local vr = require('openmw.vr')
if not vr.isVr() then return {} end

local self = require('openmw.self')
local core = require('openmw.core')
local types = require('openmw.types')
local util = require('openmw.util')
local ambient = require('openmw.ambient')
local I = require('openmw.interfaces')
local CFG = require('scripts.fitness.config')
local safe = require('scripts.fitness.safe')

local U = I.vrspaces.unitsPerMeter
local SP = I.vrspaces.referenceSpaces
local GREEN, YELLOW, RED, WHITE = util.color.rgb(0.4, 1, 0.5), util.color.rgb(1, 0.9, 0.4), util.color.rgb(1, 0.4, 0.3), util.color.rgb(1, 1, 1)

local now = 0
local cachedHead = nil
local headPos, headRight = nil, util.vector3(1, 0, 0)
local standZ = nil             -- standing head height (m), learned while you're not dodging
local history = {}             -- {t, pos} last ~0.8 s
local recentDodges = {}
local warnings = {}            -- attacker id -> {lane, dir, t, pos, right}
local lastWarnText = -10

local function coach(slot, text, color, secs)
    self.object:sendEvent('FitCoach', { slot = slot, text = text, color = color, secs = secs })
end

local LABEL = { squat = 'v  SQUAT  v', left = '<<  SLIP LEFT', right = 'SLIP RIGHT  >>' }

local function laneFor(data)
    if data.lane == 'squat' then return 'squat' end
    return data.dir == 'left' and 'left' or 'right'
end

local function posAgo(secs)
    for i = #history, 1, -1 do
        if now - history[i].t >= secs then return history[i].pos end
    end
    return history[1] and history[1].pos or headPos
end

local function dodgeFactor()
    local f = 1
    for i = #recentDodges, 1, -1 do
        if now - recentDodges[i] > CFG.dodgeMemory then table.remove(recentDodges, i)
        else f = f * CFG.dodgeFalloff end
    end
    local agility = types.Actor.stats.attributes.agility(self).modified
    return f * (0.75 + agility / 200)
end

-- How well did you dodge? returns 'clean', 'partial' or nil
local function judge(called, from, right)
    if not headPos or not standZ then return nil end
    local drop = standZ - headPos.z
    local d = headPos - from
    local side = d:dot(right)                       -- + = moved right
    local travel = util.vector2(d.x, d.y):length() + math.max(0, -d.z)
    if called == 'squat' then
        if drop >= CFG.squatDrop then return 'clean' end
    elseif called == 'left' then
        if side <= -CFG.slipDist then return 'clean' end
    elseif called == 'right' then
        if side >= CFG.slipDist then return 'clean' end
    else -- no warning seen: any decent slip or squat counts
        if drop >= CFG.squatDrop or math.abs(side) >= CFG.slipDist then return 'clean' end
    end
    if travel >= CFG.partialMove or drop >= CFG.partialMove then return 'partial' end
    return nil
end

I.Combat.addOnHitHandler(function(attack)
    if not attack.successful or not attack.attacker then return end
    if attack.sourceType == I.Combat.ATTACK_SOURCE_TYPES.Magic then return end

    local w = warnings[attack.attacker.id]
    if w and now - w.t > 3 then w = nil end
    warnings[attack.attacker.id] = nil
    local called = w and w.called or nil
    local from = w and w.pos or posAgo(0.5)
    local right = w and w.right or headRight
    local grade = judge(called, from, right)
    if not grade then
        coach('centre', 'HIT', RED, 0.8)
        return
    end

    table.insert(recentDodges, now)
    local fat = types.Actor.stats.dynamic.fatigue(self)
    fat.current = fat.current - CFG.dodgeFatigueCost

    local avoid = grade == 'clean' and CFG.cleanAvoid or CFG.partialAvoid
    local reduce = grade == 'clean' and CFG.cleanReduce or CFG.partialReduce
    local chance = avoid * dodgeFactor()
    print(string.format('[fitness] dodge %s (called %s) chance %.0f%%', grade, tostring(called), chance * 100))
    if math.random() < chance then
        attack.successful = false
        pcall(ambient.playSound, 'miss')
        coach('centre', 'DODGED!', GREEN, 1.0)
        return
    end
    if attack.damage then
        for k, v in pairs(attack.damage) do attack.damage[k] = v * reduce end
    end
    coach('centre', grade == 'clean' and 'GRAZED  (half damage)' or 'PARTIAL  (-25%)', YELLOW, 1.0)
end)

local function onIncoming(data)
    if not data.attacker then return end
    local called = laneFor(data)
    warnings[data.attacker.id] = { called = called, t = now, pos = headPos, right = headRight }
    coach('centre', LABEL[called], WHITE, math.max(data.eta or 0.6, 0.4) + 0.2)
end

local function onVRFrame()
    cachedHead = I.vrspaces.locateSpace(SP.View, SP.Local)
end

local function onFrame(dt)
    if dt <= 0 then return end
    now = now + dt
    local pose = cachedHead
    if not pose then return end
    headPos = pose.position / U
    local f = pose.orientation * util.vector3(0, 1, 0)
    local fl = util.vector3(f.x, f.y, 0)
    if fl:length() > 1e-3 then
        fl = fl:normalize()
        headRight = util.vector3(fl.y, -fl.x, 0)
    end
    table.insert(history, { t = now, pos = headPos })
    while #history > 0 and now - history[1].t > 0.8 do table.remove(history, 1) end

    -- learn standing height slowly, only while nobody is swinging at you and you're upright
    local busy = next(warnings) ~= nil
    if not standZ then standZ = headPos.z end
    if not busy and headPos.z > standZ - 0.1 then
        standZ = standZ + (headPos.z - standZ) * math.min(dt / 2.0, 1)
    end
    for id, w in pairs(warnings) do
        if now - w.t > 3 then warnings[id] = nil end
    end
end

return {
    engineHandlers = { onFrame = safe('dodge', onFrame), onVRFrame = safe('dodge vr', onVRFrame) },
    eventHandlers = { FitIncoming = safe('dodge incoming', onIncoming) },
}
