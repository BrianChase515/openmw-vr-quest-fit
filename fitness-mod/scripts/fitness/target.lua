-- Runs on every NPC and creature. Rejects lazy punches from the player and
-- applies the combo bonus the player's punch script sends back.
local self = require('openmw.self')
local types = require('openmw.types')
local I = require('openmw.interfaces')
local core = require('openmw.core')
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

return {
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
