-- The fitness HUD: one fixed screen in front of you.
--   centre line: guidance ("SQUAT!", "SLIP LEFT", "DODGED") - big
--   status line (lower): what you just threw, combos
-- Other fitness scripts send it a 'FitCoach' event: { slot = 'centre'|'status', text, color, secs }.
local vr = require('openmw.vr')
if not vr.isVr() then return {} end
local ui = require('openmw.ui')
local util = require('openmw.util')
local core = require('openmw.core')
local CFG = require('scripts.fitness.config')
local safe = require('scripts.fitness.safe')

-- 'Notification' is a VR layer that is locked to your view (the game's own message popups use it).
local LAYER = 'Notification'
local self = require('openmw.self')
local types = require('openmw.types')
local slots = {
    centre = { y = CFG.coachCentreY, size = 44 },
    status = { y = CFG.coachStatusY, size = 28 },
    stats  = { y = CFG.coachStatsY,  size = 24 },
}
local function element(slot)
    if slot.el then return slot.el end
    local ok, el = pcall(ui.create, {
        layer = LAYER, type = ui.TYPE.Text,
        props = { text = '', textSize = slot.size, textColor = util.color.rgb(1, 1, 1),
                  textShadow = true, textShadowColor = util.color.rgb(0, 0, 0),
                  relativePosition = util.vector2(0.5, slot.y), anchor = util.vector2(0.5, 0.5) },
    })
    if not ok then
        print('[fitness] coach: could not use layer ' .. LAYER .. ', falling back to HUD: ' .. tostring(el))
        LAYER = 'HUD'
        return element(slot)
    end
    slot.el = el
    return el
end

local statsTimer = 0
local function updateStats(dt)
    if not CFG.showStats then return end
    statsTimer = statsTimer - dt
    if statsTimer > 0 then return end
    statsTimer = 0.25
    local d = types.Actor.stats.dynamic
    local h, m, f = d.health(self), d.magicka(self), d.fatigue(self)
    local slot = slots.stats
    local el = element(slot)
    el.layout.props.text = string.format('HEALTH %d/%d     MAGICKA %d/%d     FATIGUE %d/%d',
        h.current, h.base + h.modifier, m.current, m.base + m.modifier, f.current, f.base + f.modifier)
    local low = f.current < 0.25 * (f.base + f.modifier) or h.current < 0.25 * (h.base + h.modifier)
    el.layout.props.textColor = low and util.color.rgb(1, 0.5, 0.4) or util.color.rgb(0.85, 0.85, 0.85)
    el:update()
end
local now = 0

local function show(data)
    local slot = slots[data.slot or 'status']
    if not slot then return end
    local el = element(slot)
    el.layout.props.text = data.text or ''
    el.layout.props.textColor = data.color or util.color.rgb(1, 1, 1)
    el:update()
    slot.until_ = now + (data.secs or 1.5)
end

local greeted = false
local function onFrame(dt)
    now = now + math.max(dt, 0)
    if not greeted and now > 2 then
        greeted = true
        show({ slot = 'centre', text = 'FITNESS MOD READY', secs = 3, color = util.color.rgb(0.6, 1, 0.6) })
        show({ slot = 'status', text = 'punch info shows here', secs = 3, color = util.color.rgb(0.8, 0.8, 0.8) })
    end
    updateStats(dt)
    for _, slot in pairs(slots) do
        if slot.el and slot.until_ and now > slot.until_ then
            slot.until_ = nil
            slot.el.layout.props.text = ''
            slot.el:update()
        end
    end
end

return {
    engineHandlers = { onFrame = safe('coach', onFrame) },
    eventHandlers = { FitCoach = safe('coach show', show) },
}
