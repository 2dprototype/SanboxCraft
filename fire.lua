-- fire.lua
-- Optimized Realistic Particle Fire System attached to physics bodies
local Water = require("water")
local EffectsSystem = require("effects")
local Entities = require("entities")
local Whale = require("whale")
local WorldManager = require("world_manager")

local MAX_PARTICLES = 500
local particlePool = {}

-- Particle table pooling to eliminate Garbage Collection allocations
local function acquireParticle()
    return table.remove(particlePool) or {}
end

local function releaseParticle(p)
    for k in pairs(p) do p[k] = nil end
    table.insert(particlePool, p)
end

local Fire = {
    list = {},
    particles = {},
    nextId = 1,
    particleTexture = nil,
    spriteBatch = nil
}

-- Initialize the Fire system and create radial particle texture + SpriteBatch
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
                    local alpha = (math.cos(dist * math.pi) * 0.5 + 0.5) ^ 1.6
                    imgData:setPixel(x, y, 1, 1, 1, alpha)
                else
                    imgData:setPixel(x, y, 1, 1, 1, 0)
                end
            end
        end
        Fire.particleTexture = love.graphics.newImage(imgData)
        Fire.particleTexture:setFilter("linear", "linear")
        Fire.spriteBatch = love.graphics.newSpriteBatch(Fire.particleTexture, MAX_PARTICLES + 100, "stream")
    end
end

-- Generate local surface attachment points anchored around the local hit point
function Fire.generateEmitters(body, target, hitWorldX, hitWorldY)
    local emitters = {}
    if not body or body:isDestroyed() then
        table.insert(emitters, { localX = 0, localY = 0 })
        return emitters
    end

    local lx, ly = body:getLocalPoint(hitWorldX, hitWorldY)

    -- Anchor emitters tightly around local hit point in 2D
    local count = 4
    for i = 1, count do
        local angle = (i / count) * math.pi * 2 + (love.math.random() - 0.5)
        local dist = love.math.random(3, 14)
        table.insert(emitters, {
            localX = lx + math.cos(angle) * dist,
            localY = ly + math.sin(angle) * dist
        })
    end

    return emitters
end

-- Insert a particle using the pool
local function pushParticle(pData)
    if #Fire.particles >= MAX_PARTICLES then
        local oldest = table.remove(Fire.particles, 1)
        releaseParticle(oldest)
    end
    local p = acquireParticle()
    for k, v in pairs(pData) do p[k] = v end
    table.insert(Fire.particles, p)
end

