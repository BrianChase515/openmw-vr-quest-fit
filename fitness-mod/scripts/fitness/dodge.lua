-- Slip incoming melee hits with your head, boxing style. A good slip gives a
-- chance to avoid the hit entirely and otherwise softens it; spamming dodges
-- wears the chance down and costs fatigue, so you still get hit plenty.
local vr = require('openmw.vr')
if not vr.isVr() then return {} end

local self = require('openmw.self')
local core = require('openmw.core')
local types = require('openmw.types')
local ui = require('openmw.ui')
local util = require('openmw.util')
local ambient = require('openmw.ambient')
local I = require('openmw.interfaces')
local CFG = require('scripts.fitness.config')

local U = I.vrspaces.unitsPerMeter
local SP = I.vrspaces.referenceSpaces
local WINDOW = 0.4

local now = 0
local history = {}      -- {t, pos} head positions in metres, last ~0.5 s
local recentDodges = {} -- times of recent dodge attempts
local hud, hudUntil = nil, 0

local function show(text, color)
    hudUntil = now + 1.0
    if not hud then
        hud = ui.create({ layer = 'HUD', type = ui.TYPE.Text, props = {
            text = text, textSize = 26, textColor = color,
            relativePosition = util.vector2(0.5, 0.7), anchor = util.vector2(0.5, 0.5) } })
    else
        hud.layout.props.text = text
        hud.layout.props.textColor = color
        hud:update()
    end
end

local function headTravel()
    -- sideways / backwards distance plus how far you dropped, over the last WINDOW seconds
    if #history < 2 then return 0 end
    local cur = history[#history].pos
    local best = 0
    for i = #history, 1, -1 do
        local e = history[i]
        if now - e.t > WINDOW then break end
        local d = cur - e.pos
        local travel = util.vector2(d.x, d.y):length() + math.max(0, -d.z)
        if travel > best then best = travel end
    end
    return best
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

I.Combat.addOnHitHandler(function(attack)
    if not attack.successful or not attack.attacker then return end
    if attack.sourceType == I.Combat.ATTACK_SOURCE_TYPES.Magic then return end

    local travel = headTravel()
    local avoid, reduce, label
    if travel >= CFG.cleanSlip then
        avoid, reduce, label = CFG.cleanAvoid, CFG.cleanReduce, 'SLIP'
    elseif travel >= CFG.partialSlip then
        avoid, reduce, label = CFG.partialAvoid, CFG.partialReduce, 'partial slip'
    else
        return -- no dodge attempted: normal hit
    end

    local chance = avoid * dodgeFactor()
    table.insert(recentDodges, now)
    local fat = types.Actor.stats.dynamic.fatigue(self)
    fat.current = fat.current - CFG.dodgeFatigueCost

    if math.random() < chance then
        attack.successful = false
        pcall(ambient.playSound, 'miss')
        show(string.format('%s - DODGED  (%.0f%% chance)', label:upper(), chance * 100), util.color.rgb(0.4, 1, 0.5))
        return
    end
    if attack.damage then
        for k, v in pairs(attack.damage) do attack.damage[k] = v * reduce end
    end
    show(string.format('%s - grazed, %.0f%% damage', label, reduce * 100), util.color.rgb(1, 0.9, 0.4))
end)

local function onFrame(dt)
    if dt <= 0 then return end
    now = now + dt
    local pose = I.vrspaces.locateSpace(SP.View, SP.Local)
    if pose then
        table.insert(history, { t = now, pos = pose.position / U })
        while #history > 0 and now - history[1].t > WINDOW + 0.1 do table.remove(history, 1) end
    end
    if hud and now > hudUntil then
        hud.layout.props.text = ''
        hud:update()
        hudUntil = math.huge
    end
end

return { engineHandlers = { onFrame = onFrame } }
