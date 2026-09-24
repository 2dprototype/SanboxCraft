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
    if Fire.list then
        for _, f in ipairs(Fire.list) do
            if f.ownBody and not f.ownBody:isDestroyed() then
                f.ownBody:destroy()
                f.ownBody = nil
            end
        end
    end

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

-- Create an invisible circle physics body for unattached or detached fires
local function createInvisibleCircleBody(x, y, radius, vx, vy)
    radius = radius or 10
    if not WorldManager or not WorldManager.world then return nil, nil, nil end

    local body = love.physics.newBody(WorldManager.world, x, y, "dynamic")
    local shape = love.physics.newCircleShape(radius)
    local fixture = love.physics.newFixture(body, shape, 0.8)
    fixture:setFriction(0.5)
    fixture:setRestitution(0.25)
    body:setLinearDamping(0.2)
    body:setAngularDamping(0.5)
    body:setUserData("fire_circle")
    fixture:setUserData("fire_circle")

    if vx and vy then
        body:setLinearVelocity(vx, vy)
    end
    return body, shape, fixture
end

-- Generate emitters around the center of an invisible circle body
local function generateCircleEmitters(radius)
    local emitters = {}
    local count = 4
    for i = 1, count do
        local angle = (i / count) * math.pi * 2 + (love.math.random() - 0.5)
        local dist = love.math.random(2, math.max(4, radius * 0.7))
        table.insert(emitters, {
            localX = math.cos(angle) * dist,
            localY = math.sin(angle) * dist
        })
    end
    return emitters
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

-- Converts an attached fire whose target body was destroyed or split into an unattached fire
-- that has and follows its own invisible circle physics body
function Fire.convertToInvisibleBody(fireObj)
    if not fireObj or fireObj.isOwnBody then return end

    local wx = fireObj.hitWorldX or 0
    local wy = fireObj.hitWorldY or 0
    local vx = fireObj.lastVx or 0
    local vy = fireObj.lastVy or 0

    -- If the attached body is still alive, sample the most accurate coordinates and velocity right now
    if fireObj.body and not fireObj.body:isDestroyed() then
        pcall(function()
            wx, wy = fireObj.body:getWorldPoint(fireObj.localHitX or 0, fireObj.localHitY or 0)
            vx, vy = fireObj.body:getLinearVelocityFromWorldPoint(wx, wy)
        end)
    end

    -- Add a small dynamic scatter impulse upon detachment / splitting
    local scatterVx = vx + (love.math.random() - 0.5) * 30
    local scatterVy = vy + (love.math.random() - 0.5) * 30 - love.math.random(15, 45)

    local circleRadius = math.min(12, math.max(7, 8 + (fireObj.intensity or 1.0)))
    local body, shape, fixture = createInvisibleCircleBody(wx, wy, circleRadius, scatterVx, scatterVy)

    fireObj.isAttached = false
    fireObj.isOwnBody = true
    fireObj.target = nil
    fireObj.body = body
    fireObj.ownBody = body
    fireObj.shape = shape
    fireObj.fixture = fixture
    fireObj.circleRadius = circleRadius

    fireObj.localHitX = 0
    fireObj.localHitY = 0
    fireObj.hitWorldX = wx
    fireObj.hitWorldY = wy
    fireObj.lastWorldX = wx
    fireObj.lastWorldY = wy
    fireObj.lastVx = scatterVx
    fireObj.lastVy = scatterVy

    fireObj.emitters = generateCircleEmitters(circleRadius)

    Fire.spawnBurst(wx, wy, 8, fireObj.intensity)
end

-- Called when an external physics body is about to be destroyed or split
function Fire.onBodyDestroyedOrSplit(body)
    if not body then return end
    for _, f in ipairs(Fire.list) do
        if f.isAttached and f.body == body and not f.isOwnBody then
            Fire.convertToInvisibleBody(f)
        end
    end
end

-- Apply physical explosion impulse to any free-floating invisible fire bodies
function Fire.applyImpulseInRadius(cx, cy, radius, maxForce)
    for _, f in ipairs(Fire.list) do
        if f.isOwnBody and f.ownBody and not f.ownBody:isDestroyed() then
            local fx, fy = f.ownBody:getPosition()
            local dx = fx - cx
            local dy = fy - cy
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < radius and dist > 0.001 then
                local falloff = 1 - (dist / radius)
                local force = (maxForce or 100) * falloff
                local nx = dx / dist
                local ny = dy / dist
                f.ownBody:applyLinearImpulse(nx * force, ny * force)
            end
        end
    end
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

