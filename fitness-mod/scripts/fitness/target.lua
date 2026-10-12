-- Runs on every NPC and creature. Rejects lazy punches from the player and
-- applies the combo bonus the player's punch script sends back.
local self = require('openmw.self')
local types = require('openmw.types')
local I = require('openmw.interfaces')
local core = require('openmw.core')
local safe = require('scripts.fitness.safe')
local animation = require('openmw.animation')
local CFG = require('scripts.fitness.config')

local function isPlayerPunch(attack)
    return attack.attacker and types.Player.objectIsInstance(attack.attacker)
        and not attack.weapon and not attack.ammo
        and attack.sourceType == I.Combat.ATTACK_SOURCE_TYPES.Melee
end

local function describeSelf()
    if types.Creature.objectIsInstance(self) then
        local t = types.Creature.record(self).type
        local T = types.Creature.TYPE
        if t == T.Undead then return 'undead' end
        if t == T.Daedra then return 'daedra' end
        if t == T.Humanoid then return 'humanoid' end
        return 'creature'
    end
    -- NPC: classify by cuirass weight
    local item = types.Actor.getEquipment(self, types.Actor.EQUIPMENT_SLOT.Cuirass)
    if item and types.Armor.objectIsInstance(item) then
        local skill = I.Combat.getArmorSkill and I.Combat.getArmorSkill(item)
        if skill == 'heavyarmor' then return 'heavy' end
        if skill == 'mediumarmor' then return 'medium' end
        return 'light'
    end
    return 'light'
end

-- Vanilla hand-to-hand damage for a punch of the given strength (used when we
-- overturn a skill-roll miss: a committed punch that connects should land).
local function handToHandDamage(attacker, strength)
    local skill = types.NPC.stats.skills.handtohand(attacker).modified
    local minM, maxM = core.getGMST('fMinHandToHandMult'), core.getGMST('fMaxHandToHandMult')
    local dmg = skill * (minM + (maxM - minM) * strength)
    local fat = types.Actor.stats.dynamic.fatigue(self).current
    if fat <= 0 then

        return { health = dmg * core.getGMST('fHandtoHandHealthPer') }
    end
    return { fatigue = dmg }
end

I.Combat.addOnHitHandler(function(attack)
    if not isPlayerPunch(attack) then return end
    local strength = attack.strength or 0
    print(string.format('[fitness] punch contact: success=%s strength=%.2f', tostring(attack.successful), strength))
    if strength < CFG.minPunchStrength then
        -- not a real punch: no damage, plays the miss sound
        attack.successful = false
        attack.attacker:sendEvent('FitPunchWeak', { strength = strength })
        return
    end
    if not attack.successful and CFG.committedPunchesAlwaysHit then
        -- Morrowind's skill roll said "miss"; in a fitness game effort beats dice.
        attack.successful = true
        attack.damage = handToHandDamage(attack.attacker, strength)
    end
    if not attack.successful then return end
    local dmg = attack.damage or {}
    attack.attacker:sendEvent('FitPunchLanded', {
        victim = self.object,
        kind = describeSelf(),
        fatigue = dmg.fatigue or 0,
        health = dmg.health or 0,
        strength = strength,
    })
end)

-- ---------------------------------------------------------------------------
-- Telegraphing attacks on the player: spot our own wind-up, warn the player,
-- and slow the wind-up a little so there's time to react.
local NPC_ATTACKS = { 'chop', 'slash', 'thrust' }
local warned = nil        -- { group, hitKey } for the swing we already called
local slowed = nil        -- group whose speed we changed

local function fightingPlayer()
    local target = I.AI and I.AI.getActiveTarget and I.AI.getActiveTarget('Combat')
    return target and types.Player.objectIsInstance(target) and target or nil
end

