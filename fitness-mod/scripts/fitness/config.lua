-- Shared tuning for the fitness mod. Distances in metres, times in seconds.
return {
    debugHud = false,         -- extra movement readout on the status line (for tuning)

    -- Fitness HUD layout (fractions of the view panel, 0 = top, 1 = bottom)
    coachCentreY = 0.22,
    coachSpeedY  = 0.555,  -- punch speed readout (just above the combo line)
    coachStatusY = 0.62,
    coachStatsY  = 0.74,
    coachTallyY  = 0.82,   -- workout tracker line (steps, jumps, squats, punches, kcal)
    showStats    = true,   -- health / magicka / fatigue bars on the bottom line
    statsMode    = 'combat',   -- 'combat': show them while fighting (+10 s), after losing health/magicka, or when health is low; 'always'
    statsHideAfterCombat = 10,
    statsAlwaysBelow = 0.35,   -- health or fatigue fraction below which your bars always show
    showCompass  = true,   -- direction you're facing (N, NE, E...) in the upper right
    compassX = 0.85, compassY = 0.08, compassSize = 26,
    jumpButtonOpensMap = true,   -- you jump for real, so the jump button (left trigger) opens the map instead
    showEnemy    = true,   -- enemy name + health / fatigue bars at the top while fighting
    coachEnemyY  = 0.06,
    enemyHideAfterDeath = 10,   -- seconds a defeated enemy's bars stay up before disappearing
    -- Keep your body lined up with your character: if your head ends up this far (m) from the
    -- character (walking around the room), the view re-centres. false = never.
    recenterDist = 0.35,
    -- Warn when jogging in place has carried you this far (m) from where the jog started.
    -- Off (false) for roomscale play; set to e.g. 0.5 if you play in a small space.
    driftWarn    = false,

    -- Effort gate: the engine reports punch strength 0..1 from hand speed,
    -- strength = (speed - 1.0) / 4.0 with default VR settings, so 0.5 = 3.0 m/s.
    -- The engine now ignores swings under 2.8 m/s (set in the build), so any strength counts here.
    minPunchStrength = 0.05,
    -- Morrowind rolls your skill to decide if a hit lands. With this on, any punch that
    -- connects with real effort lands (damage still scales with skill and strength).
    committedPunchesAlwaysHit = true,
    -- Show every swing on screen (even in the air), handy for shadowboxing and tuning.
    showSwings = true,
    -- Punch speed grades (m/s at the controller). Green = good, yellow = OK, red = push harder.
    -- Set for a strong puncher; the rear-hand straight (cross) and hooks travel further, so they're graded higher.
    -- Your stance (which hand leads) is in Options > Scripts > Fitness.
    speedGrades = {
        -- set from a real session: your hardest ~40% of punches are green
        jab      = { green = 6.6, yellow = 5.0 },
        cross    = { green = 7.4, yellow = 5.5 },
        hook     = { green = 9.0, yellow = 6.5 },
        uppercut = { green = 9.0, yellow = 6.5 },
        punch    = { green = 7.5, yellow = 5.5 },
    },
    punchMinSpeedMoving = 3.8, -- while your feet are moving, slower swings are taken as jogging arms
    punchFastSpeed = 5.0,      -- swings this fast are punches wherever they finish (arm pumps are ~3 m/s)
    punchMaxDropFast = 0.65,   -- ...down to body-shot height (m below your eyes)
    hookMinReach = -0.25,      -- slower hooks: finish beside the head is fine
    uppercutMinReach = -0.15,  -- slower uppercuts: finish close in is fine
    -- What counts as a punch (vs. arms pumping while you jog): the fist must finish at least
    -- this far in front of your face, and no more than this far below it.
    punchMinReach = 0.30,
    punchMaxDrop  = 0.45,
    punchMinReachMoving = 0.42,   -- stricter while you're jogging

    -- The game's own wrist HUD panel (health bars, minimap, equipped icons).
    -- 'hidden' (default): never shown - the fitness HUD shows your stats.
    -- 'watch' (experimental): shows when you check your left wrist like a watch. Or always shown at 'LeftWristTop' (game default), 'HUDBottomLeft', ...
    hudPosition = 'hidden',
    watchSpace = 'LeftWristInner',   -- where it appears when you check: inner wrist (or 'LeftWristTop')
    watchPixelsPerMeter = 1024,      -- smaller = bigger panel

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
