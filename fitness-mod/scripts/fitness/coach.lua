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
local now = 0
local enemyTimer = 0
local slots = {
    centre = { y = CFG.coachCentreY, size = 44 },
    status = { y = CFG.coachStatusY, size = 28 },
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

local function updateStats(dt)
    if not CFG.showStats then return end
    statsTimer = statsTimer - dt
    if statsTimer > 0 then return end
    statsTimer = 0.25
    if not statsEl then buildStats() end
    if not statsEl then return end
    local d = types.Actor.stats.dynamic
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
    -- pick the nearest enemy that reported in the last 1.5 s
    local best, bestDist
    for id, e in pairs(enemies) do
        if now - e.t > 1.5 then
            enemies[id] = nil
        else
            local dist = e.pos and (e.pos - self.position):length() or 0
            if not best or dist < bestDist then best, bestDist = e, dist end
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
    enemyParts.name.props.text = best.name
    for key, row in pairs(enemyParts.rows) do
        local cur, max = math.max(best[key] or 0, 0), math.max(best[key .. 'Max'] or 1, 1)
        local p = math.min(cur / max, 1)
        row.fill.props.size = util.vector2(math.max(ENEMY_W * p, 1), 16)
        row.fill.props.color = key == 'health' and util.color.rgb(0.9, 0.3, 0.25) or util.color.rgb(0.35, 0.8, 0.4)
        row.label.props.text = string.format('%s %d/%d', key == 'health' and 'HP' or 'FAT', cur, max)
    end
    enemyEl:update()
end

local function show(data)
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
local function onFrame(dt)
    now = now + math.max(dt, 0)
    if not greeted and now > 2 then
        greeted = true
        show({ slot = 'centre', text = 'FITNESS MOD READY', secs = 3, color = util.color.rgb(0.6, 1, 0.6) })
        show({ slot = 'status', text = 'punch info shows here', secs = 3, color = util.color.rgb(0.8, 0.8, 0.8) })
    end
    updateStats(dt)
    enemyTimer = (enemyTimer or 0) - dt
    if enemyTimer <= 0 then enemyTimer = 0.25; updateEnemy() end
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
    eventHandlers = {
        FitCoach = safe('coach show', show),
        FitEnemyStatus = safe('coach enemy', function(e) e.t = now; enemies[e.id] = e end),
    },
}