-- Create a fire object attached to a target / body, or with an invisible circle body if not attached
function Fire.create(target, worldX, worldY, initialIntensity, initVx, initVy)
    local intensity = initialIntensity or 1.0
    local body = (target and target.body) or nil
    if body and body:isDestroyed() then body = nil end

    local maxLife = 8.0 + intensity * 3.5
    local fireObj = {
        id = Fire.nextId,
        intensity = intensity,
        maxIntensity = 5.0,
        life = maxLife,
        maxLife = maxLife,
        radius = 20 + intensity * 8,
        damagePerSec = 25 * intensity,
        inWater = false,
        spawnTimer = 0,
        hitWorldX = worldX,
        hitWorldY = worldY,
        lastWorldX = worldX,
        lastWorldY = worldY,
        lastVx = initVx or 0,
        lastVy = initVy or 0
    }
    Fire.nextId = Fire.nextId + 1

    if body then
        -- Attached to existing body: follow it!
        fireObj.isAttached = true
        fireObj.isOwnBody = false
        fireObj.target = target
        fireObj.body = body
        fireObj.ownBody = nil
        fireObj.localHitX, fireObj.localHitY = body:getLocalPoint(worldX, worldY)
        fireObj.emitters = Fire.generateEmitters(body, target, worldX, worldY)
        pcall(function()
            fireObj.lastVx, fireObj.lastVy = body:getLinearVelocityFromWorldPoint(worldX, worldY)
        end)
    else
        -- Not attached: create an invisible circle physics body which it follows!
        local circleRadius = math.min(12, math.max(7, 8 + intensity))
        local ownBody, shape, fixture = createInvisibleCircleBody(worldX, worldY, circleRadius, initVx or 0, initVy or 0)
        fireObj.isAttached = false
        fireObj.isOwnBody = true
        fireObj.target = nil
        fireObj.body = ownBody
        fireObj.ownBody = ownBody
        fireObj.shape = shape
        fireObj.fixture = fixture
        fireObj.circleRadius = circleRadius
        fireObj.localHitX = 0
        fireObj.localHitY = 0
        fireObj.emitters = generateCircleEmitters(circleRadius)
    end

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
        if fireObj.isAttached then
            local wx, wy = fireObj.body:getWorldPoint(fireObj.localHitX, fireObj.localHitY)
            local extraEmitters = Fire.generateEmitters(fireObj.body, fireObj.target, wx, wy)
            for _, em in ipairs(extraEmitters) do
                if #fireObj.emitters < 8 then
                    table.insert(fireObj.emitters, em)
                end
            end
        else
            local extraEmitters = generateCircleEmitters(fireObj.circleRadius or 10)
            for _, em in ipairs(extraEmitters) do
                if #fireObj.emitters < 8 then
                    table.insert(fireObj.emitters, em)
                end
            end
        end
    end

    local wx, wy = fireObj.hitWorldX, fireObj.hitWorldY
    if fireObj.body and not fireObj.body:isDestroyed() then
        if fireObj.isAttached then
            wx, wy = fireObj.body:getWorldPoint(fireObj.localHitX, fireObj.localHitY)
        else
            wx, wy = fireObj.body:getPosition()
        end
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
        if target and f.isAttached and f.target and f.target == target then
            return f
        end
        if target and target.body and f.isAttached and f.body and f.body == target.body then
            return f
        end
        if not target and f.isOwnBody then
            local dx = f.hitWorldX - worldX
            local dy = f.hitWorldY - worldY
            if math.sqrt(dx * dx + dy * dy) <= (radius or 20) then
                return f
            end
        end
    end
    return nil
end

