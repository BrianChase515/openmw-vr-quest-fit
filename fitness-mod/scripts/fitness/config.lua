-- Shared tuning for the fitness mod. Distances in metres, times in seconds.
return {
    debugHud = true,          -- on-screen readouts for tuning

    -- Effort gate: the engine reports punch strength 0..1 from hand speed,
    -- strength = (speed - 1.0) / 4.0 with default VR settings, so 0.5 = 3.0 m/s.
    minPunchStrength = 0.5,

    -- Combos: alternate punch types to build a multiplier, repeat one type and it goes stale.
    comboWindow   = 1.5,      -- max gap between landed punches to keep a combo alive
    comboStep     = 0.2,      -- multiplier gained per new punch type in the chain
    comboMaxLevel = 4,        -- cap: 1 + 4 * 0.2 = x1.8
    staleAfter    = 3,        -- this many of the same punch in a row...
    staleMult     = 0.6,      -- ...does only this much damage

    -- Enemy weaknesses (off by default; combos are the main mechanic).
    weaknessesEnabled = false,
    weaknessMult = 1.25,
    resistMult   = 0.8,

    -- Damage model: false = vanilla (punches drain fatigue, knockdown lets health damage through)
    --               true  = brawler (punches also hurt health directly)
    brawler = false,
    brawlerHealthShare = 0.5,

    -- Dodging (slip the incoming hit with your head)
    cleanSlip = 0.15, partialSlip = 0.07,  -- head travel in the last 0.4 s
    cleanAvoid = 0.45, partialAvoid = 0.15,
    cleanReduce = 0.5, partialReduce = 0.75,
    dodgeFatigueCost = 5,
    dodgeFalloff = 0.6,       -- each recent dodge multiplies the next chance by this
    dodgeMemory = 4.0,
}
