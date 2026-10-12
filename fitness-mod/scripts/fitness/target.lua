-- Runs on every NPC and creature. Rejects lazy punches from the player and
-- applies the combo bonus the player's punch script sends back.
local self = require('openmw.self')
local types = require('openmw.types')
local I = require('openmw.interfaces')
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

I.Combat.addOnHitHandler(function(attack)
    if not isPlayerPunch(attack) or not attack.successful then return end
    if (attack.strength or 1) < CFG.minPunchStrength then
        -- not a real punch: no damage, plays the miss sound
        attack.successful = false
        attack.attacker:sendEvent('FitPunchWeak', { strength = attack.strength })
        return
    end
    local dmg = attack.damage or {}
    attack.attacker:sendEvent('FitPunchLanded', {
        victim = self.object,
        kind = describeSelf(),
        fatigue = dmg.fatigue or 0,
        health = dmg.health or 0,
        strength = attack.strength,
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