-- Player ignites target under mouse cursor (or creates a free-floating circle body fireball in blank space)
function Fire.igniteAt(worldX, worldY, player, entitiesList, vegetationList)
    local target = nil

    if entitiesList then
        local minDist = 35
        for _, e in ipairs(entitiesList) do
            if e.body and not e.body:isDestroyed() and e ~= player then
                local ex, ey = e.body:getPosition()
                local dist = math.sqrt((worldX - ex) ^ 2 + (worldY - ey) ^ 2)
                local threshold = (e.r or math.max(e.w or 20, e.h or 20) / 2) + 6
                local inside = false
                if e.fixture and not e.fixture:isDestroyed() then
                    inside = e.fixture:testPoint(worldX, worldY)
                end
                if (inside or dist < threshold) and dist < minDist then
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
                if w.fixture and not w.fixture:isDestroyed() and w.fixture:testPoint(worldX, worldY) then
                    target = w
                    break
                end
            end
        end
    end

    -- Check trees (branches have physical dynamic bodies)
    if not target then
        local okTrees, Trees = pcall(require, "trees")
        if okTrees and Trees and Trees.list then
            local minDist = 30
            for _, tree in ipairs(Trees.list) do
                for _, branch in ipairs(tree.branches or {}) do
                    if branch.body and not branch.body:isDestroyed() and not branch.isSevered then
                        local bx, by = branch.body:getPosition()
                        local dist = math.sqrt((worldX - bx) ^ 2 + (worldY - by) ^ 2)
                        local inside = false
                        if branch.fixtures then
                            for _, fix in ipairs(branch.fixtures) do
                                if not fix:isDestroyed() and fix:testPoint(worldX, worldY) then
                                    inside = true
                                    break
                                end
                            end
                        end
                        if (inside or dist < (branch.w1 or 10) + 5) and dist < minDist then
                            minDist = dist
                            target = branch
                        end
                    end
                end
                if target then break end
            end
        end
    end

    -- Only match boundaries if the cursor is ACTUALLY inside the boundary fixture
    if not target and WorldManager and WorldManager.boundaries then
        for _, b in ipairs(WorldManager.boundaries) do
            if b.body and not b.body:isDestroyed() and b.fixture and not b.fixture:isDestroyed() then
                if b.fixture:testPoint(worldX, worldY) then
                    target = b
                    break
                end
            end
        end
    end

    -- Query any other physics fixture in the Box2D world under mouse cursor
    if not target and WorldManager and WorldManager.world then
        WorldManager.world:queryBoundingBox(worldX - 10, worldY - 10, worldX + 10, worldY + 10, function(fixture)
            if not fixture:isDestroyed() and fixture:testPoint(worldX, worldY) then
                local b = fixture:getBody()
                if b and not b:isDestroyed() and (not player or b ~= player.body) and b:getUserData() ~= "fire_circle" then
                    target = { body = b, fixture = fixture }
                    return false
                end
            end
            return true
        end)
    end

    -- Check vegetation (vegetation has no body, so target has no body -> circle body is created!)
    if not target and vegetationList then
        for _, v in ipairs(vegetationList) do
            local dist = math.sqrt((worldX - v.x) ^ 2 + (worldY - v.y) ^ 2)
            if dist < 18 then
                target = v
                break
            end
        end
    end

    local existing = Fire.findTargetFire(target, worldX, worldY, target and 35 or 18)
    if existing then
        Fire.intensify(existing, 1.0)
        Fire.castPlayerFlame(player, worldX, worldY)
        return existing
    end

    -- If target is blank / has no body, calculate initial launch velocity from player toward cursor
    local initVx, initVy = 0, 0
    local targetBody = (target and target.body) or nil
    if not targetBody and player and player.body and not player.body:isDestroyed() then
        local px, py = player.body:getPosition()
        local dx = worldX - px
        local dy = worldY - py
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist > 5 then
            local speed = 75
            initVx = (dx / dist) * speed
            initVy = (dy / dist) * speed - 25
        end
    end

    local f = Fire.create(target, worldX, worldY, 1.0, initVx, initVy)
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

