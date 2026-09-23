local Vegetation = {}
Vegetation.list = {}
Vegetation.healRate = 4.0  -- Heal speed (HP per second when surviving)
Vegetation.destroyed = false
Vegetation.totalCreated = 0

-- Initialize or clear vegetation data
function Vegetation.init()
    Vegetation.list = {}
    Vegetation.destroyed = false
    Vegetation.totalCreated = 0
end

function Vegetation.isDestroyed()
    return Vegetation.destroyed
end

function Vegetation.getCount()
    return #Vegetation.list
end

-- Create an individual grass tuft attached to a specific Box2D body
function Vegetation.createGrass(body, localX, localY, w, h, localAngle)
    if not body or body:isDestroyed() then return nil end

    -- Generate a realistic organic blend for Healthy Grass (Vibrant lush green)
    local hR = 0.10 + math.random() * 0.08
    local hG = 0.65 + math.random() * 0.15
    local hB = 0.12 + math.random() * 0.06
    
    -- Generate a realistic organic blend for Decayed/Yellow Grass (Dry straw/yellow)
    local dR = 0.85 + math.random() * 0.10
    local dG = 0.74 + math.random() * 0.10
    local dB = 0.15 + math.random() * 0.06
    
    local maxHp = 100
    local grass = {
        type = "grass",
        body = body,
        localX = localX or 0,
        localY = localY or 0,
        localAngle = localAngle or 0,
        
        -- Health & state
        health = maxHp,
        maxHealth = maxHp,
        
        -- Absolute coordinates synchronized dynamically during updates
        x = 0, y = 0,
        
        -- Core structural dimensions
        w = w or (3.5 + math.random() * 2.5),
        h = h or (16 + math.random() * 18), -- High height variance for wilder look
        
        -- Dynamic bending variables
        angle = 0,                       
        angularVelocity = 0,
        stiffness = 0 + math.random(12),
        damping = 4.5 + math.random() * 1.5,
        maxBend = math.pi / 1.5,
        
        -- Complex layered wind properties (Base breeze + Gusts)
        windFreq = 1.2 + math.random() * 1.5,
        windGustFreq = 2.5 + math.random() * 2.0,
        windStrength = 0.02 + math.random() * 0.03,
        
        -- Colors: 100% health = healthyColor (green), 0% health = deadColor (yellow)
        healthyColor = { hR, hG, hB },
        deadColor = { dR, dG, dB },
        
        -- Procedural Blades: Generate 2 to 5 distinct blades per tuft for organic clustering
        blades = {}
    }
    
    local numBlades = math.random(2, 5)
    for i = 1, numBlades do
        table.insert(grass.blades, {
            -- Random spread angle for this specific blade
            angleOffset = (math.random() - 0.5) * 0.9,
            -- Height multiplier (some blades in the tuft are short, some tall)
            heightMod = 0.5 + math.random() * 0.7,
            -- Width multiplier
            widthMod = 0.6 + math.random() * 0.6,
            -- Slight color variance per blade
            colorMod = 0.85 + math.random() * 0.3,
            -- Natural static curve (makes blades droop slightly naturally)
            curve = (math.random() - 0.5) * 0.4
        })
    end
    
    -- Initial absolute coordinate lock
    grass.x, grass.y = body:getWorldPoint(grass.localX, grass.localY)
    table.insert(Vegetation.list, grass)
    Vegetation.totalCreated = Vegetation.totalCreated + 1
    Vegetation.destroyed = false
    return grass
end

