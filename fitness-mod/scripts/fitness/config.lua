-- Shared tuning for the fitness mod. Distances in metres, times in seconds.
return {
    debugHud = false,         -- extra movement readout on the status line (for tuning)

    -- Fitness HUD layout (fractions of the view panel, 0 = top, 1 = bottom)
    coachCentreY = 0.22,
    coachStatusY = 0.62,
    coachStatsY  = 0.74,
    showStats    = true,   -- health / magicka / fatigue numbers on the bottom line
    -- Warn when jogging in place has carried you this far (m) from where the jog started.
    driftWarn    = 0.5,

    -- Effort gate: the engine reports punch strength 0..1 from hand speed,
    -- strength = (speed - 1.0) / 4.0 with default VR settings, so 0.5 = 3.0 m/s.
    minPunchStrength = 0.5,
    -- Morrowind rolls your skill to decide if a hit lands. With this on, any punch that
    -- connects with real effort lands (damage still scales with skill and strength).
    committedPunchesAlwaysHit = true,
    -- Show every swing on screen (even in the air), handy for shadowboxing and tuning.
    showSwings = true,
    -- What counts as a punch (vs. arms pumping while you jog): the fist must finish at least
    -- this far in front of your face, and no more than this far below it.
    punchMinReach = 0.30,
    punchMaxDrop  = 0.45,
    punchMinReachMoving = 0.42,   -- stricter while you're jogging

    -- Where the game's own health/magic/fatigue panel sits. 'LeftWristTop' is the engine default
    -- (on your left wrist). 'HUDBottomLeft' would lock it in the lower-left of
    -- your view. Other options: 'HUDBottomRight', 'HUDTopLeft', 'HUDTopRight', 'LeftWristTop'
    -- (engine default). Set to false to leave whatever you picked in the VR settings menu.
    hudPosition = 'LeftWristTop',

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

    -- Dodging. Enemies telegraph each attack: the screen tells you SQUAT, SLIP LEFT or SLIP RIGHT.
    windupSlow  = 0.5,   -- enemy wind-ups play at this speed, giving you more time to react
    squatDrop   = 0.18,  -- squat: head this far below your standing height (m)
    slipDist    = 0.14,  -- slip: head this far sideways in the called direction (m)
    partialMove = 0.07,  -- any dodge movement this big (wrong direction / too small) = partial
    cleanAvoid = 0.45, partialAvoid = 0.15,
    cleanReduce = 0.5, partialReduce = 0.75,
    dodgeFatigueCost = 5,
    dodgeFalloff = 0.8,       -- each recent clean dodge multiplies the next chance by this
    dodgeMemory = 3.0,
}
