-- fire.lua
-- Realistic Particle Fire System attached to physics bodies (like grass)
local Water = require("water")
local EffectsSystem = require("effects")
local Entities = require("entities")
local Whale = require("whale")
local WorldManager = require("world_manager")

local Fire = {
    list = {},
    particles = {},
    nextId = 1,
    particleTexture = nil
}

-- Initialize the Fire system and create the soft radial glow particle texture
function Fire.init()
    Fire.list = {}
    Fire.particles = {}
    Fire.nextId = 1

    if not Fire.particleTexture and love.graphics then
        local size = 32
        local half = size / 2
        local imgData = love.image.newImageData(size, size)
        for y = 0, size - 1 do
            for x = 0, size - 1 do
                local dx = (x + 0.5) - half
                local dy = (y + 0.5) - half
                local dist = math.sqrt(dx * dx + dy * dy) / half
                if dist <= 1.0 then
                    -- Soft cosine falloff for organic particle blending
                    local alpha = (math.cos(dist * math.pi) * 0.5 + 0.5) ^ 1.6
                    imgData:setPixel(x, y, 1, 1, 1, alpha)
                else
                    imgData:setPixel(x, y, 1, 1, 1, 0)
                end
            end
        end
        Fire.particleTexture = love.graphics.newImage(imgData)
        Fire.particleTexture:setFilter("linear", "linear")
    end
end

-- Generate local surface attachment points on a Box2D body (like how grass works)
function Fire.generateEmitters(body, target, hitWorldX, hitWorldY)
    local emitters = {}
    if not body or body:isDestroyed() then
        table.insert(emitters, { localX = 0, localY = 0 })
        return emitters
    end

    local lx, ly = body:getLocalPoint(hitWorldX, hitWorldY)
    local fixtures = body:getFixtures()

    if fixtures and #fixtures > 0 then
        for _, fixture in ipairs(fixtures) do
            local shape = fixture:getShape()
            local shapeType = shape:getType()

            if shapeType == "polygon" then
                local points = { shape:getPoints() }
                local numPoints = #points / 2
                -- Check if this is a large boundary (e.g. wall/floor)
                local isLargeBoundary = false
                if target and target.w and (target.w > 120 or (target.h and target.h > 120)) then
                    isLargeBoundary = true
                end

                if isLargeBoundary then
                    -- Localize fire around the hit point on the boundary
                    for offset = -35, 35, 12 do
                        table.insert(emitters, {
                            localX = lx + offset,
                            localY = ly + (love.math.random() - 0.5) * 4
                        })
                    end
                else
                    -- Distribute emitters around the polygon edges of the object
                    for i = 1, numPoints do
                        local idx1 = (i - 1) * 2 + 1
                        local idx2 = (i % numPoints) * 2 + 1
                        local x1, y1 = points[idx1], points[idx1 + 1]
                        local x2, y2 = points[idx2], points[idx2 + 1]
                        local edgeLen = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
                        local step = math.max(8, edgeLen / 3)
                        for d = 0, edgeLen, step do
                            local t = d / edgeLen
                            table.insert(emitters, {
                                localX = x1 + (x2 - x1) * t + (love.math.random() - 0.5) * 2,
                                localY = y1 + (y2 - y1) * t + (love.math.random() - 0.5) * 2
                            })
                        end
                    end
                end

            elseif shapeType == "circle" then
                local r = shape:getRadius()
                local cx, cy = shape:getPoint()
                -- Distribute emitters around circumference
                local count = math.max(6, math.floor(r * 0.5))
                for i = 1, count do
                    local theta = (i / count) * math.pi * 2
                    table.insert(emitters, {
                        localX = cx + (r * 0.9) * math.cos(theta),
                        localY = cy + (r * 0.9) * math.sin(theta)
                    })
                end
            end
        end
    end

    if #emitters == 0 then
        table.insert(emitters, { localX = lx, localY = ly })
    end

    return emitters
end