-- Merge two independent colliding fireballs into one larger, more intense fireball
function Fire.mergeFireballs(f1, f2, f2Index)
    if not f1 or not f2 then return end

    -- Remove f2 from Fire.list
    if f2Index and Fire.list[f2Index] == f2 then
        table.remove(Fire.list, f2Index)
    else
        for idx, item in ipairs(Fire.list) do
            if item == f2 then
                table.remove(Fire.list, idx)
                break
            end
        end
    end

    local totalIntensity = (f1.intensity or 1.0) + (f2.intensity or 1.0)
    local w1 = (f1.intensity or 1.0) / totalIntensity
    local w2 = (f2.intensity or 1.0) / totalIntensity

    local mx = (f1.hitWorldX or 0) * w1 + (f2.hitWorldX or 0) * w2
    local my = (f1.hitWorldY or 0) * w1 + (f2.hitWorldY or 0) * w2

    local v1x, v1y = 0, 0
    local v2x, v2y = 0, 0
    if f1.ownBody and not f1.ownBody:isDestroyed() then
        v1x, v1y = f1.ownBody:getLinearVelocity()
    end
    if f2.ownBody and not f2.ownBody:isDestroyed() then
        v2x, v2y = f2.ownBody:getLinearVelocity()
    end

    local mvx = v1x * w1 + v2x * w2
    local mvy = v1y * w1 + v2y * w2

    f1.intensity = math.min(f1.maxIntensity, f1.intensity + f2.intensity * 0.7)
    f1.life = math.min(30.0, math.max(f1.life, f2.life) + 2.5 + f2.intensity * 1.5)
    f1.maxLife = math.max(f1.maxLife, f2.maxLife) + 3.0
    f1.radius = 20 + f1.intensity * 8
    f1.damagePerSec = 25 * f1.intensity

    f1.circleRadius = math.min(24, math.max(8, 8 + f1.intensity * 2.2))

    if f1.ownBody and not f1.ownBody:isDestroyed() then
        f1.ownBody:setPosition(mx, my)
        f1.ownBody:setLinearVelocity(mvx, mvy)
        if f1.shape and f1.shape.setRadius then
            pcall(function()
                f1.shape:setRadius(f1.circleRadius)
                f1.ownBody:resetMassData()
            end)
        end
    end

    f1.hitWorldX = mx
    f1.hitWorldY = my
    f1.lastWorldX = mx
    f1.lastWorldY = my
    f1.lastVx = mvx
    f1.lastVy = mvy

    f1.emitters = generateCircleEmitters(f1.circleRadius)

    if f2.ownBody and not f2.ownBody:isDestroyed() then
        f2.ownBody:destroy()
        f2.ownBody = nil
    end

    -- Visual burst and shockwave for fireball merge
    Fire.spawnBurst(mx, my, 16, f1.intensity)
    local okEff, Effects = pcall(require, "effects")
    if okEff and Effects and Effects.createShockwave then
        Effects.createShockwave(mx, my, 20 + f1.circleRadius * 2, 0.45, "fire")
    end
    if okEff and Effects and Effects.createParticle then
        for s = 1, 8 do
            local ang = love.math.random() * math.pi * 2
            local spd = love.math.random(60, 160)
            Effects.createParticle(mx, my, math.cos(ang) * spd, math.sin(ang) * spd - 15, 20, 280, 2.5, "orangeSpark")
        end
    end
end