-- returns group, attackName, secondsUntilHit if a melee wind-up is in progress
local function currentWindup()
    local group = animation.getActiveGroup(self, animation.BONE_GROUP.RightArm)
    if not group or group == '' then
        group = animation.getActiveGroup(self, animation.BONE_GROUP.Torso)
    end
    if not group or group == '' then return nil end
    local t = animation.getCurrentTime(self, group)
    if not t then return nil end
    local speed = animation.getSpeed(self, group) or 1
    if group:find('^attack') then -- creatures: attack1/2/3
        local s = animation.getTextKeyTime(self, group .. ': start')
        local h = animation.getTextKeyTime(self, group .. ': hit')
        if s and h and t >= s - 0.01 and t < h then return group, group, (h - t) / math.max(speed, 0.1) end
        return nil
    end
    for _, a in ipairs(NPC_ATTACKS) do
        local s = animation.getTextKeyTime(self, group .. ': ' .. a .. ' start')
        local h = animation.getTextKeyTime(self, group .. ': ' .. a .. ' min hit')
            or animation.getTextKeyTime(self, group .. ': ' .. a .. ' hit')
        if s and h and t >= s - 0.01 and t < h then return group, a, (h - t) / math.max(speed, 0.1) end
    end
    return nil
end

local LANE = { slash = 'squat', attack1 = 'squat', chop = 'slip', thrust = 'slip', attack2 = 'slip', attack3 = 'slip' }

local combatCheck, cachedPlayer = 0, nil
local statusTimer = 0
local loggedSpeed = false
local function onUpdate(dt)
    -- cheap: only ask the AI who we're fighting twice a second
    combatCheck = combatCheck - dt
    if combatCheck <= 0 then
        combatCheck = 0.5
        cachedPlayer = fightingPlayer()
    end
    local player = cachedPlayer
    if player and CFG.showEnemy then
        statusTimer = statusTimer - dt
        if statusTimer <= 0 then
            statusTimer = 0.25
            local d = types.Actor.stats.dynamic
            local h, f = d.health(self), d.fatigue(self)
            local rec = (types.NPC.objectIsInstance(self) and types.NPC.record(self)) or types.Creature.record(self)
            player:sendEvent('FitEnemyStatus', { id = self.object.id, name = rec and rec.name or '?',
                pos = self.position,
                health = h.current, healthMax = h.base + h.modifier,
                fatigue = f.current, fatigueMax = f.base + f.modifier })
        end
    end
    if not player then
        if slowed then animation.setSpeed(self, slowed, 1); slowed = nil end
        warned = nil
        return
    end
    if (player.position - self.position):length() > 600 then return end
    local group, atk, eta = currentWindup()
    if not group then
        if slowed then animation.setSpeed(self, slowed, 1); slowed = nil end
        warned = nil
        return
    end
    local key = group .. atk
    if warned == key and slowed == group and CFG.windupSlow < 1 then
        -- the engine may reset animation speed: keep it slowed for the whole wind-up
        local sp = animation.getSpeed(self, group)
        if not loggedSpeed then
            loggedSpeed = true
            print(string.format('[fitness] %s wind-up %s: speed %.2f (wanted %.2f)', self.recordId or '?', atk, sp or -1, CFG.windupSlow))
        end
        if sp and math.abs(sp - CFG.windupSlow) > 0.01 then animation.setSpeed(self, group, CFG.windupSlow) end
    end
    if warned ~= key then
        loggedSpeed = false
        warned = key
        if CFG.windupSlow and CFG.windupSlow < 1 then
            animation.setSpeed(self, group, CFG.windupSlow)
            slowed = group
            eta = eta / CFG.windupSlow
        end
        local lane = LANE[atk] or 'slip'
        local dir = (atk == 'attack2') and 'left' or (atk == 'attack3') and 'right'
            or (math.random() < 0.5 and 'left' or 'right')
        player:sendEvent('FitIncoming', { attacker = self.object, lane = lane, dir = dir, eta = eta })
    end
end

return {
    engineHandlers = { onUpdate = safe('target', onUpdate) },
    eventHandlers = {
        -- extra (or negative, for stale punches) damage decided by the player's combo
        FitPunchBonus = function(data)
            local dyn = types.Actor.stats.dynamic
            if data.fatigue and data.fatigue ~= 0 then
                local f = dyn.fatigue(self)
                f.current = f.current - data.fatigue
            end
            if data.health and data.health ~= 0 then
                local h = dyn.health(self)
                h.current = math.max(h.current - data.health, 0)
            end
        end,
    },
}