-- Create a fire object attached to a target / body
function Fire.create(target, worldX, worldY, initialIntensity)
    local intensity = initialIntensity or 1.0
    local body = (target and target.body) or nil
    local emitters = Fire.generateEmitters(body, target, worldX, worldY)

    local maxLife = 8.0 + intensity * 3.5
    local fireObj = {
        id = Fire.nextId,
        target = target,
        body = body,
        emitters = emitters,
        hitWorldX = worldX,
        hitWorldY = worldY,
        intensity = intensity,
        maxIntensity = 5.0,
        life = maxLife,
        maxLife = maxLife,
        radius = 20 + intensity * 8,
        damagePerSec = 25 * intensity,
        inWater = false,
        spawnTimer = 0
    }
    Fire.nextId = Fire.nextId + 1

    -- Spawn initial burst of realistic fire ignition particles
    Fire.spawnBurst(worldX, worldY, 12, intensity)

    table.insert(Fire.list, fireObj)
    return fireObj
end

-- Intensify an existing fire
function Fire.intensify(fireObj, amount)
    amount = amount or 1.0
    fireObj.intensity = math.min(fireObj.maxIntensity, fireObj.intensity + amount)
    fireObj.maxLife = 8.0 + fireObj.intensity * 3.5
    fireObj.life = math.min(35.0, fireObj.life + 6.0 + amount * 3.0)
    fireObj.radius = 20 + fireObj.intensity * 8
    fireObj.damagePerSec = 25 * fireObj.intensity

    -- Add additional emitters if attached to a body
    if fireObj.body and not fireObj.body:isDestroyed() and #fireObj.emitters < 24 then
        local bx, by = fireObj.body:getPosition()
        local extraEmitters = Fire.generateEmitters(fireObj.body, fireObj.target, bx, by)
        for _, em in ipairs(extraEmitters) do
            if #fireObj.emitters < 24 then
                table.insert(fireObj.emitters, em)
            end
        end
    end

    -- Burst of bright ignition particles
    local wx, wy = fireObj.hitWorldX, fireObj.hitWorldY
    if fireObj.body and not fireObj.body:isDestroyed() then
        wx, wy = fireObj.body:getPosition()
    end
    Fire.spawnBurst(wx, wy, 16, fireObj.intensity)
end

-- Spawn a realistic radial burst of fire particles
function Fire.spawnBurst(cx, cy, count, intensity)
    for i = 1, count do
        local angle = love.math.random() * math.pi * 2
        local speed = love.math.random(25, 75 * (0.8 + intensity * 0.25))
        local vx = math.cos(angle) * speed
        local vy = math.sin(angle) * speed - love.math.random(30, 80)
        local life = 0.35 + love.math.random() * 0.3
        local size = 10 + love.math.random() * 8 * intensity
        table.insert(Fire.particles, {
            x = cx + (love.math.random() - 0.5) * 12,
            y = cy + (love.math.random() - 0.5) * 12,
            vx = vx, vy = vy,
            life = life, maxLife = life,
            size = size,
            startSize = size * 0.7,
            endSize = size * 1.3,
            rot = love.math.random() * math.pi * 2,
            vRot = (love.math.random() - 0.5) * 6,
            pType = "flame"
        })
    end
    -- Add embers
    for i = 1, math.floor(count * 0.6) do
        local angle = love.math.random() * math.pi * 2
        local speed = love.math.random(40, 110)
        table.insert(Fire.particles, {
            x = cx, y = cy,
            vx = math.cos(angle) * speed,
            vy = math.sin(angle) * speed - love.math.random(50, 120),
            life = 0.5 + love.math.random() * 0.4,
            maxLife = 0.9,
            size = 2 + love.math.random() * 2,
            pType = "ember"
        })
    end
end

-- Check if a fire is already attached to an object or near a location
function Fire.findTargetFire(target, worldX, worldY, radius)
    radius = radius or 35
    for _, f in ipairs(Fire.list) do
        if target and f.target and f.target == target then
            return f
        end
        if target and target.body and f.body and f.body == target.body then
            return f
        end
        local dx = f.hitWorldX - worldX
        local dy = f.hitWorldY - worldY
        if math.sqrt(dx * dx + dy * dy) <= (f.radius or radius) then
            return f
        end
    end
    return nil
end

