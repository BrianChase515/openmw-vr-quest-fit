-- Comeback anthem: when you drop to half health (or less) in a fight, your own fight song starts.
--
-- No music ships with the mod. Drop any .mp3 / .ogg / .wav you own into
--   Documents\openmw-fitness\music   on the PC (the installer copies it to the Quest)
-- or straight into  Data Files/music/fitness/  on the headset.
-- One file = that song every time; several = a random one each fight.
--
-- It plays once per fight and runs to the end (or until the fight's over, when the game's
-- normal music comes back by itself). Settings: Options > Scripts > Fitness.
local vr = require('openmw.vr')
if not vr.isVr() then return {} end

local self = require('openmw.self')
local core = require('openmw.core')
local types = require('openmw.types')
local ambient = require('openmw.ambient')
local vfs = require('openmw.vfs')
local storage = require('openmw.storage')
local util = require('openmw.util')
local I = require('openmw.interfaces')
local safe = require('scripts.fitness.safe')

local GROUP = 'SettingsFitnessAnthem'
I.Settings.registerGroup({
    key = GROUP, page = 'FitnessMod', l10n = 'FitnessMod', name = 'Comeback anthem', permanentStorage = true,
    description = 'Plays your own song from Data Files/music/fitness when you are hurt in a fight.',
    settings = {
        { key = 'enabled', renderer = 'checkbox', name = 'Play anthem when hurt in combat', default = true },
        { key = 'threshold', renderer = 'number', name = 'Health % that starts it', default = 50,
          argument = { integer = true, min = 10, max = 90 } },
    },
})
local settings = storage.playerSection(GROUP)

local FOLDER = 'music/fitness/'
local AUDIO = { mp3 = true, ogg = true, wav = true, flac = true }

local tracks
local function findTracks()
    tracks = {}
    for path in vfs.pathsWithPrefix(FOLDER) do
        local ext = path:match('%.(%w+)$')
        if ext and AUDIO[ext:lower()] then tracks[#tracks + 1] = path end
    end
    print(string.format('[fitness] anthem: %d track(s) in %s', #tracks, FOLDER))
end

local lastEnemySeen = -100
local inFight, played = false, false
local lowFor, now = 0, 0

local function onFrame(dt)
    if dt <= 0 or core.isWorldPaused() then return end
    now = now + dt
    if not tracks then findTracks() end

    local fighting = now - lastEnemySeen < 3
    if not fighting then
        inFight, played, lowFor = false, false, 0   -- fight over: game music takes back over
        return
    end
    inFight = true
    if played or #tracks == 0 or settings:get('enabled') == false then return end
    if types.Actor.isDead(self) then return end

    local h = types.Actor.stats.dynamic.health(self)
    local max = h.base + h.modifier
    local pct = max > 0 and h.current / max * 100 or 100
    if pct <= (settings:get('threshold') or 50) then
        lowFor = lowFor + dt
    else
        lowFor = 0
    end
    if lowFor >= 0.5 then   -- let the game's battle music start first, then cut over
        played = true
        local track = tracks[math.random(#tracks)]
        ambient.streamMusic(track, { fadeOut = 0.5 })
        self.object:sendEvent('FitCoach', { slot = 'status', secs = 2.5, size = 40,
            color = util.color.rgb(1, 0.8, 0.2), text = 'GET UP!' })
        print('[fitness] anthem: ' .. track .. string.format(' at %.0f%% health', pct))
    end
end

return {
    engineHandlers = {
        onFrame = safe('anthem', onFrame),
    },
    eventHandlers = {
        FitEnemyStatus = function() lastEnemySeen = now end,
        Died = function() played = true end,
    },
}
