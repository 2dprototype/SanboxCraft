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
-- @param flower: If true, adds a slightly tall plant containing a pink cherry flower inside the vegetation
function Vegetation.createGrass(body, localX, localY, w, h, localAngle, flower)
    if not body or body:isDestroyed() then return nil end

    -- Generate a realistic organic blend for Healthy Grass (Deep Forest to Olive Green)
    local hR = 0.12 + math.random() * 0.10
    local hG = 0.28 + math.random() * 0.18
    local hB = 0.10 + math.random() * 0.08
    
    -- Generate a realistic organic blend for Dead/Burnt Grass (Dark Ochre/Mustard/Brown)
    local dR = 0.42 + math.random() * 0.15
    local dG = 0.35 + math.random() * 0.12
    local dB = 0.12 + math.random() * 0.06
    
    local maxHp = 100
    local hasFlower = (flower == true) or (type(flower) == "number" and math.random() < flower)

    local grass = {
        type = "grass",
        body = body,
        localX = localX or 0,
        localY = localY or 0,
        localAngle = localAngle or 0,
        hasFlower = hasFlower,
        
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
    
    -- When flower is true: inside each vegetation tuft, add a slightly tall plant that contains a pink cherry flower
    if grass.hasFlower then
        grass.flowerPlant = {
            -- High stability & elasticity physics properties (resists bending, snaps back firmly)
            angle = 0,
            angularVelocity = 0,
            stiffness = 50 + math.random() * 15,          -- Significantly higher elasticity/stiffness than grass (grass is 0-12)
            damping = 9.0 + math.random() * 2.0,          -- High damping for quick recovery and steady posture
            maxBend = math.pi / 12,                       -- Tight bend limit (~15 deg, shouldn't bend much)
            windStrength = 0.005 + math.random() * 0.004, -- Subtle gentle breeze sway
            
            -- Slightly tall plant rising gracefully above the grass tuft
            heightMod = 1.45 + math.random() * 0.25,
            widthMod = 0.76 + math.random() * 0.14,
            angleOffset = (math.random() - 0.5) * 0.08,   -- Stays mostly upright
            curve = (math.random() - 0.5) * 0.06,         -- Very subtle natural curve
            petalAngle = math.random() * math.pi * 2,
            petalScale = 0.42 + math.random() * 0.24,
            -- Leaf shoots along the lower-to-mid stem
            leaves = {
                { t = 0.36 + math.random() * 0.08, side = -1, size = 3.6 + math.random() * 1.4, angle = -0.42 - math.random() * 0.2 },
                { t = 0.58 + math.random() * 0.08, side = 1, size = 3.4 + math.random() * 1.4, angle = 0.42 + math.random() * 0.2 }
            }
        }
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
-- @param flower: If true, the vegetation will contain only one flower plant
function Vegetation.populateBody(body, densityMulti, flower)
    if not body or body:isDestroyed() then return end
    densityMulti = densityMulti or 1.0
    
    local fixtures = body:getFixtures()
    if not fixtures or #fixtures == 0 then return end
    
    local candidates = {}
    
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
                        
                        table.insert(candidates, { x = jx, y = jy, angle = localAngle })
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
                
                table.insert(candidates, { x = lx, y = ly, angle = localAngle })
            end
        end
    end
    
    if #candidates == 0 then return end
    
    -- Ensure each vegetation contains only ONE flower plant when flower is true
    local flowerIdx = nil
    if flower == true then
        -- Place the single flower plant naturally near the center of the vegetation
        local center = math.floor(#candidates / 2) + 1
        local offset = (#candidates > 3) and math.random(-1, 1) or 0
        flowerIdx = math.max(1, math.min(#candidates, center + offset))
    end
    
    for idx, c in ipairs(candidates) do
        local hasFlower = (flower == "all") or (flower == true and idx == flowerIdx) or (type(flower) == "number" and math.random() < flower)
        Vegetation.createGrass(body, c.x, c.y, nil, nil, c.angle, hasFlower)
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
                if item.hasFlower then
                    for p = 1, 4 do
                        local vx = (math.random() - 0.5) * 60
                        local vy = -(math.random() * 45 + 15)
                        EffectsSystem.createParticle(item.x, item.y - item.h * 1.1, vx, vy, 35, 120, 2.5 + math.random() * 1.2, "cherryPetal")
                    end
                end
            end
            table.remove(Vegetation.list, i)
        else
            item.x, item.y = item.body:getWorldPoint(item.localX, item.localY)
            
            -- 2. Layered Ambient Wind Processing (Base wave + chaotic gusts)
            local baseWind = math.sin(time * item.windFreq + item.x * 0.015)
            local gustWind = math.sin(time * item.windGustFreq + item.x * 0.04) * 0.4
            local wind = (baseWind + gustWind) * item.windStrength
            
            -- 3. Damped Spring Physics for grass blades
            local angleDiff = wind - item.angle
            local springForce = angleDiff * item.stiffness
            
            item.angularVelocity = item.angularVelocity + springForce * dt
            item.angularVelocity = item.angularVelocity * math.max(0, 1 - item.damping * dt)
            item.angle = item.angle + item.angularVelocity * dt
            item.angle = math.max(-item.maxBend, math.min(item.maxBend, item.angle))
            
            -- 3b. Dedicated high stability & elasticity physics for flower plant (stays sturdy, resists bending)
            if item.hasFlower and item.flowerPlant then
                local plant = item.flowerPlant
                local pWind = baseWind * plant.windStrength
                local pAngleDiff = pWind - plant.angle
                local pSpringForce = pAngleDiff * plant.stiffness
                
                plant.angularVelocity = plant.angularVelocity + pSpringForce * dt
                plant.angularVelocity = plant.angularVelocity * math.max(0, 1 - plant.damping * dt)
                plant.angle = plant.angle + plant.angularVelocity * dt
                plant.angle = math.max(-plant.maxBend, math.min(plant.maxBend, plant.angle))
            end

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
                            
                            -- Flower plant has high stability & elasticity: only deflected slightly and springs back
                            if item.hasFlower and item.flowerPlant then
                                item.flowerPlant.angularVelocity = item.flowerPlant.angularVelocity + impulse * dt * 10
                            end
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
            
            -- Flower plant has high stability & elasticity: resists violent bending and recovers rapidly
            if item.hasFlower and item.flowerPlant then
                local pBend = pushDir * falloff * 0.35
                item.flowerPlant.angle = math.max(-item.flowerPlant.maxBend, math.min(item.flowerPlant.maxBend, item.flowerPlant.angle + pBend))
                item.flowerPlant.angularVelocity = item.flowerPlant.angularVelocity + explosionForce * 0.8
            end
            
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
                    if item.hasFlower then
                        for p = 1, 6 do
                            local px = item.x + (math.random() - 0.5) * 10
                            local py = item.y - item.h * 1.2 + (math.random() - 0.5) * 6
                            local vx = (math.random() - 0.5) * 90 + (pushDir * falloff * 120)
                            local vy = -(math.random() * 70 + 30)
                            EffectsSystem.createParticle(px, py, vx, vy, 40, 100, 2.5 + math.random() * 1.5, "cherryPetal")
                        end
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

-- Render a detailed, authentic pink cherry flower (sakura blossom) at the current graphics transform
function Vegetation.drawCherryFlower(item, plant, decay, wilt)
    local scale = plant.petalScale or 1.0
    local baseR = (item.w * 1.45 + 5.0) * scale -- Blossom radius
    
    -- 1. Green Sepals / Calyx connecting stem to petals
    local sepR = 0.14 * (1 - decay) + 0.35 * decay
    local sepG = 0.30 * (1 - decay) + 0.28 * decay
    local sepB = 0.10 * (1 - decay) + 0.10 * decay
    love.graphics.setColor(sepR, sepG, sepB)
    for se = 1, 3 do
        local a = (se - 1) * (math.pi * 2 / 3) + math.pi / 2
        local sx = math.cos(a) * (baseR * 0.35)
        local sy = math.sin(a) * (baseR * 0.35) + 1.2
        love.graphics.polygon("fill", 0, 1.5, sx - 1.2, sy, sx + 1.2, sy)
    end

    -- 2. Organic Blossom Pink Colors (Vibrant healthy cherry blossom pink to withered dried-rose)
    -- Main petal body pink
    local pR = 1.00 * (1 - decay) + 0.68 * decay
    local pG = 0.68 * (1 - decay) + 0.48 * decay
    local pB = 0.80 * (1 - decay) + 0.42 * decay

    -- Outer tip highlight (soft pastel blossom blush)
    local tipR = 1.00 * (1 - decay) + 0.72 * decay
    local tipG = 0.84 * (1 - decay) + 0.56 * decay
    local tipB = 0.90 * (1 - decay) + 0.50 * decay

    -- Inner throat (deep magenta / rose pink center core)
    local inR = 0.92 * (1 - decay) + 0.55 * decay
    local inG = 0.30 * (1 - decay) + 0.28 * decay
    local inB = 0.55 * (1 - decay) + 0.26 * decay

    local petalLen = baseR * 1.05
    local petalWidth = baseR * 0.62

    -- 3. Draw 5 Cherry Blossom Petals radially with iconic notched tip
    for p = 1, 5 do
        local angle = (p - 1) * (math.pi * 2 / 5) + plant.petalAngle
        local dirX = math.cos(angle)
        local dirY = math.sin(angle)
        local perpX = -dirY
        local perpY = dirX

        -- Base of petal
        local bX, bY = 0, 0
        -- Mid-sides (widest part of the petal)
        local mlX = dirX * (petalLen * 0.52) - perpX * (petalWidth * 0.50)
        local mlY = dirY * (petalLen * 0.52) - perpY * (petalWidth * 0.50)
        local mrX = dirX * (petalLen * 0.52) + perpX * (petalWidth * 0.50)
        local mrY = dirY * (petalLen * 0.52) + perpY * (petalWidth * 0.50)
        -- Left lobe tip
        local tlX = dirX * petalLen - perpX * (petalWidth * 0.28)
        local tlY = dirY * petalLen - perpY * (petalWidth * 0.28)
        -- Notch indentation (the cherry blossom cleft)
        local notchX = dirX * (petalLen * 0.86)
        local notchY = dirY * (petalLen * 0.86)
        -- Right lobe tip
        local trX = dirX * petalLen + perpX * (petalWidth * 0.28)
        local trY = dirY * petalLen + perpY * (petalWidth * 0.28)

        -- Outer Petal Body
        love.graphics.setColor(pR, pG, pB, 0.96)
        love.graphics.polygon("fill", bX, bY, mlX, mlY, tlX, tlY, notchX, notchY, trX, trY, mrX, mrY)

        -- Tip highlight for soft translucent cherry blossom appearance
        love.graphics.setColor(tipR, tipG, tipB, 0.70)
        love.graphics.polygon("fill",
            notchX, notchY,
            tlX, tlY,
            dirX * (petalLen * 0.72) - perpX * (petalWidth * 0.25), dirY * (petalLen * 0.72) - perpY * (petalWidth * 0.25),
            dirX * (petalLen * 0.72) + perpX * (petalWidth * 0.25), dirY * (petalLen * 0.72) + perpY * (petalWidth * 0.25),
            trX, trY
        )

        -- Inner base petal glow (rich magenta gradient radiating from throat)
        love.graphics.setColor(inR, inG, inB, 0.65)
        love.graphics.polygon("fill",
            bX, bY,
            dirX * (petalLen * 0.36) - perpX * (petalWidth * 0.26), dirY * (petalLen * 0.36) - perpY * (petalWidth * 0.26),
            dirX * (petalLen * 0.46), dirY * (petalLen * 0.46),
            dirX * (petalLen * 0.36) + perpX * (petalWidth * 0.26), dirY * (petalLen * 0.36) + perpY * (petalWidth * 0.26)
        )
    end

    -- 4. Deep Cherry Center Throat Ring
    love.graphics.setColor(inR, inG, inB, 0.88)
    love.graphics.circle("fill", 0, 0, baseR * 0.28)

    -- 5. Radiating Stamens & Golden-Yellow Pollen Anthers
    local numStamens = 7
    for s = 1, numStamens do
        local sa = (s - 1) * (math.pi * 2 / numStamens) + plant.petalAngle + 0.25
        local sDist = baseR * 0.42
        local ax = math.cos(sa) * sDist
        local ay = math.sin(sa) * sDist

        -- Stamen filament line
        love.graphics.setColor(inR * 1.1, inG * 1.2, inB * 1.1, 0.75)
        love.graphics.setLineWidth(1)
        love.graphics.line(0, 0, ax, ay)

        -- Golden-yellow pollen dot at the tip
        local yR = 1.00 * (1 - decay) + 0.70 * decay
        local yG = 0.90 * (1 - decay) + 0.60 * decay
        local yB = 0.28 * (1 - decay) + 0.30 * decay
        love.graphics.setColor(yR, yG, yB, 0.95)
        love.graphics.circle("fill", ax, ay, 0.85 * scale)
    end

    -- 6. Core Center Pistil
    local cR = 1.00 * (1 - decay) + 0.75 * decay
    local cG = 0.96 * (1 - decay) + 0.68 * decay
    local cB = 0.45 * (1 - decay) + 0.35 * decay
    love.graphics.setColor(cR, cG, cB, 0.95)
    love.graphics.circle("fill", 0, 0, 1.2 * scale)
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
                local depthShadow = 0.4 + (0.6 * heightRatio)
                
                -- Add a slight yellow tint to the very tips of the grass for realism
                local tipYellow = (heightRatio > 0.7) and (0.1 * heightRatio) or 0
                
                local fR = math.min(1, bR * depthShadow * blade.colorMod + tipYellow)
                local fG = math.min(1, bG * depthShadow * blade.colorMod + tipYellow)
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
        
        -- If flower parameter is true: inside each vegetation tuft, draw the slightly tall plant containing the pink cherry flower
        if item.hasFlower and item.flowerPlant then
            local plant = item.flowerPlant
            love.graphics.push()
            
            -- Apply subtle angle offset for the plant stem
            love.graphics.rotate(plant.angleOffset)
            
            local plantHeight = item.h * plant.heightMod
            local plantWidth = item.w * plant.widthMod
            local pSegs = 5
            local segH = plantHeight / pSegs
            
            -- Fresh botanical stem green, transitioning with decay
            local sR = (item.healthyColor[1] * 0.85) * (1 - decay) + item.deadColor[1] * decay
            local sG = (math.min(1, item.healthyColor[2] * 1.15)) * (1 - decay) + item.deadColor[2] * decay
            local sB = (item.healthyColor[3] * 0.80) * (1 - decay) + item.deadColor[3] * decay
            
            -- High stability & elasticity: flower plant bends subtly with plant.angle and resists severe wilting
            local pAngle = plant.angle or (item.angle * 0.15)
            local pWilt = wilt * 0.20
            
            for s = 1, pSegs do
                local hRatio = s / pSegs
                local shadow = 0.5 + (0.5 * hRatio)
                love.graphics.setColor(sR * shadow, sG * shadow, sB * shadow)
                
                local currentW = plantWidth * ((pSegs - s + 1.2) / pSegs)
                local nextW = plantWidth * ((pSegs - s + 0.2) / pSegs)
                
                -- High stability & elasticity: gentle bending along stem segments
                love.graphics.rotate((pAngle / pSegs) + ((plant.curve + pWilt) / pSegs))
                
                -- Draw stem segment
                love.graphics.polygon("fill",
                    -currentW / 2, 0,
                    currentW / 2, 0,
                    nextW / 2, -segH,
                    -nextW / 2, -segH
                )
                
                -- Side leaf shoots along mid-stem
                if plant.leaves then
                    for _, leaf in ipairs(plant.leaves) do
                        if (leaf.t >= (s - 1) / pSegs) and (leaf.t < s / pSegs) then
                            love.graphics.push()
                            love.graphics.translate(leaf.side * (currentW * 0.45), -segH * 0.5)
                            love.graphics.rotate(leaf.angle + (pAngle * 0.4))
                            
                            local lR = sR * 1.05
                            local lG = sG * 1.10
                            local lB = sB * 0.90
                            love.graphics.setColor(lR, lG, lB, 0.95)
                            
                            love.graphics.polygon("fill",
                                0, 0,
                                leaf.side * leaf.size * 0.6, -leaf.size * 0.45,
                                leaf.side * leaf.size, -leaf.size * 0.1,
                                leaf.side * leaf.size * 0.5, leaf.size * 0.25
                            )
                            love.graphics.pop()
                        end
                    end
                end
                
                love.graphics.translate(0, -segH)
            end
            
            -- Render the pink cherry flower at the tip of the tall plant!
            Vegetation.drawCherryFlower(item, plant, decay, wilt)
            
            love.graphics.pop()
        end
        
        love.graphics.pop()
        ::continue::
    end
    -- Reset color and line width to prevent tinting other game assets
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

return Vegetation