-- Player ignites target under mouse cursor
function Fire.igniteAt(worldX, worldY, player, entitiesList, vegetationList)
    -- 1. Identify target object under cursor
    local target = nil

    -- Check entities
    if entitiesList then
        local minDist = 45
        for _, e in ipairs(entitiesList) do
            if e.body and not e.body:isDestroyed() and e ~= player then
                local ex, ey = e.body:getPosition()
                local dist = math.sqrt((worldX - ex) ^ 2 + (worldY - ey) ^ 2)
                local threshold = (e.r or math.max(e.w or 20, e.h or 20) / 2) + 15
                if dist < threshold and dist < minDist then
                    minDist = dist
                    target = e
                end
            end
        end
    end

    -- Check whales
    if not target then
        local whales = Whale.getAll()
        for _, w in ipairs(whales) do
            if w.body and not w.body:isDestroyed() then
                local wx, wy = w.body:getPosition()
                local dist = math.sqrt((worldX - wx) ^ 2 + (worldY - wy) ^ 2)
                if dist < (w.data.w / 2 + 20) then
                    target = w
                    break
                end
            end
        end
    end

    -- Check grass
    if not target and vegetationList then
        for _, v in ipairs(vegetationList) do
            local dist = math.sqrt((worldX - v.x) ^ 2 + (worldY - v.y) ^ 2)
            if dist < 22 then
                target = v
                break
            end
        end
    end

    -- Check static map boundaries
    if not target and WorldManager and WorldManager.boundaries then
        for _, b in ipairs(WorldManager.boundaries) do
            if b.body and not b.body:isDestroyed() then
                local bx, by = b.body:getPosition()
                local dist = math.sqrt((worldX - bx) ^ 2 + (worldY - by) ^ 2)
                local threshold = math.max(b.w or 20, b.h or 20) / 2 + 20
                if dist < threshold then
                    target = b
                    break
                end
            end
        end
    end

    -- 2. If target or location already has fire, INTENSIFY IT
    local existing = Fire.findTargetFire(target, worldX, worldY, 40)
    if existing then
        Fire.intensify(existing, 1.0)
        Fire.castPlayerFlame(player, worldX, worldY)
        return existing
    end

    -- 3. Otherwise, create new fire attached to object (or world location)
    local f = Fire.create(target, worldX, worldY, 1.0)
    Fire.castPlayerFlame(player, worldX, worldY)
    return f
end

-- Shoot realistic flame particles from player to target position
function Fire.castPlayerFlame(player, tx, ty)
    if not player or not player.body or player.body:isDestroyed() then return end
    local px, py = player.body:getPosition()
    local dx = tx - px
    local dy = ty - py
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist <= 0 then return end
    local nx = dx / dist
    local ny = dy / dist

    local count = math.min(14, math.floor(dist / 22) + 5)
    for i = 1, count do
        local progress = (i / count)
        local spread = (1 - progress) * 10
        local fx = px + nx * (dist * progress) + (love.math.random() - 0.5) * spread
        local fy = py + ny * (dist * progress) + (love.math.random() - 0.5) * spread
        local speed = love.math.random(80, 220)
        local life = 0.25 + love.math.random() * 0.25
        local size = 12 + love.math.random() * 10
        table.insert(Fire.particles, {
            x = fx, y = fy,
            vx = nx * speed + (love.math.random() - 0.5) * 30,
            vy = ny * speed + (love.math.random() - 0.5) * 30,
            life = life, maxLife = life,
            size = size, startSize = size * 0.8, endSize = size * 1.3,
            rot = love.math.random() * math.pi * 2,
            vRot = (love.math.random() - 0.5) * 6,
            pType = "flame"
        })
    end
end

