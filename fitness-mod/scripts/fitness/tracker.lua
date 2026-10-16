-- Workout tracker: counts steps, jumps, squats, punches and dodges, and estimates calories.
--
-- Calories use the standard MET method: every activity burns a multiple of your resting rate
-- (standing ~1.3x, walking 2.5-4x, jogging in place ~8x, punching ~7.8x, swimming ~5.3x),
-- and your resting rate comes from the Mifflin-St Jeor formula (weight, height, age, sex),
-- set in Options > Scripts > Fitness. It's an estimate, like any fitness tracker's.
local vr = require('openmw.vr')
if not vr.isVr() then return {} end

local self = require('openmw.self')
local core = require('openmw.core')
local storage = require('openmw.storage')
local util = require('openmw.util')
local I = require('openmw.interfaces')
local CFG = require('scripts.fitness.config')
local safe = require('scripts.fitness.safe')

local L10N = 'FitnessMod'
local GROUP = 'SettingsFitnessProfile'

I.Settings.registerPage({ key = 'FitnessMod', l10n = L10N, name = 'Fitness',
    description = 'Your body stats for the calorie estimate, and tracker display.\n'
        .. 'Your all-time workout totals show at the bottom of your view whenever the game is paused or a menu is open.' })
I.Settings.registerGroup({
    key = GROUP, page = 'FitnessMod', l10n = L10N, name = 'Fitness profile', permanentStorage = true,
    settings = {
        { key = 'units', renderer = 'select', name = 'Units', default = 'Imperial (lb, in)',
          argument = { l10n = L10N, items = { 'Imperial (lb, in)', 'Metric (kg, cm)' } } },
        { key = 'weight', renderer = 'number', name = 'Weight', default = 180,
          description = 'Pounds or kilograms, depending on Units.', argument = { integer = true, min = 50, max = 700 } },
        { key = 'height', renderer = 'number', name = 'Height', default = 70,
          description = 'Inches or centimetres, depending on Units.', argument = { integer = true, min = 36, max = 250 } },
        { key = 'age', renderer = 'number', name = 'Age', default = 35, argument = { integer = true, min = 10, max = 100 } },
        { key = 'sex', renderer = 'select', name = 'Sex', default = 'Male',
          description = 'Used for the resting calorie rate.', argument = { l10n = L10N, items = { 'Male', 'Female' } } },
        { key = 'showTracker', renderer = 'checkbox', name = 'Show workout summary in menus', default = true,
          description = 'This session and all-time totals at the bottom of your view whenever a menu is open.' },
    },
})
local profile = storage.playerSection(GROUP)

-- All-time totals survive restarts and new characters.
local totals = storage.playerSection('FitnessTotals')
totals:setLifeTime(storage.LIFE_TIME.Persistent)

local MET = { idle = 1.3, walk = 2.5, walkFast = 4.0, run = 8.0, punch = 7.8, swim = 5.3, rest = 1.0 }

local session = { steps = 0, jumps = 0, squats = 0, punches = 0, hits = 0, dodges = 0, kcal = 0 }
local activity, pace = 'idle', 0
local lastPunch = -100
local now, showTimer, saveTimer = 0, 0, 0

-- resting calories per second (Mifflin-St Jeor BMR / 86400)
local function restingKcalPerSec()
    local w, h, age = profile:get('weight') or 180, profile:get('height') or 70, profile:get('age') or 35
    if (profile:get('units') or 'Imperial (lb, in)'):find('^Imperial') then
        w, h = w * 0.4536, h * 2.54
    end
    local bmr = 10 * w + 6.25 * h - 5 * age + ((profile:get('sex') == 'Female') and -161 or 5)
    return math.max(bmr, 800) / 86400
end