-- Helper to populate a specific body's surface dynamically
-- @param densityMulti: Multiplier for grass thickness (e.g., 1.0 is normal, 2.0 is very dense)
function Vegetation.populateBody(body, densityMulti)
    if not body or body:isDestroyed() then return end
    densityMulti = densityMulti or 1.0
    
    local fixtures = body:getFixtures()
    if not fixtures or #fixtures == 0 then return end
    
    for _, fixture in ipairs(fixtures) do
        local shape = fixture:getShape()
        local shapeType = shape:getType()
        
        if shapeType == "polygon" then
            local points = {shape:getPoints()}
            if #points >= 6 then -- Polygons have at least 3 vertices
                local bestEdge = nil
                local bestY = math.huge -- Looking for the lowest Y normal (points UP in screen space)
                
                local numPoints = #points / 2
                for i = 1, numPoints do
                    local idx1 = (i - 1) * 2 + 1
                    local idx2 = (i % numPoints) * 2 + 1
                    
                    local lx1, ly1 = points[idx1], points[idx1+1]
                    local lx2, ly2 = points[idx2], points[idx2+1]
                    
                    -- Convert local vertices to world coordinates to find true orientation
                    local wx1, wy1 = body:getWorldPoint(lx1, ly1)
                    local wx2, wy2 = body:getWorldPoint(lx2, ly2)
                    
                    local dx = wx2 - wx1
                    local dy = wy2 - wy1
                    
                    -- World normal (assuming CCW winding)
                    local nx, ny = dy, -dx
                    local len = math.sqrt(nx*nx + ny*ny)
                    if len > 0 then
                        nx, ny = nx/len, ny/len
                    end
                    
                    -- Is this the edge pointing most directly upward?
                    if ny < bestY then
                        bestY = ny
                        bestEdge = {lx1, ly1, lx2, ly2}
                    end
                end
                
                -- Add grass to the topmost edge
                if bestEdge then
                    local lx1, ly1, lx2, ly2 = bestEdge[1], bestEdge[2], bestEdge[3], bestEdge[4]
                    local dx, dy = lx2 - lx1, ly2 - ly1
                    local length = math.sqrt(dx*dx + dy*dy)
                    
                    local step = 9 / densityMulti
                    local lnx, lny = dy, -dx
                    local localAngle = math.atan2(lny, lnx) + math.pi/2
                    
                    for d = 4, length - 4, step do
                        local jitter = (math.random() - 0.5) * (step * 0.8)
                        local jt = (d + jitter) / length
                        jt = math.max(0, math.min(1, jt))
                        
                        local jx = lx1 + dx * jt
                        local jy = ly1 + dy * jt
                        
                        -- Add slight depth variance along the normal
                        local lenNorm = math.sqrt(lnx*lnx + lny*lny)
                        if lenNorm > 0 then
                            local depthJitter = (math.random() - 0.5) * 2.5
                            jx = jx + (lnx/lenNorm) * depthJitter
                            jy = jy + (lny/lenNorm) * depthJitter
                        end
                        
                        Vegetation.createGrass(body, jx, jy, nil, nil, localAngle)
                    end
                end
            end
        elseif shapeType == "circle" then
            local r = shape:getRadius()
            local lcx, lcy = shape:getPoint()
            local step = 9 / densityMulti
            local circumference = 2 * math.pi * r
            
            -- Distribute circularly
            for d = 0, circumference, step do
                local theta = (d / circumference) * 2 * math.pi
                -- Randomize angle slightly
                local jitterTheta = theta + (math.random() - 0.5) * (step / r)
                
                local lx = lcx + r * math.cos(jitterTheta)
                local ly = lcy + r * math.sin(jitterTheta)
                local localAngle = jitterTheta + math.pi/2
                
                Vegetation.createGrass(body, lx, ly, nil, nil, localAngle)
            end
        end
    end
end