-- Update all fire objects, emitters, and particles
function Fire.update(dt, entitiesList, vegetationList)
    local time = love.timer.getTime()

    -- 1. Update Fire Objects
    for i = #Fire.list, 1, -1 do
        local f = Fire.list[i]

        -- Check body validity
        local bodyAlive = f.body and not f.body:isDestroyed()

        -- Update representative world coordinate
        if bodyAlive then
            f.hitWorldX, f.hitWorldY = f.body:getWorldPoint(0, 0)
        end

        -- Water check: does any emitter enter water?
        local anyInWater = false
        local waterArea = Water.isPointInWater(f.hitWorldX, f.hitWorldY)
        if waterArea then anyInWater = true end

        -- Emitter checks & particle emission
        local spawnInterval = math.max(0.015, 0.06 - (f.intensity * 0.008))
        f.spawnTimer = f.spawnTimer + dt

        local shouldSpawn = false
        if f.spawnTimer >= spawnInterval then
            f.spawnTimer = 0
            shouldSpawn = true
        end

        for _, em in ipairs(f.emitters) do
            local wx, wy = f.hitWorldX, f.hitWorldY
            local bvx, bvy = 0, 0

            if bodyAlive then
                wx, wy = f.body:getWorldPoint(em.localX, em.localY)
                bvx, bvy = f.body:getLinearVelocityFromWorldPoint(wx, wy)
            else
                wx = em.localX + f.hitWorldX
                wy = em.localY + f.hitWorldY
            end

            local emWater = Water.isPointInWater(wx, wy)
            if emWater then
                anyInWater = true
                -- Rapidly sizzle out in water
                if shouldSpawn and love.math.random() < 0.75 then
                    local life = 0.4 + love.math.random() * 0.4
                    table.insert(Fire.particles, {
                        x = wx + (love.math.random() - 0.5) * 10,
                        y = wy + (love.math.random() - 0.5) * 6,
                        vx = (love.math.random() - 0.5) * 30 + bvx * 0.2,
                        vy = -love.math.random(35, 80) + bvy * 0.2,
                        life = life, maxLife = life,
                        size = 14 + love.math.random() * 8,
                        startSize = 8, endSize = 22,
                        rot = love.math.random() * math.pi * 2,
                        vRot = (love.math.random() - 0.5) * 2,
                        pType = "steam"
                    })
                end
            else
                -- Not in water: spawn realistic flame particles
                if shouldSpawn then
                    local baseSize = (14 + f.intensity * 6) * (0.8 + love.math.random() * 0.4)
                    local life = 0.35 + love.math.random() * 0.3
                    local upDraft = -love.math.random(60, 160) * (0.8 + f.intensity * 0.2)
                    local turbX = (love.math.random() - 0.5) * (30 + f.intensity * 10)

                    table.insert(Fire.particles, {
                        x = wx + (love.math.random() - 0.5) * 6,
                        y = wy + (love.math.random() - 0.5) * 6,
                        vx = bvx * 0.35 + turbX,
                        vy = bvy * 0.35 + upDraft,
                        life = life, maxLife = life,
                        size = baseSize,
                        startSize = baseSize * 0.6,
                        endSize = baseSize * 1.4,
                        rot = love.math.random() * math.pi * 2,
                        vRot = (love.math.random() - 0.5) * 5,
                        pType = "flame"
                    })

                    -- Occasional flying embers
                    if love.math.random() < (0.25 + f.intensity * 0.1) then
                        local emberLife = 0.45 + love.math.random() * 0.4
                        table.insert(Fire.particles, {
                            x = wx, y = wy,
                            vx = bvx * 0.4 + (love.math.random() - 0.5) * 60,
                            vy = bvy * 0.4 - love.math.random(90, 220),
                            life = emberLife, maxLife = emberLife,
                            size = 1.8 + love.math.random() * 1.6,
                            pType = "ember"
                        })
                    end

                    -- Smoke puffs drifting up above the flames
                    if love.math.random() < 0.12 then
                        local smokeLife = 0.7 + love.math.random() * 0.5
                        local smokeSize = 16 + f.intensity * 6
                        table.insert(Fire.particles, {
                            x = wx + (love.math.random() - 0.5) * 12,
                            y = wy - baseSize * 0.8,
                            vx = bvx * 0.2 + (love.math.random() - 0.5) * 20,
                            vy = -love.math.random(25, 60),
                            life = smokeLife, maxLife = smokeLife,
                            size = smokeSize,
                            startSize = smokeSize * 0.5,
                            endSize = smokeSize * 1.8,
                            rot = love.math.random() * math.pi * 2,
                            vRot = (love.math.random() - 0.5) * 2,
                            pType = "smoke"
                        })
                    end
                end
            end
        end

        f.inWater = anyInWater

        -- Decay Life & Intensity
        if f.inWater then
            -- FIRE DECAYS EXTREMELY QUICK IN WATER (10x faster)
            f.life = f.life - dt * 10.0
            f.intensity = f.intensity - dt * 5.0
        else
            -- Normal decay in open air
            f.life = f.life - dt
        end

        -- Check fire expiration
        if f.life <= 0 or f.intensity <= 0 then
            -- Extinguish smoke puff
            for p = 1, 4 do
                table.insert(Fire.particles, {
                    x = f.hitWorldX + (love.math.random() - 0.5) * 12,
                    y = f.hitWorldY - love.math.random(5, 15),
                    vx = (love.math.random() - 0.5) * 25,
                    vy = -love.math.random(20, 50),
                    life = 0.6, maxLife = 0.6,
                    size = 18, startSize = 8, endSize = 25,
                    rot = love.math.random() * math.pi * 2,
                    vRot = (love.math.random() - 0.5) * 2,
                    pType = "smoke"
                })
            end
            table.remove(Fire.list, i)
        else
            -- 2. Environmental & Damage interactions (only when not submerged)
            if not f.inWater then
                -- A. Destroy Grass: Grass within radius takes heavy burn damage
                if vegetationList then
                    local grassBurnDmg = (45 + f.intensity * 35) * dt
                    for gIdx = #vegetationList, 1, -1 do
                        local grass = vegetationList[gIdx]
                        local gdx = f.hitWorldX - grass.x
                        local gdy = f.hitWorldY - grass.y
                        local dist = math.sqrt(gdx * gdx + gdy * gdy)
                        if dist < (f.radius + 12) then
                            grass.health = grass.health - grassBurnDmg
                            -- If grass dies from fire
                            if grass.health <= 0 then
                                for p = 1, 3 do
                                    EffectsSystem.createParticle(
                                        grass.x, grass.y,
                                        (love.math.random() - 0.5) * 60,
                                        -love.math.random(20, 60),
                                        20, 180, 1.8, "grassDebris"
                                    )
                                    table.insert(Fire.particles, {
                                        x = grass.x, y = grass.y,
                                        vx = (love.math.random() - 0.5) * 40,
                                        vy = -love.math.random(40, 120),
                                        life = 0.5, maxLife = 0.5,
                                        size = 2.5, pType = "ember"
                                    })
                                end
                                table.remove(vegetationList, gIdx)
                            end
                        end
                    end
                end

                -- B. Damage Attached Object / Light Explosive Fuses
                if f.target and f.target.type then
                    if f.target.type == "grenade" or f.target.type == "tnt" or f.target.type == "nuke" or f.target.type == "radium" then
                        -- Light or accelerate explosive fuse!
                        if not f.target.timer or f.target.timer <= 0 then
                            f.target.timer = math.max(0.5, 3.2 - f.intensity * 0.5)
                        else
                            f.target.timer = math.max(0.05, f.target.timer - dt * (1 + f.intensity * 0.5))
                        end
                    else
                        -- Apply continuous fire damage to props / enemies / player / whales
                        Entities.applyDamage(f.target, f.damagePerSec * dt)
                    end
                end

                -- C. Proximity damage to other entities in fire radius
                if entitiesList then
                    for _, other in ipairs(entitiesList) do
                        if other ~= f.target and other.body and not other.body:isDestroyed() then
                            local ox, oy = other.body:getPosition()
                            local odist = math.sqrt((f.hitWorldX - ox) ^ 2 + (f.hitWorldY - oy) ^ 2)
                            if odist < f.radius then
                                if other.type == "grenade" or other.type == "tnt" or other.type == "nuke" or other.type == "radium" then
                                    if not other.timer or other.timer <= 0 then
                                        other.timer = math.max(0.5, 3.0 - f.intensity * 0.4)
                                    end
                                else
                                    Entities.applyDamage(other, f.damagePerSec * 0.5 * dt)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- 2. Update Realistic Particles
    for i = #Fire.particles, 1, -1 do
        local p = Fire.particles[i]
        p.life = p.life - dt

        if p.life <= 0 then
            table.remove(Fire.particles, i)
        else
            if p.pType == "flame" then
                -- Upward buoyant draft
                p.vy = p.vy - 160 * dt
                -- Turbulent lateral jitter
                p.vx = p.vx + (math.sin(time * 12 + p.rot) * 45) * dt
                p.x = p.x + p.vx * dt
                p.y = p.y + p.vy * dt
                p.rot = p.rot + (p.vRot or 0) * dt

                -- Growth over lifetime
                local progress = 1 - (p.life / p.maxLife)
                p.currentSize = p.startSize + (p.endSize - p.startSize) * progress

            elseif p.pType == "ember" then
                -- Fast rising spark with air flutter
                p.vy = p.vy - 240 * dt
                p.vx = p.vx + (math.sin(time * 18 + p.y * 0.2) * 70) * dt
                p.x = p.x + p.vx * dt
                p.y = p.y + p.vy * dt

            elseif p.pType == "smoke" or p.pType == "steam" then
                -- Slow rising, expanding cloud
                p.vy = p.vy - 40 * dt
                p.x = p.x + p.vx * dt
                p.y = p.y + p.vy * dt
                p.rot = p.rot + (p.vRot or 0) * dt
                local progress = 1 - (p.life / p.maxLife)
                p.currentSize = p.startSize + (p.endSize - p.startSize) * progress
            end
        end
    end
