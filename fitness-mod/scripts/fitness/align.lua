-- Keeps you lined up with your character. In roomscale your head can wander away from where the
-- game thinks your body is, so enemies end up swinging beside you. When the gap gets big enough
-- (and you're not mid-swing), the view is re-centred on the character - same as the Recenter button.
local vr = require('openmw.vr')
if not vr.isVr() then return {} end
local self = require('openmw.self')
local util = require('openmw.util')
local I = require('openmw.interfaces')
local CFG = require('scripts.fitness.config')
local safe = require('scripts.fitness.safe')

local U = I.vrspaces.unitsPerMeter
local headWorld = nil
local now, lastRecenter, overSince = 0, -10, nil
local logTimer = 0

local function onVRFrame()
    headWorld = I.vrspaces.locateSpaceInWorld(I.vrspaces.referenceSpaces.View)
end

local function onFrame(dt)
    if dt <= 0 or not CFG.recenterDist or not headWorld then return end
    now = now + dt
    local d = headWorld.position - self.position
    local gap = util.vector2(d.x, d.y):length() / U
    logTimer = logTimer + dt
    if logTimer > 5 then
        logTimer = 0
        print(string.format('[fitness] body offset %.2fm', gap))
    end
    if gap > CFG.recenterDist then
        overSince = overSince or now
        -- wait a moment so a quick lean or dodge doesn't trigger it
        if now - overSince > 0.8 and now - lastRecenter > 3 then
            lastRecenter = now
            overSince = nil
            I.vrspaces.recenterXY()
            print(string.format('[fitness] re-centred (offset was %.2fm)', gap))
            self.object:sendEvent('FitCoach', { slot = 'status', text = 're-centred on your character', secs = 1.0,
                color = util.color.rgb(0.7, 0.85, 1) })
        end
    else
        overSince = nil
    end
end

return { engineHandlers = { onFrame = safe('align', onFrame), onVRFrame = safe('align vr', onVRFrame) } }