-- Update loop simulating ambient environment physics, healing, and real-time synchronization
function Vegetation.update(dt, entitiesList)
    local time = love.timer.getTime()
    local EffectsSystem = package.loaded["effects"]
    local hadGrass = (#Vegetation.list > 0)
    
    for i = #Vegetation.list, 1, -1 do
        local item = Vegetation.list[i]
        
        -- If parent body destroyed or specific grass health reaches 0, specific grass dies
        if not item.body or item.body:isDestroyed() or item.health <= 0 then
            if item.health and item.health <= 0 and EffectsSystem and EffectsSystem.createParticle then
                for p = 1, 3 do
                    local vx = (math.random() - 0.5) * 50
                    local vy = -(math.random() * 40 + 15)
                    EffectsSystem.createParticle(item.x, item.y, vx, vy, 20, 200, 1.5 + math.random(), "grassDebris")
                end
            end
            table.remove(Vegetation.list, i)
        else
            item.x, item.y = item.body:getWorldPoint(item.localX, item.localY)
            
            -- 2. Layered Ambient Wind Processing (Base wave + chaotic gusts)
            local baseWind = math.sin(time * item.windFreq + item.x * 0.015)
            local gustWind = math.sin(time * item.windGustFreq + item.x * 0.04) * 0.4
            local wind = (baseWind + gustWind) * item.windStrength
            
            -- 3. Damped Spring Physics
            local angleDiff = wind - item.angle
            local springForce = angleDiff * item.stiffness
            
            item.angularVelocity = item.angularVelocity + springForce * dt
            item.angularVelocity = item.angularVelocity * math.max(0, 1 - item.damping * dt)
            item.angle = item.angle + item.angularVelocity * dt
            item.angle = math.max(-item.maxBend, math.min(item.maxBend, item.angle))
            
            -- 4. Entity brush interaction mechanics
            if entitiesList then
                for _, e in ipairs(entitiesList) do
                    if e.body and not e.body:isDestroyed() and e.body ~= item.body then
                        local ex, ey = e.body:getPosition()
                        local dx = ex - item.x
                        local dy = ey - item.y
                        local dist = math.sqrt(dx * dx + dy * dy)
                        
                        local entityRadius = e.r or math.max(e.w or 20, e.h or 20) / 2
                        local triggerDistance = entityRadius + 14
                        
                        if dist < triggerDistance then
                            local vx, vy = e.body:getLinearVelocity()
                            local speed = math.sqrt(vx * vx + vy * vy)
                            
                            local pushDir = vx > 0 and 1 or (vx < 0 and -1 or 0)
                            if pushDir == 0 then pushDir = dx > 0 and -1 or 1 end
                            
                            local interactionStrength = 1 - (dist / triggerDistance)
                            local impulse = pushDir * interactionStrength * (speed * 0.08 + 4.5)
                            item.angularVelocity = item.angularVelocity + impulse * dt * 60
                        end
                    end
                end
            end
            
            -- 5. Healing: slowly recover health back to full green over time if still alive
            if item.health < item.maxHealth then
                item.health = math.min(item.maxHealth, item.health + Vegetation.healRate * dt)
            end
        end
    end
    
    -- If all grass dies, the vegetation is destroyed
    if hadGrass and #Vegetation.list == 0 and not Vegetation.destroyed then
        Vegetation.destroyed = true
        print("All vegetation has been destroyed!")
    end
end

-- Process high-impact explosions and trigger damage/color mutations
function Vegetation.applyExplosion(cx, cy, radius, force, damage)
    local EffectsSystem = package.loaded["effects"]
    local hadGrass = (#Vegetation.list > 0)
    local baseDmg = (damage and damage > 0) and damage or ((force or 500) * 0.5)
    
    for i = #Vegetation.list, 1, -1 do
        local item = Vegetation.list[i]
        local dx = item.x - cx
        local dy = (item.y - item.h / 2) - cy
        local dist = math.sqrt(dx * dx + dy * dy)
        
        if dist < radius then
            local pushDir = dx >= 0 and 1 or -1
            local falloff = 1 - (dist / radius)
            local explosionForce = pushDir * falloff * ((force or 1000) * 0.09)
            
            -- Flatten instantly from shockwave energy
            item.angle = item.angle + pushDir * falloff * 2.5
            item.angularVelocity = item.angularVelocity + explosionForce * 5.0
            
            -- Damage the grass based on explosive damage, force, and distance falloff
            local explosionDmg = math.max(25 * falloff, (baseDmg * 0.35 + (force or 100) * 0.15) * falloff)
            item.health = item.health - explosionDmg
            
            -- Dirt/debris kicking up from the roots
            if EffectsSystem and EffectsSystem.createParticle then
                local particleCount = math.floor(falloff * 3) + 1
                for p = 1, particleCount do
                    local px = item.x + (math.random() - 0.5) * 10
                    local py = item.y - math.random() * (item.h * 0.5)
                    local vx = (math.random() - 0.5) * 50 + (pushDir * falloff * 90)
                    local vy = -(math.random() * 50 + 20)
                    EffectsSystem.createParticle(px, py, vx, vy, 35, 120, 1.5 + math.random(2), "debris")
                end
            end
            
            -- If specific grass reaches 0 health, it dies immediately
            if item.health <= 0 then
                if EffectsSystem and EffectsSystem.createParticle then
                    for p = 1, 4 do
                        local px = item.x + (math.random() - 0.5) * 8
                        local py = item.y - math.random() * (item.h * 0.6)
                        local vx = (math.random() - 0.5) * 80 + (pushDir * falloff * 100)
                        local vy = -(math.random() * 60 + 30)
                        EffectsSystem.createParticle(px, py, vx, vy, 25, 180, 2 + math.random(), "grassDebris")
                    end
                end
                table.remove(Vegetation.list, i)
            end
        end
    end
    
    -- Check if all grass died from this explosion
    if hadGrass and #Vegetation.list == 0 and not Vegetation.destroyed then
        Vegetation.destroyed = true
        print("All vegetation has been destroyed by explosion!")
    end
end

-- Monkey-patch helper hooks to securely intercept explosion triggers from standard entities
local Entities = package.loaded["entities"] or require("entities")
if Entities and type(Entities.explode) == "function" then
    local originalExplode = Entities.explode
    Entities.explode = function(e)
        local cx, cy, radius, force, damage
        if e and e.body and not e.body:isDestroyed() then
            cx, cy = e.body:getPosition()
            radius = e.explosionRadius or 100
            force = e.explosionForce or 1000
            damage = e.explosionDamage or 200
        end
        originalExplode(e)
        if cx and cy then
            Vegetation.applyExplosion(cx, cy, radius, force, damage)
        end
    end
end

-- Render highly realistic procedural segmented grass
function Vegetation.draw()
    local segments = 4 -- Keeps performance solid while allowing smooth curving
    
    for _, item in ipairs(Vegetation.list) do
        -- CRITICAL FIX: Skip any grass attached to a destroyed body or with <= 0 health
        if not item.body or item.body:isDestroyed() or (item.health and item.health <= 0) then
            goto continue
        end
        
        love.graphics.push()
        love.graphics.translate(item.x, item.y)
        
        -- Orient matrix based on the parent body angle structure
        local bodyAngle = item.body:getAngle()
        love.graphics.rotate(bodyAngle + item.localAngle)
        
        -- Health decay: 100% health = Healthy Green (decay=0), 0% health = Decayed Yellow (decay=1)
        local healthRatio = math.max(0, math.min(1, item.health / item.maxHealth))
        local decay = 1 - healthRatio
        
        -- Base color smoothly transitions from green to yellow as health decays
        local bR = item.healthyColor[1] * (1 - decay) + item.deadColor[1] * decay
        local bG = item.healthyColor[2] * (1 - decay) + item.deadColor[2] * decay
        local bB = item.healthyColor[3] * (1 - decay) + item.deadColor[3] * decay
        
        -- Decayed yellow grass wilts and droops slightly
        local wilt = decay * 0.28
        
        -- Draw each procedural blade in the tuft
        for _, blade in ipairs(item.blades) do
            love.graphics.push()
            
            -- Apply blade-specific angle spread
            love.graphics.rotate(blade.angleOffset)
            
            local bladeHeight = item.h * blade.heightMod
            local bladeWidth = item.w * blade.widthMod
            local segH = bladeHeight / segments
            
            for s = 1, segments do
                -- Root-to-Tip Gradient: 
                -- Roots (s=1) are shadowed.
                -- Tips (s=segments) are slightly brighter.
                local heightRatio = s / segments
                local depthShadow = 0.45 + (0.55 * heightRatio)
                
                -- Add a slight yellow-drying tint to the tips when decaying
                local tipYellow = (heightRatio > 0.6) and (0.15 * decay * heightRatio) or 0
                
                local fR = math.min(1, bR * depthShadow * blade.colorMod + tipYellow)
                local fG = math.min(1, bG * depthShadow * blade.colorMod + tipYellow * 0.8)
                local fB = math.min(1, bB * depthShadow * blade.colorMod)
                
                love.graphics.setColor(fR, fG, fB)
                
                -- Calculate tapering width
                local currentW = bladeWidth * ((segments - s + 1) / segments)
                local nextW = bladeWidth * ((segments - s) / segments)
                
                -- Distribute physical bending + natural static curve + wilt along segments
                love.graphics.rotate((item.angle / segments) + ((blade.curve + wilt) / segments))
                
                -- Draw the segment polygon
                love.graphics.polygon("fill", 
                    -currentW / 2, 0, 
                    currentW / 2, 0, 
                    nextW / 2, -segH, 
                    -nextW / 2, -segH
                )
                
                -- Translate up to the end of this segment for the next loop iteration
                love.graphics.translate(0, -segH)
            end
            
            love.graphics.pop()
        end
        
        love.graphics.pop()
        ::continue::
    end
    -- Reset color to prevent tinting other game assets
    love.graphics.setColor(1, 1, 1, 1)
end

return Vegetation