end

-- Render realistic particle fire using soft radial glow texture and additive blend mode
function Fire.draw()
    if not Fire.particleTexture then
        Fire.init()
    end

    local tex = Fire.particleTexture
    if not tex then return end

    -- 1. LAYER 1: Large ambient warm glow around active fires
    love.graphics.setBlendMode("add")
    for _, f in ipairs(Fire.list) do
        local lifeFade = math.min(1.0, f.life / 1.5)
        local intScale = (0.8 + (f.intensity / 5.0) * 0.8)
        local rad = f.radius * intScale

        if not f.inWater then
            -- Ambient deep orange heat aura
            love.graphics.setColor(1.0, 0.35, 0.05, 0.14 * lifeFade)
            love.graphics.draw(tex, f.hitWorldX, f.hitWorldY - rad * 0.2, 0, (rad * 3.5) / 32, (rad * 3.5) / 32, 16, 16)

            -- Inner warm gold aura
            love.graphics.setColor(1.0, 0.65, 0.15, 0.25 * lifeFade)
            love.graphics.draw(tex, f.hitWorldX, f.hitWorldY - rad * 0.1, 0, (rad * 2.0) / 32, (rad * 2.0) / 32, 16, 16)
        end
    end

    -- 2. LAYER 2: Realistic Flame Particles (Additive Blend Mode)
    -- Overlapping soft particles naturally blend into blazing white-hot cores and golden/orange edges!
    for _, p in ipairs(Fire.particles) do
        if p.pType == "flame" then
            local t = p.life / p.maxLife
            local r, g, b, a

            -- Color temperature gradient from young (hot white/yellow) to old (deep red/charred)
            if t > 0.65 then
                -- White-hot core
                local s = (t - 0.65) / 0.35
                r = 1.0
                g = 0.82 + s * 0.18
                b = 0.40 + s * 0.60
                a = 0.95
            elseif t > 0.30 then
                -- Brilliant golden yellow to fiery orange
                local s = (t - 0.30) / 0.35
                r = 1.0
                g = 0.30 + s * 0.52
                b = 0.02 + s * 0.38
                a = 0.90
            else
                -- Fiery orange to deep embers red
                local s = t / 0.30
                r = 0.65 + s * 0.35
                g = 0.08 + s * 0.22
                b = 0.01
                a = s * 0.90
            end

            local scale = (p.currentSize or p.size) / 32
            love.graphics.setColor(r, g, b, a)
            love.graphics.draw(tex, p.x, p.y, p.rot, scale, scale, 16, 16)

        elseif p.pType == "ember" then
            local t = p.life / p.maxLife
            local alpha = math.min(1.0, t * 2.0)
            love.graphics.setColor(1.0, 0.78 + love.math.random() * 0.22, 0.25, alpha * 0.95)
            love.graphics.circle("fill", p.x, p.y, p.size or 2)
        end
    end

    -- 3. LAYER 3: Dark Smoke & Steam (Alpha Blend Mode)
    love.graphics.setBlendMode("alpha")

    for _, p in ipairs(Fire.particles) do
        if p.pType == "smoke" then
            local t = p.life / p.maxLife
            local alpha = (1 - (1 - t) ^ 2) * 0.32
            local scale = (p.currentSize or p.size) / 32
            love.graphics.setColor(0.18, 0.16, 0.16, alpha)
            love.graphics.draw(tex, p.x, p.y, p.rot, scale, scale, 16, 16)

        elseif p.pType == "steam" then
            local t = p.life / p.maxLife
            local alpha = (1 - (1 - t) ^ 2) * 0.38
            local scale = (p.currentSize or p.size) / 32
            love.graphics.setColor(0.85, 0.90, 0.95, alpha)
            love.graphics.draw(tex, p.x, p.y, p.rot, scale, scale, 16, 16)
        end
    end

    -- Reset to standard state
    love.graphics.setColor(1, 1, 1, 1)
end

return Fire
