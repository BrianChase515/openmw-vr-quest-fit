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

local U = I.vrspaces.unitsPerMeter
local SP = I.vrspaces.referenceSpaces
local HANDS = {
    right = { space = I.vrspaces.actionSpaces.RightHandGrip,
              haptic = '/user/hand/right/output/haptic', inward = -1 },
    left  = { space = I.vrspaces.actionSpaces.LeftHandGrip,
              haptic = '/user/hand/left/output/haptic', inward = 1 },
}
local LAUNCH_SPEED, END_SPEED = 1.5, 0.8   -- m/s: swing tracking only, not the effort gate

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
local hud, hudText, hudUntil = nil, '', 0
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

local function emptyHanded()
    local w = Actor.getEquipment(self, Actor.EQUIPMENT_SLOT.CarriedRight)
    return w == nil or not types.Weapon.objectIsInstance(w)
end

raiseFists = function()
    lastPunchSwing = now
    if Actor.getStance(self) == Actor.STANCE.Nothing and emptyHanded()
        and types.Player.getControlSwitch(self, types.Player.CONTROL_SWITCH.Fighting) then
        Actor.setStance(self, Actor.STANCE.Weapon)
        raisedByUs = true
    end
end

local function maybeLowerFists()
    if raisedByUs and now - lastPunchSwing > FISTS_DOWN_AFTER then
        if Actor.getStance(self) == Actor.STANCE.Weapon and emptyHanded() then
            Actor.setStance(self, Actor.STANCE.Nothing)
        end
        raisedByUs = false
    end
end

onSwingEnd = function(name, h)
    if h.peak < AUTO_FISTS_SPEED then return end
    local kind = classify(h, name)
    print(string.format('[fitness] swing %s %s peak %.1f m/s', name, kind, h.peak))
    if CFG.showSwings and now > hudUntil then
        showSwing(string.format('%s %.1f m/s', kind, h.peak))
    end
end

local function updateHand(name, h, dt)
    local pose = locate(h.space)
    if not pose then h.prev = nil; return end
    local p = toMeters(pose.position)
    if h.prev then
        local speed = (p - h.prev):length() / dt
        if not h.active and speed > LAUNCH_SPEED then
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
            if h.peak >= AUTO_FISTS_SPEED then raiseFists() end
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

local function showHud(text, secs)
    if not CFG.debugHud and secs < 1 then return end
    hudText, hudUntil = text, now + (secs or 1.2)
    if not hud then
        hud = ui.create({ layer = 'HUD', type = ui.TYPE.Text, props = {
            text = text, textSize = 26, textColor = util.color.rgb(1, 0.6, 0.2),
            relativePosition = util.vector2(0.5, 0.62), anchor = util.vector2(0.5, 0.5) } })
    else
        hud.layout.props.text = text
        hud:update()
    end
end

local swingHud
showSwing = function(text)
    if not swingHud then
        swingHud = ui.create({ layer = 'HUD', type = ui.TYPE.Text, props = {
            text = text, textSize = 20, textColor = util.color.rgb(0.8, 0.8, 0.8),
            relativePosition = util.vector2(0.5, 0.56), anchor = util.vector2(0.5, 0.5) } })
    else
        swingHud.layout.props.text = text
        swingHud:update()
    end
end

local function buzz(name, strength, secs)
    hapticUntil[name] = now + secs
    HANDS[name].buzz = strength
end

local function onPunchLanded(data)
    local h, name = pickHand()
    local kind = h and classify(h, name) or 'punch'

    -- combo bookkeeping
    if now - combo.lastTime > CFG.comboWindow then
        combo.level, combo.last, combo.sameCount, combo.chain = 0, nil, 0, {}
    end
    local mult
    if kind ~= 'punch' and kind == combo.last then
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
    combo.last, combo.lastTime = kind, now
    table.insert(combo.chain, kind)
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
        label = string.format('%s (stale) x%.1f  - mix it up', kind:upper(), mult)
    elseif combo.level > 0 then
        label = string.format('COMBO %d  %s  x%.1f%s', combo.level + 1, table.concat(combo.chain, ' > '):upper(), mult, tag)
    else
        label = string.format('%s%s', kind:upper(), tag)
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
    if hud and now > hudUntil and hudText ~= '' then
        hudText = ''
        hud.layout.props.text = ''
        hud:update()
    end
end

local safe = require('scripts.fitness.safe')
return {
    engineHandlers = { onFrame = safe('punch', onFrame), onVRFrame = safe('punch vr', onVRFrame) },
    eventHandlers = {
        FitPunchLanded = safe('punch landed', onPunchLanded),
        FitPunchWeak = function(d)
            showHud(string.format('too soft (%.0f%%) - commit to it', (d.strength or 0) * 100), 0.8)
        end,
    },
}