-- Create a fire object attached to a target / body
function Fire.create(target, worldX, worldY, initialIntensity)
    local intensity = initialIntensity or 1.0
    local body = (target and target.body) or nil
    local emitters = Fire.generateEmitters(body, target, worldX, worldY)

    local localHitX, localHitY = 0, 0
    if body and not body:isDestroyed() then
        localHitX, localHitY = body:getLocalPoint(worldX, worldY)
    end

    local maxLife = 8.0 + intensity * 3.5
    local fireObj = {
        id = Fire.nextId,
        target = target,
        body = body,
        emitters = emitters,
        localHitX = localHitX,
        localHitY = localHitY,
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

    Fire.spawnBurst(worldX, worldY, 8, intensity)

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

    if fireObj.body and not fireObj.body:isDestroyed() and #fireObj.emitters < 8 then
        local wx, wy = fireObj.body:getWorldPoint(fireObj.localHitX, fireObj.localHitY)
        local extraEmitters = Fire.generateEmitters(fireObj.body, fireObj.target, wx, wy)
        for _, em in ipairs(extraEmitters) do
            if #fireObj.emitters < 8 then
                table.insert(fireObj.emitters, em)
            end
        end
    end

    local wx, wy = fireObj.hitWorldX, fireObj.hitWorldY
    if fireObj.body and not fireObj.body:isDestroyed() then
        wx, wy = fireObj.body:getWorldPoint(fireObj.localHitX, fireObj.localHitY)
    end
    Fire.spawnBurst(wx, wy, 10, fireObj.intensity)
end

-- Spawn a realistic radial burst of fire particles
function Fire.spawnBurst(cx, cy, count, intensity)
    for i = 1, count do
        local angle = love.math.random() * math.pi * 2
        local speed = love.math.random(25, 65 * (0.8 + intensity * 0.25))
        local vx = math.cos(angle) * speed
        local vy = math.sin(angle) * speed - love.math.random(20, 60)
        local life = 0.3 + love.math.random() * 0.25
        local size = 8 + love.math.random() * 6 * intensity
        pushParticle({
            x = cx + (love.math.random() - 0.5) * 8,
            y = cy + (love.math.random() - 0.5) * 8,
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

    for i = 1, math.floor(count * 0.4) do
        local angle = love.math.random() * math.pi * 2
        local speed = love.math.random(30, 80)
        pushParticle({
            x = cx, y = cy,
            vx = math.cos(angle) * speed,
            vy = math.sin(angle) * speed - love.math.random(40, 90),
            life = 0.4 + love.math.random() * 0.3,
            maxLife = 0.7,
            size = 2 + love.math.random() * 1.5,
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
    local target = nil

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

    if not target and vegetationList then
        for _, v in ipairs(vegetationList) do
            local dist = math.sqrt((worldX - v.x) ^ 2 + (worldY - v.y) ^ 2)
            if dist < 22 then
                target = v
                break
            end
        end
    end

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

    local existing = Fire.findTargetFire(target, worldX, worldY, 40)
    if existing then
        Fire.intensify(existing, 1.0)
        Fire.castPlayerFlame(player, worldX, worldY)
        return existing
    end

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

    local count = math.min(10, math.floor(dist / 28) + 4)
    for i = 1, count do
        local progress = (i / count)
        local spread = (1 - progress) * 8
        local fx = px + nx * (dist * progress) + (love.math.random() - 0.5) * spread
        local fy = py + ny * (dist * progress) + (love.math.random() - 0.5) * spread
        local speed = love.math.random(80, 200)
        local life = 0.2 + love.math.random() * 0.2
        local size = 10 + love.math.random() * 8
        pushParticle({
            x = fx, y = fy,
            vx = nx * speed + (love.math.random() - 0.5) * 20,
            vy = ny * speed + (love.math.random() - 0.5) * 20,
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
        local bodyAlive = f.body and not f.body:isDestroyed()

        -- Maintain precise local hit location tracking on physical bodies
        if bodyAlive then
            f.hitWorldX, f.hitWorldY = f.body:getWorldPoint(f.localHitX, f.localHitY)
        end

        local anyInWater = false
        local waterArea = Water.isPointInWater(f.hitWorldX, f.hitWorldY)
        if waterArea then anyInWater = true end

        local spawnInterval = math.max(0.025, 0.07 - (f.intensity * 0.008))
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
                if shouldSpawn and love.math.random() < 0.6 then
                    local life = 0.35 + love.math.random() * 0.35
                    pushParticle({
                        x = wx + (love.math.random() - 0.5) * 8,
                        y = wy + (love.math.random() - 0.5) * 6,
                        vx = (love.math.random() - 0.5) * 25 + bvx * 0.2,
                        vy = -love.math.random(30, 70) + bvy * 0.2,
                        life = life, maxLife = life,
                        size = 12 + love.math.random() * 6,
                        startSize = 8, endSize = 20,
                        rot = love.math.random() * math.pi * 2,
                        vRot = (love.math.random() - 0.5) * 2,
                        pType = "steam"
                    })
                end
            else
                if shouldSpawn then
                    local baseSize = (12 + f.intensity * 5) * (0.8 + love.math.random() * 0.4)
                    local life = 0.3 + love.math.random() * 0.25
                    local upDraft = -love.math.random(50, 140) * (0.8 + f.intensity * 0.2)
                    local turbX = (love.math.random() - 0.5) * (25 + f.intensity * 8)

                    pushParticle({
                        x = wx + (love.math.random() - 0.5) * 5,
                        y = wy + (love.math.random() - 0.5) * 5,
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

                    if love.math.random() < (0.2 + f.intensity * 0.08) then
                        local emberLife = 0.4 + love.math.random() * 0.3
                        pushParticle({
                            x = wx, y = wy,
                            vx = bvx * 0.4 + (love.math.random() - 0.5) * 50,
                            vy = bvy * 0.4 - love.math.random(80, 180),
                            life = emberLife, maxLife = emberLife,
                            size = 1.6 + love.math.random() * 1.4,
                            pType = "ember"
                        })
                    end

                    if love.math.random() < 0.1 then
                        local smokeLife = 0.6 + love.math.random() * 0.4
                        local smokeSize = 14 + f.intensity * 5
                        pushParticle({
                            x = wx + (love.math.random() - 0.5) * 10,
                            y = wy - baseSize * 0.8,
                            vx = bvx * 0.2 + (love.math.random() - 0.5) * 18,
                            vy = -love.math.random(20, 50),
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

        if f.inWater then
            f.life = f.life - dt * 10.0
            f.intensity = f.intensity - dt * 5.0
        else
            f.life = f.life - dt
        end

        if f.life <= 0 or f.intensity <= 0 then
            for p = 1, 3 do
                pushParticle({
                    x = f.hitWorldX + (love.math.random() - 0.5) * 10,
                    y = f.hitWorldY - love.math.random(5, 12),
                    vx = (love.math.random() - 0.5) * 20,
                    vy = -love.math.random(20, 45),
                    life = 0.5, maxLife = 0.5,
                    size = 16, startSize = 8, endSize = 22,
                    rot = love.math.random() * math.pi * 2,
                    vRot = (love.math.random() - 0.5) * 2,
                    pType = "smoke"
                })
            end
            table.remove(Fire.list, i)
        else
            if not f.inWater then
                if vegetationList then
                    local grassBurnDmg = (45 + f.intensity * 35) * dt
                    for gIdx = #vegetationList, 1, -1 do
                        local grass = vegetationList[gIdx]
                        local gdx = f.hitWorldX - grass.x
                        local gdy = f.hitWorldY - grass.y
                        local dist = math.sqrt(gdx * gdx + gdy * gdy)
                        if dist < (f.radius + 12) then
                            grass.health = grass.health - grassBurnDmg
                            if grass.health <= 0 then
                                for p = 1, 2 do
                                    EffectsSystem.createParticle(
                                        grass.x, grass.y,
                                        (love.math.random() - 0.5) * 60,
                                        -love.math.random(20, 60),
                                        20, 180, 1.8, "grassDebris"
                                    )
                                    pushParticle({
                                        x = grass.x, y = grass.y,
                                        vx = (love.math.random() - 0.5) * 30,
                                        vy = -love.math.random(30, 90),
                                        life = 0.4, maxLife = 0.4,
                                        size = 2.2, pType = "ember"
                                    })
                                end
                                table.remove(vegetationList, gIdx)
                            end
                        end
                    end
                end

                local okTrees, Trees = pcall(require, "trees")
                if okTrees and Trees and Trees.damageInRadius then
                    Trees.damageInRadius(f.hitWorldX, f.hitWorldY, f.radius + 15, f.damagePerSec * dt * 0.8)
                end

                if f.target and f.target.type then
                    if f.target.type == "grenade" or f.target.type == "tnt" or f.target.type == "nuke" or f.target.type == "radium" then
                        if not f.target.timer or f.target.timer <= 0 then
                            f.target.timer = math.max(0.5, 3.2 - f.intensity * 0.5)
                        else
                            f.target.timer = math.max(0.05, f.target.timer - dt * (1 + f.intensity * 0.5))
                        end
                    else
                        Entities.applyDamage(f.target, f.damagePerSec * dt)
                    end
                end

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

    -- 2. Update Particles with Memory Recycling
    for i = #Fire.particles, 1, -1 do
        local p = Fire.particles[i]
        p.life = p.life - dt

        if p.life <= 0 then
            releaseParticle(p)
            table.remove(Fire.particles, i)
        else
            if p.pType == "flame" then
                p.vy = p.vy - 160 * dt
                p.vx = p.vx + (math.sin(time * 12 + p.rot) * 40) * dt
                p.x = p.x + p.vx * dt
                p.y = p.y + p.vy * dt
                p.rot = p.rot + (p.vRot or 0) * dt
                local progress = 1 - (p.life / p.maxLife)
                p.currentSize = p.startSize + (p.endSize - p.startSize) * progress

            elseif p.pType == "ember" then
                p.vy = p.vy - 220 * dt
                p.vx = p.vx + (math.sin(time * 18 + p.y * 0.2) * 60) * dt
                p.x = p.x + p.vx * dt
                p.y = p.y + p.vy * dt

            elseif p.pType == "smoke" or p.pType == "steam" then
                p.vy = p.vy - 35 * dt
                p.x = p.x + p.vx * dt
                p.y = p.y + p.vy * dt
                p.rot = p.rot + (p.vRot or 0) * dt
                local progress = 1 - (p.life / p.maxLife)
                p.currentSize = p.startSize + (p.endSize - p.startSize) * progress
            end
        end
    end
end

-- Render realistic particle fire using LÖVE2D SpriteBatch (1-2 draw calls max)
function Fire.draw()
    if not Fire.particleTexture then
        Fire.init()
    end

    local tex = Fire.particleTexture
    if not tex or not Fire.spriteBatch then return end

    -- 1. Ambient Glow
    love.graphics.setBlendMode("add")
    for _, f in ipairs(Fire.list) do
        local lifeFade = math.min(1.0, f.life / 1.5)
        local intScale = (0.8 + (f.intensity / 5.0) * 0.8)
        local rad = f.radius * intScale

        if not f.inWater then
            love.graphics.setColor(1.0, 0.35, 0.05, 0.14 * lifeFade)
            love.graphics.draw(tex, f.hitWorldX, f.hitWorldY - rad * 0.2, 0, (rad * 3.5) / 32, (rad * 3.5) / 32, 16, 16)

            love.graphics.setColor(1.0, 0.65, 0.15, 0.25 * lifeFade)
            love.graphics.draw(tex, f.hitWorldX, f.hitWorldY - rad * 0.1, 0, (rad * 2.0) / 32, (rad * 2.0) / 32, 16, 16)
        end
    end

    -- 2. Flame & Ember Particles (Batched)
    Fire.spriteBatch:clear()
    for _, p in ipairs(Fire.particles) do
        if p.pType == "flame" then
            local t = p.life / p.maxLife
            local r, g, b, a

            if t > 0.65 then
                local s = (t - 0.65) / 0.35
                r, g, b, a = 1.0, 0.82 + s * 0.18, 0.40 + s * 0.60, 0.95
            elseif t > 0.30 then
                local s = (t - 0.30) / 0.35
                r, g, b, a = 1.0, 0.30 + s * 0.52, 0.02 + s * 0.38, 0.90
            else
                local s = t / 0.30
                r, g, b, a = 0.65 + s * 0.35, 0.08 + s * 0.22, 0.01, s * 0.90
            end

            local scale = (p.currentSize or p.size) / 32
            Fire.spriteBatch:setColor(r, g, b, a)
            Fire.spriteBatch:add(p.x, p.y, p.rot, scale, scale, 16, 16)

        elseif p.pType == "ember" then
            local t = p.life / p.maxLife
            local alpha = math.min(1.0, t * 2.0)
            local scale = (p.size or 2) / 32
            Fire.spriteBatch:setColor(1.0, 0.85, 0.25, alpha * 0.95)
            Fire.spriteBatch:add(p.x, p.y, 0, scale, scale, 16, 16)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(Fire.spriteBatch)

    -- 3. Smoke & Steam Particles (Batched)
    love.graphics.setBlendMode("alpha")
    Fire.spriteBatch:clear()
    for _, p in ipairs(Fire.particles) do
        if p.pType == "smoke" then
            local t = p.life / p.maxLife
            local alpha = (1 - (1 - t) ^ 2) * 0.32
            local scale = (p.currentSize or p.size) / 32
            Fire.spriteBatch:setColor(0.18, 0.16, 0.16, alpha)
            Fire.spriteBatch:add(p.x, p.y, p.rot, scale, scale, 16, 16)

        elseif p.pType == "steam" then
            local t = p.life / p.maxLife
            local alpha = (1 - (1 - t) ^ 2) * 0.38
            local scale = (p.currentSize or p.size) / 32
            Fire.spriteBatch:setColor(0.85, 0.90, 0.95, alpha)
            Fire.spriteBatch:add(p.x, p.y, p.rot, scale, scale, 16, 16)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(Fire.spriteBatch)

    love.graphics.setColor(1, 1, 1, 1)
end

return Fire