-- Update all fire objects, emitters, and particles
function Fire.update(dt, entitiesList, vegetationList)
    local time = love.timer.getTime()

    -- 0. Merge colliding independent fireballs
    for i = #Fire.list, 1, -1 do
        local f1 = Fire.list[i]
        if f1 and f1.isOwnBody and f1.ownBody and not f1.ownBody:isDestroyed() then
            for j = i - 1, 1, -1 do
                local f2 = Fire.list[j]
                if f2 and f2.isOwnBody and f2.ownBody and not f2.ownBody:isDestroyed() then
                    local dx = f1.hitWorldX - f2.hitWorldX
                    local dy = f1.hitWorldY - f2.hitWorldY
                    local dist = math.sqrt(dx * dx + dy * dy)
                    local r1 = f1.circleRadius or 10
                    local r2 = f2.circleRadius or 10
                    local collideDist = r1 + r2 + 6

                    if dist <= collideDist then
                        Fire.mergeFireballs(f1, f2, j)
                        break
                    end
                end
            end
        end
    end

    -- 1. Update Fire Objects
    for i = #Fire.list, 1, -1 do
        local f = Fire.list[i]

        -- If attached fire's target body was destroyed or split, convert to invisible circle body
        if f.isAttached then
            if not f.body or f.body:isDestroyed() or (f.target and f.target.dead) then
                Fire.convertToInvisibleBody(f)
            end
        end

        local bodyAlive = f.body and not f.body:isDestroyed()

        -- Follow the physics body:
        -- If attached to an entity body -> track localHitX, localHitY
        -- If unattached / ownBody -> track circle body position
        if bodyAlive then
            if f.isAttached then
                f.hitWorldX, f.hitWorldY = f.body:getWorldPoint(f.localHitX, f.localHitY)
                pcall(function()
                    f.lastVx, f.lastVy = f.body:getLinearVelocityFromWorldPoint(f.hitWorldX, f.hitWorldY)
                end)
            else
                f.hitWorldX, f.hitWorldY = f.body:getPosition()
                pcall(function()
                    f.lastVx, f.lastVy = f.body:getLinearVelocity()
                end)
            end
            f.lastWorldX, f.lastWorldY = f.hitWorldX, f.hitWorldY
        end

        local anyInWater = false
        local waterArea = Water.isPointInWater(f.hitWorldX, f.hitWorldY)
        if waterArea then anyInWater = true end

        -- Submerged physics for own invisible circle body: water resistance and buoyancy
        if anyInWater and f.isOwnBody and bodyAlive then
            pcall(function()
                local vx, vy = f.body:getLinearVelocity()
                f.body:setLinearVelocity(vx * (1 - math.min(1, dt * 3.0)), vy * (1 - math.min(1, dt * 2.0)) - 15 * dt * 64)
            end)
        end

        local spawnInterval = math.max(0.025, 0.07 - (f.intensity * 0.008))
        f.spawnTimer = f.spawnTimer + dt

        local shouldSpawn = false
        if f.spawnTimer >= spawnInterval then
            f.spawnTimer = 0
            shouldSpawn = true
        end

        for _, em in ipairs(f.emitters) do
            local wx, wy = f.hitWorldX, f.hitWorldY
            local bvx, bvy = f.lastVx or 0, f.lastVy or 0

            if bodyAlive then
                wx, wy = f.body:getWorldPoint(em.localX, em.localY)
                pcall(function()
                    bvx, bvy = f.body:getLinearVelocityFromWorldPoint(wx, wy)
                end)
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
            -- Velocity rapidly reduces independent fireball's duration
            local speedMultiplier = 1.0
            if f.isOwnBody and bodyAlive then
                local vx, vy = f.lastVx or 0, f.lastVy or 0
                local speed = math.sqrt(vx * vx + vy * vy)
                if speed > 20 then
                    -- Rapidly burn out fuel proportional to movement velocity
                    speedMultiplier = 1.0 + (speed / 70.0) * 1.5

                    -- Spawn extra trailing embers as velocity rapidly burns out the fireball
                    if love.math.random() < math.min(0.5, speed / 250.0) then
                        pushParticle({
                            x = f.hitWorldX + (love.math.random() - 0.5) * 6,
                            y = f.hitWorldY + (love.math.random() - 0.5) * 6,
                            vx = -vx * 0.25 + (love.math.random() - 0.5) * 35,
                            vy = -vy * 0.25 - love.math.random(20, 50),
                            life = 0.2 + love.math.random() * 0.2,
                            maxLife = 0.4,
                            size = 2.0 + love.math.random() * 1.5,
                            pType = "ember"
                        })
                    end
                end
            end
            f.life = f.life - dt * speedMultiplier
        end

        -- Check out-of-bounds or expiration
        local outOfBounds = (f.hitWorldY and f.hitWorldY > 10000)
        if f.life <= 0 or f.intensity <= 0 or outOfBounds then
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
            if f.ownBody and not f.ownBody:isDestroyed() then
                f.ownBody:destroy()
                f.ownBody = nil
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

                if f.isAttached and f.target and f.target.type then
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

-- Clear all fires and safely clean up their physics bodies
function Fire.clear()
    if Fire.list then
        for _, f in ipairs(Fire.list) do
            if f.ownBody and not f.ownBody:isDestroyed() then
                f.ownBody:destroy()
                f.ownBody = nil
            end
        end
    end
    Fire.list = {}
    Fire.particles = {}
end

return Fire