local function currentMet()
    local m = MET.idle
    if activity == 'run' then m = MET.run
    elseif activity == 'walk' then m = MET.walk + (MET.walkFast - MET.walk) * pace
    elseif activity == 'swim' then m = MET.swim
    elseif activity == 'rest' then m = MET.rest end
    if now - lastPunch < 4 then m = math.max(m, MET.punch) end   -- throwing punches = boxing workout
    return m
end

local function add(key, n)
    session[key] = session[key] + n
    totals:set(key, (totals:get(key) or 0) + n)
end

local function commas(n)
    local s = tostring(math.floor(n + 0.5))
    return s:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
end

local KEYS = { 'steps', 'jumps', 'squats', 'punches', 'hits', 'dodges', 'kcal' }
local function allTimeText()
    local t = {}
    for _, k in ipairs(KEYS) do t[k] = (totals:get(k) or 0) + (k == 'kcal' and saveTimer or 0) end
    return string.format('THIS SESSION   %s steps   %d jumps   %d squats   %d punches   %s kcal\n'
        .. 'ALL TIME   %s steps   %s jumps   %s squats   %s punches (%s landed)   %s dodges   %s kcal',
        commas(session.steps), session.jumps, session.squats, session.punches, commas(session.kcal),
        commas(t.steps), commas(t.jumps), commas(t.squats), commas(t.punches), commas(t.hits),
        commas(t.dodges), commas(t.kcal))
end

-- coach.lua shows this summary whenever the game is paused / a menu is open
local summary = storage.playerSection('FitnessSummary')
summary:setLifeTime(storage.LIFE_TIME.Temporary)

local function onFrame(dt)
    if dt <= 0 then return end
    now = now + dt
    if not core.isWorldPaused() then
        local kcal = currentMet() * restingKcalPerSec() * dt
        session.kcal = session.kcal + kcal
        saveTimer = saveTimer + kcal
        if saveTimer > 0.5 then   -- don't write storage every frame
            totals:set('kcal', (totals:get('kcal') or 0) + saveTimer)
            saveTimer = 0
        end
    end
    showTimer = showTimer - dt
    if showTimer > 0 then return end
    showTimer = 0.5
    -- shown only while a menu is open / the game is paused (coach.lua), not during play
    summary:set('text', profile:get('showTracker') ~= false and allTimeText() or nil)
end

-- Backup copy of the totals inside every save game. Saves live in the Quest's Morrowind folder,
-- which survives reinstalls; the totals file itself is in the app's folder, which doesn't.
-- Loading a save never lowers your totals, only restores them if they were lost.
local function onSave()
    local t = {}
    for _, k in ipairs(KEYS) do t[k] = totals:get(k) or 0 end
    return { fitnessTotals = t }
end
local function onLoad(data)
    local saved = data and data.fitnessTotals
    if not saved then return end
    local restored = false
    for _, k in ipairs(KEYS) do
        if (saved[k] or 0) > (totals:get(k) or 0) then totals:set(k, saved[k]); restored = true end
    end
    if restored then print('[fitness] all-time totals restored from your save') end
end

local logTimer = 0
return {
    engineHandlers = {
        onSave = onSave,
        onLoad = onLoad,
        onFrame = safe('tracker', function(dt)
            onFrame(dt)
            logTimer = logTimer + math.max(dt, 0)
            if logTimer > 60 then
                logTimer = 0
                print(string.format('[fitness] session: %d steps, %d jumps, %d squats, %d punches (%d landed), %d dodges, %.0f kcal | all-time %.0f kcal',
                    session.steps, session.jumps, session.squats, session.punches, session.hits, session.dodges, session.kcal,
                    totals:get('kcal') or 0))
            end
        end),
    },
    eventHandlers = {
        FitTally = safe('tracker tally', function(d)
            for k, n in pairs(d) do
                if session[k] then add(k, n) end
                if k == 'punches' then lastPunch = now end
            end
        end),
        FitActivity = safe('tracker activity', function(d) activity, pace = d.state, d.pace or 0 end),
    },
}
