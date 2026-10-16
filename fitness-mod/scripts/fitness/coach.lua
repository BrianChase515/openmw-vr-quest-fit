-- The fitness HUD: one fixed screen in front of you.
--   centre line: guidance ("SQUAT!", "SLIP LEFT", "DODGED") - big
--   status line (lower): what you just threw, combos
-- Other fitness scripts send it a 'FitCoach' event: { slot = 'centre'|'status', text, color, secs }.
local vr = require('openmw.vr')
if not vr.isVr() then return {} end
local ui = require('openmw.ui')
local util = require('openmw.util')
local core = require('openmw.core')
local storage = require('openmw.storage')
local summary = storage.playerSection('FitnessSummary')
local CFG = require('scripts.fitness.config')
local safe = require('scripts.fitness.safe')

-- 'Notification' is a VR layer that is locked to your view (the game's own message popups use it).
local LAYER = 'Notification'
local self = require('openmw.self')
local types = require('openmw.types')
local now = 0
local enemyTimer = 0
local slots = {
    centre = { y = CFG.coachCentreY, size = 44 },
    speed  = { y = CFG.coachSpeedY or 0.555, size = 30 },   -- punch type + hand speed, colour-graded
    status = { y = CFG.coachStatusY, size = 28 },
    tally  = { y = CFG.coachTallyY or 0.82, size = 22 },
}
local function element(slot)
    if slot.el then return slot.el end
    local ok, el = pcall(ui.create, {
        layer = LAYER, type = ui.TYPE.Text,
        props = { text = '', textSize = slot.size, textColor = util.color.rgb(1, 1, 1), multiline = true,
                  textAlignH = ui.ALIGNMENT.Center,
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

-- Health / magicka / fatigue: a label + a bar each, coloured by how much is left.
local WHITE_TEX = ui.texture { path = 'white' }
local STATS = { { key = 'health', label = 'HEALTH' }, { key = 'magicka', label = 'MAGICKA' }, { key = 'fatigue', label = 'FATIGUE' } }
local BAR_W, BAR_H, GAP = 200, 16, 30
local statsEl, statsParts = nil, {}
local statsTimer = 0

local function pctColor(p)
    if p > 0.6 then return util.color.rgb(0.35, 0.9, 0.4) end
    if p > 0.3 then return util.color.rgb(1.0, 0.8, 0.25) end
    return util.color.rgb(1.0, 0.3, 0.25)
end

local function buildStats()
    local content = {}
    for i, st in ipairs(STATS) do
        local x = (i - 1) * (BAR_W + GAP)
        local label = { type = ui.TYPE.Text, props = { position = util.vector2(x, 0), text = st.label,
            textSize = 20, textColor = util.color.rgb(1, 1, 1), textShadow = true, textShadowColor = util.color.rgb(0, 0, 0) } }
        local back = { type = ui.TYPE.Image, props = { position = util.vector2(x, 26), size = util.vector2(BAR_W, BAR_H),
            resource = WHITE_TEX, color = util.color.rgb(0.1, 0.1, 0.1), alpha = 0.7 } }
        local fill = { type = ui.TYPE.Image, props = { position = util.vector2(x, 26), size = util.vector2(BAR_W, BAR_H),
            resource = WHITE_TEX, color = util.color.rgb(0.35, 0.9, 0.4) } }
        statsParts[st.key] = { label = label, fill = fill, text = st.label }
        content[#content + 1] = back
        content[#content + 1] = fill
        content[#content + 1] = label
    end
    local ok, el = pcall(ui.create, {
        layer = LAYER, type = ui.TYPE.Widget,
        props = { relativePosition = util.vector2(0.5, CFG.coachStatsY), anchor = util.vector2(0.5, 0.5),
                  size = util.vector2(3 * BAR_W + 2 * GAP, 26 + BAR_H) },
        content = ui.content(content),
    })
    if ok then statsEl = el else print('[fitness] coach: stats bars failed: ' .. tostring(el)) end
end

-- Your bars show when they matter: while something is fighting you (and 10 s after), for a few
-- seconds after you lose health or magicka outside a fight, and always when health is low.
-- The rest of the time check your wrist. config.lua: statsMode = 'combat' (default) or 'always'.
local lastFight, lastDrop = -100, -100
local prevHealth, prevMagicka
local function statsWanted()
    if CFG.statsMode == 'always' then return true end
    if now - lastFight < (CFG.statsHideAfterCombat or 10) then return true end
    if now - lastDrop < 5 then return true end
    local h = types.Actor.stats.dynamic.health(self)
    local hmax = math.max((h.base or 0) + (h.modifier or 0), 1)
    return h.current / hmax < (CFG.statsAlwaysBelow or 0.35)
end

local function updateStats(dt)
    if not CFG.showStats then return end
    statsTimer = statsTimer - dt
    if statsTimer > 0 then return end
    statsTimer = 0.25
    if not statsEl then buildStats() end
    if not statsEl then return end
    local d = types.Actor.stats.dynamic
    local hc, mc = d.health(self).current, d.magicka(self).current
    if (prevHealth and hc < prevHealth - 0.5) or (prevMagicka and mc < prevMagicka - 0.5) then lastDrop = now end
    prevHealth, prevMagicka = hc, mc
    local want = statsWanted()
    if statsEl.layout.props.visible ~= want then
        statsEl.layout.props.visible = want
        statsEl:update()
    end
    if not want then return end
    for _, st in ipairs(STATS) do
        local stat = d[st.key](self)
        local max = math.max((stat.base or 0) + (stat.modifier or 0), 1)
        local cur = math.max(stat.current or 0, 0)
        local p = math.min(cur / max, 1)
        local part = statsParts[st.key]
        part.fill.props.size = util.vector2(math.max(BAR_W * p, 1), BAR_H)
        part.fill.props.color = pctColor(p)
        part.label.props.text = string.format('%s  %d/%d', part.text, cur, max)
        part.label.props.textColor = pctColor(p)
    end
    statsEl:update()
end

-- Enemy panel (top): name + health + fatigue of whoever is fighting you (nearest if several).
local enemies = {}         -- id -> latest status
local finished = {}        -- id -> true once a defeated enemy's bars have had their moment
local HIDE_AFTER_DEATH = CFG.enemyHideAfterDeath or 10
local enemyEl, enemyParts = nil, nil
local ENEMY_W = 420

local function buildEnemy()
    local name = { type = ui.TYPE.Text, props = { position = util.vector2(0, 0), text = '',
        textSize = 22, textColor = util.color.rgb(1, 0.85, 0.6), textShadow = true, textShadowColor = util.color.rgb(0, 0, 0) } }
    local rows, content = {}, { name }
    for i, key in ipairs({ 'health', 'fatigue' }) do
        local y = 28 + (i - 1) * 24
        local back = { type = ui.TYPE.Image, props = { position = util.vector2(0, y), size = util.vector2(ENEMY_W, 16),
            resource = WHITE_TEX, color = util.color.rgb(0.1, 0.1, 0.1), alpha = 0.7 } }
        local fill = { type = ui.TYPE.Image, props = { position = util.vector2(0, y), size = util.vector2(ENEMY_W, 16),
            resource = WHITE_TEX, color = util.color.rgb(0.9, 0.3, 0.25) } }
        local label = { type = ui.TYPE.Text, props = { position = util.vector2(ENEMY_W + 10, y - 3), text = '',
            textSize = 18, textColor = util.color.rgb(1, 1, 1), textShadow = true, textShadowColor = util.color.rgb(0, 0, 0) } }
        rows[key] = { fill = fill, label = label }
        content[#content + 1] = back
        content[#content + 1] = fill
        content[#content + 1] = label
    end
    local ok, el = pcall(ui.create, {
        layer = LAYER, type = ui.TYPE.Widget,
        props = { relativePosition = util.vector2(0.5, CFG.coachEnemyY), anchor = util.vector2(0.5, 0),
                  size = util.vector2(ENEMY_W + 140, 80), visible = false },
        content = ui.content(content),
    })
    if ok then enemyEl, enemyParts = el, { name = name, rows = rows } else print('[fitness] coach: enemy bar failed: ' .. tostring(el)) end
end

local function updateEnemy()
    if not CFG.showEnemy then return end
    -- pick the nearest living enemy that reported in the last 1.5 s; a defeated one stays up
    -- (marked DEFEATED) for a few seconds when nobody else is fighting you, then goes away
    local best, bestDist, bestAlive
    for id, e in pairs(enemies) do
        if (e.health or 1) <= 0 and not e.deadAt then e.deadAt = now end
        if now - e.t > 1.5 then
            enemies[id] = nil
        elseif e.deadAt and now - e.deadAt > HIDE_AFTER_DEATH then
            enemies[id], finished[id] = nil, true
        else
            local alive = not e.deadAt
            local dist = e.pos and (e.pos - self.position):length() or 0
            if not best or (alive and not bestAlive) or (alive == bestAlive and dist < bestDist) then
                best, bestDist, bestAlive = e, dist, alive
            end
        end
    end
    if not enemyEl then
        if not best then return end
        buildEnemy()
        if not enemyEl then return end
    end
    if not best then
        if enemyEl.layout.props.visible then enemyEl.layout.props.visible = false; enemyEl:update() end
        return
    end
    enemyEl.layout.props.visible = true
    enemyParts.name.props.text = best.deadAt and (best.name .. '  -  DEFEATED') or best.name
    for key, row in pairs(enemyParts.rows) do
        local cur, max = math.max(best[key] or 0, 0), math.max(best[key .. 'Max'] or 1, 1)
        local p = math.min(cur / max, 1)
        row.fill.props.size = util.vector2(math.max(ENEMY_W * p, 1), 16)
        row.fill.props.color = key == 'health' and util.color.rgb(0.9, 0.3, 0.25) or util.color.rgb(0.35, 0.8, 0.4)
        row.label.props.text = string.format('%s %d/%d', key == 'health' and 'HP' or 'FAT', cur, max)
    end
    enemyEl:update()
end

-- Full-view colour flash for dodge results / calls, fading out.
local flashEl, flashUntil, flashLen = nil, 0, 0.5
local centreBox = nil
local function flash(color, secs)
    if not flashEl then
        local ok, el = pcall(ui.create, { layer = LAYER, type = ui.TYPE.Image, props = {
            relativePosition = util.vector2(0, 0), relativeSize = util.vector2(1, 1),
            resource = WHITE_TEX, color = color, alpha = 0 } })
        if not ok then return end
        flashEl = el
    end
    flashLen = secs or 0.5
    flashUntil = now + flashLen
    flashEl.layout.props.color = color
    flashEl.layout.props.alpha = 0.35
    flashEl:update()
end
local function updateFlash()
    if not flashEl or flashEl.layout.props.alpha == 0 then return end
    local left = flashUntil - now
    flashEl.layout.props.alpha = left > 0 and 0.35 * (left / flashLen) or 0
    flashEl:update()
end
local function setCentreBox(visible)
    if not centreBox then
        local ok, el = pcall(ui.create, { layer = LAYER, type = ui.TYPE.Image, props = {
            relativePosition = util.vector2(0.5, CFG.coachCentreY), anchor = util.vector2(0.5, 0.5),
            size = util.vector2(760, 96), resource = WHITE_TEX, color = util.color.rgb(0, 0, 0), alpha = 0.55,
            visible = false } })
        if not ok then return end
        centreBox = el
    end
    if centreBox.layout.props.visible ~= visible then
        centreBox.layout.props.visible = visible
        centreBox:update()
    end
end

local function show(data)
    if data.flash then flash(data.flash, data.flashSecs) end
    if data.slot == 'centre' then setCentreBox((data.text or '') ~= '') end
    local slot = slots[data.slot or 'status']
    if not slot then return end
    local el = element(slot)
    el.layout.props.text = data.text or ''
    el.layout.props.textColor = data.color or util.color.rgb(1, 1, 1)
    el.layout.props.textSize = data.size or slot.size
    el:update()
    slot.until_ = now + (data.secs or 1.5)
end

local greeted = false
-- Compass (upper right): which way you're looking, as a strip of directions with your heading under it.
local I = require('openmw.interfaces')
local compassEl, headYaw, compassTimer = nil, nil, 0
local POINTS = { [0] = 'N', [45] = 'NE', [90] = 'E', [135] = 'SE', [180] = 'S', [225] = 'SW', [270] = 'W', [315] = 'NW' }
local NAMES16 = { 'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', 'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW' }
local function onVRFrame()
    if not CFG.showCompass then return end
    local head = I.vrspaces.locateSpaceInWorld(I.vrspaces.referenceSpaces.View)
    if head and head.orientation then
        local f = head.orientation * util.vector3(0, 1, 0)
        if f.x * f.x + f.y * f.y > 1e-4 then headYaw = math.deg((math.atan2 or math.atan)(f.x, f.y)) % 360 end
    end
end
local function updateCompass(dt)
    if not CFG.showCompass or not headYaw then return end
    compassTimer = compassTimer - math.max(dt, 0.001)
    if compassTimer > 0 then return end
    compassTimer = 0.05
    -- strip from -90 to +90 degrees around where you look, one slot per 15 degrees
    local parts = {}
    for i = -6, 6 do
        local a = math.floor((headYaw + i * 15) / 15 + 0.5) * 15 % 360
        parts[#parts + 1] = POINTS[a] or ((i == 0) and '|' or '.')
    end
    local text = table.concat(parts, '  ') .. '\n' .. string.format('%s  %03d', NAMES16[math.floor(headYaw / 22.5 + 0.5) % 16 + 1], math.floor(headYaw + 0.5) % 360)
    if not compassEl then
        local ok, el = pcall(ui.create, { layer = LAYER, type = ui.TYPE.Text, props = {
            text = text, textSize = 22, multiline = true, textAlignH = ui.ALIGNMENT.Center,
            textColor = util.color.rgb(1, 0.92, 0.7), textShadow = true, textShadowColor = util.color.rgb(0, 0, 0),
            relativePosition = util.vector2(CFG.compassX or 0.8, CFG.compassY or 0.07), anchor = util.vector2(0.5, 0) } })
        if not ok then CFG.showCompass = false; print('[fitness] compass failed: ' .. tostring(el)); return end
        compassEl = el
        return
    end
    if compassEl.layout.props.text ~= text then
        compassEl.layout.props.text = text
        compassEl:update()
    end
end

local pausedShown = false
local function onFrame(dt)
    now = now + math.max(dt, 0)
    -- game paused / menu open: workout summary (this session + all time) at the bottom of your view
    if core.isWorldPaused() then
        if not pausedShown and summary:get('text') then
            pausedShown = true
            show({ slot = 'tally', text = summary:get('text'), secs = 0.1, size = 24,
                   color = util.color.rgb(0.75, 0.9, 1) })
        end
    else
        pausedShown = false
    end
    if not greeted and now > 2 then
        greeted = true
        show({ slot = 'centre', text = 'FITNESS MOD READY', secs = 3, color = util.color.rgb(0.6, 1, 0.6) })
        show({ slot = 'status', text = 'punch info shows here', secs = 3, color = util.color.rgb(0.8, 0.8, 0.8) })
    end
    updateStats(dt)
    updateFlash()
    updateCompass(dt)
    enemyTimer = (enemyTimer or 0) - dt
    if enemyTimer <= 0 then enemyTimer = 0.25; updateEnemy() end
    for _, slot in pairs(slots) do
        if slot.el and slot.until_ and now > slot.until_ then
            slot.until_ = nil
            slot.el.layout.props.text = ''
            slot.el:update()
            if slot == slots.centre then setCentreBox(false) end
        end
    end
end

return {
    engineHandlers = { onFrame = safe('coach', onFrame), onVRFrame = safe('coach vr', onVRFrame) },
    eventHandlers = {
        FitCoach = safe('coach show', show),
        FitEnemyStatus = safe('coach enemy', function(e)
            if (e.health or 1) > 0 then lastFight = now end
            if finished[e.id] then return end
            local old = enemies[e.id]
            e.t, e.deadAt = now, old and old.deadAt
            enemies[e.id] = e
        end),
    },
}
