-- world_manager.lua (UPDATED WITH SLICING FIXES)
local Config = require("config")
local WorldManager = {
    world = nil,
    boundaries = {},
    spatialGrid = {}, -- Format: grid[cx][cy] = { entities }
    timer = 0,
    activeRadius = Config.chunks.activeRadius
}

function WorldManager.init()
    love.physics.setMeter(Config.physics.meter)
    WorldManager.world = love.physics.newWorld(0, Config.physics.gravityY, true)
    WorldManager.spatialGrid = {}
    WorldManager.activeRadius = Config.chunks.activeRadius
end

function WorldManager.getChunkCoords(x, y)
    local size = Config.chunks.size
    return math.floor(x / size), math.floor(y / size)
end

function WorldManager.registerEntity(entity)
    if not entity.body or entity.body:isDestroyed() then return end
    local x, y = entity.body:getPosition()
    local cx, cy = WorldManager.getChunkCoords(x, y)
    
    -- WorldManager.spatialGrid[cx] = WorldManager.spatialGrid[cx] or {}
    -- WorldManager.spatialGrid[cx][cy] = WorldManager.spatialGrid[cx][cy] or {}
    
    -- table.insert(WorldManager.spatialGrid[cx][cy], entity)
    entity.currentChunkX = cx
    entity.currentChunkY = cy
end

function WorldManager.updateSpatialGrid(entities)
    -- Re-index dynamic game objects across grid chunks
    WorldManager.spatialGrid = {}
    for _, entity in ipairs(entities) do
        if entity.body and not entity.body:isDestroyed() then
            WorldManager.registerEntity(entity)
        end
    end
end

function WorldManager.optimizeActiveChunks(cameraX, cameraY)
    local ccx, ccy = WorldManager.getChunkCoords(cameraX, cameraY)
    local radius = WorldManager.activeRadius

    for cx, col in pairs(WorldManager.spatialGrid) do
        for cy, entities in pairs(col) do
            -- 1. Calculate if this specific chunk is within the active radius
            local shouldBeActive = (math.abs(cx - ccx) <= radius) and (math.abs(cy - ccy) <= radius)
            
            for _, entity in ipairs(entities) do
                if entity.body and not entity.body:isDestroyed() and entity.body:getType() == "dynamic" then
                    -- 2. CRITICAL FIX: Only call setActive if the state actually needs to change!
                    -- This prevents Box2D from wiping the contact manifolds of resting objects.
                    if entity.body:isActive() ~= shouldBeActive then
                        entity.body:setActive(shouldBeActive)
                    end
                end
            end
        end
    end
end

function WorldManager.createBoundary(x, y, w, h, angle)
    local body = love.physics.newBody(WorldManager.world, x, y, "static")
    local shape = love.physics.newRectangleShape(w, h)
    local fixture = love.physics.newFixture(body, shape)
    fixture:setFriction(0.5)
    fixture:setRestitution(0.2)
    body:setAngle(angle)
    
    local boundary = { body = body, shape = shape, fixture = fixture, w = w, h = h, type = "boundary" }
    table.insert(WorldManager.boundaries, boundary)
    return boundary
end

function WorldManager.drawBoundaries()
    love.graphics.setColor(0, 0, 0)
    for _, b in ipairs(WorldManager.boundaries) do
        if b.body and not b.body:isDestroyed() then
            love.graphics.polygon("fill", b.body:getWorldPoints(b.shape:getPoints()))
        end
    end
end

-- ========== BOUNDARY SLICING FEATURE (CONTACT-BASED) ==========

function WorldManager.getCollidingBoundary(player)
    if not player or not player.body or player.body:isDestroyed() then return nil, nil end
    local contacts = WorldManager.world:getContacts()
    for _, contact in ipairs(contacts) do
        if contact:isEnabled() then
            local fa, fb = contact:getFixtures()
            if not fa or not fb then goto continue end
            local bodyA = fa:getBody()
            local bodyB = fb:getBody()
            local isPlayerA = (bodyA == player.body)
            local isPlayerB = (bodyB == player.body)
            if isPlayerA or isPlayerB then
                local boundaryBody = isPlayerA and bodyB or bodyA
                for _, b in ipairs(WorldManager.boundaries) do
                    if b.body == boundaryBody then
                        return b, contact
                    end
                end
            end
        end
        ::continue::
    end
    return nil, nil
end

function WorldManager.getContactOverlapOnBoundary(boundary, playerBody, contact)
    if not contact then
        local contacts = WorldManager.world:getContactList()
        for _, c in ipairs(contacts) do
            if c:isEnabled() then
                local fa, fb = c:getFixtures()
                if fa and fb then
                    local bodyA = fa:getBody()
                    local bodyB = fb:getBody()
                    if (bodyA == playerBody and bodyB == boundary.body) or
                       (bodyB == playerBody and bodyA == boundary.body) then
                        contact = c
                        break
                    end
                end
            end
        end
    end
    if not contact then return nil, nil end

    local x1, y1, x2, y2, nx, ny = contact:getPositions()
    local points = {}
    if x1 and y1 then table.insert(points, {x = x1, y = y1}) end
    if x2 and y2 then table.insert(points, {x = x2, y = y2}) end
    if #points == 0 then return nil, nil end

    local worldPoints = {boundary.body:getWorldPoints(boundary.shape:getPoints())}
    local p1 = {x=worldPoints[1], y=worldPoints[2]}
    local p2 = {x=worldPoints[3], y=worldPoints[4]}
    local p3 = {x=worldPoints[5], y=worldPoints[6]}
    local dx12 = p2.x - p1.x
    local dy12 = p2.y - p1.y
    local len12 = math.sqrt(dx12*dx12 + dy12*dy12)
    local dx23 = p3.x - p2.x
    local dy23 = p3.y - p2.y
    local len23 = math.sqrt(dx23*dx23 + dy23*dy23)

    local axis
    if len12 > len23 then
        axis = {x = dx12/len12, y = dy12/len12}
    else
        axis = {x = dx23/len23, y = dy23/len23}
    end

    local minProj, maxProj = math.huge, -math.huge
    for _, pt in ipairs(points) do
        local proj = pt.x * axis.x + pt.y * axis.y
        if proj < minProj then minProj = proj end
        if proj > maxProj then maxProj = proj end
    end

    local buffer = 3
    return minProj - buffer, maxProj + buffer
end

function WorldManager.computeSliceInfo(boundary, playerBody, playerShape, contact)
    local points = {boundary.body:getWorldPoints(boundary.shape:getPoints())}
    local p1 = {x=points[1], y=points[2]}
    local p2 = {x=points[3], y=points[4]}
    local p3 = {x=points[5], y=points[6]}
    local p4 = {x=points[7], y=points[8]}
    
    local dx12 = p2.x - p1.x
    local dy12 = p2.y - p1.y
    local len12 = math.sqrt(dx12*dx12 + dy12*dy12)
    local dx23 = p3.x - p2.x
    local dy23 = p3.y - p2.y
    local len23 = math.sqrt(dx23*dx23 + dy23*dy23)
    
    local lengthAxis, length, width
    if len12 > len23 then
        lengthAxis = {x = dx12/len12, y = dy12/len12}
        length = len12
        width = len23
    else
        lengthAxis = {x = dx23/len23, y = dy23/len23}
        length = len23
        width = len12
    end
    
    local boundaryMin, boundaryMax = math.huge, -math.huge
    for i = 1, #points, 2 do
        local proj = points[i]*lengthAxis.x + points[i+1]*lengthAxis.y
        if proj < boundaryMin then boundaryMin = proj end
        if proj > boundaryMax then boundaryMax = proj end
    end
    
    local overlapStart, overlapEnd = WorldManager.getContactOverlapOnBoundary(boundary, playerBody, contact)
    if not overlapStart or overlapEnd <= overlapStart + 5 then
        return nil
    end
    
    overlapStart = math.max(boundaryMin, overlapStart)
    overlapEnd = math.min(boundaryMax, overlapEnd)
    if overlapEnd <= overlapStart + 5 then return nil end
    
    local MIN_SLICE = 5
    local leftLen = overlapStart - boundaryMin
    local middleLen = overlapEnd - overlapStart
    local rightLen = boundaryMax - overlapEnd
    
    local pieces = {}
    if leftLen >= MIN_SLICE then
        table.insert(pieces, {type="static", start=boundaryMin, finish=overlapStart, length=leftLen})
    end
    if middleLen >= MIN_SLICE then
        table.insert(pieces, {type="dynamic", start=overlapStart, finish=overlapEnd, length=middleLen})
    end
    if rightLen >= MIN_SLICE then
        table.insert(pieces, {type="static", start=overlapEnd, finish=boundaryMax, length=rightLen})
    end
    
    if #pieces == 0 then return nil end
    
    local isLengthAxisW = math.abs(length - boundary.w) < 0.1
    
    local centerX, centerY = boundary.body:getPosition()
    local boundaryCenterProj = (boundaryMin + boundaryMax) / 2
    local cat, mask, group = boundary.fixture:getFilterData()
    
    return {
        pieces = pieces,
        lengthAxis = lengthAxis,
        width = width,
        angle = boundary.body:getAngle(),
        isLengthAxisW = isLengthAxisW,
        originalW = boundary.w,
        originalH = boundary.h,
        friction = boundary.fixture:getFriction(),
        restitution = boundary.fixture:getRestitution(),
        categories = cat,
        mask = mask,
        group = group,
        centerX = centerX,
        centerY = centerY,
        boundaryMin = boundaryMin,
        boundaryMax = boundaryMax,
        boundaryCenterProj = boundaryCenterProj,
        overlapStart = overlapStart, -- Saved for effect placement
        overlapEnd = overlapEnd     -- Saved for effect placement
    }
end

function WorldManager.performSlice(boundary, sliceInfo)
    local EffectsSystem = require("effects")
    local Entities = require("entities")
    
    local axis = sliceInfo.lengthAxis
    local perpX, perpY = -axis.y, axis.x
    local halfW = sliceInfo.width / 2

    -- ==== FIX 2: Create damage effects exactly along the two real slicing areas ====
    local function drawCutEffect(p)
        local cutCenterX = sliceInfo.centerX + axis.x * (p - sliceInfo.boundaryCenterProj)
        local cutCenterY = sliceInfo.centerY + axis.y * (p - sliceInfo.boundaryCenterProj)
        local x1 = cutCenterX - perpX * halfW
        local y1 = cutCenterY - perpY * halfW
        local x2 = cutCenterX + perpX * halfW
        local y2 = cutCenterY + perpY * halfW
        EffectsSystem.createDamageEffect(x1, y1, x2, y2)
    end

    if sliceInfo.overlapStart then drawCutEffect(sliceInfo.overlapStart) end
    if sliceInfo.overlapEnd then drawCutEffect(sliceInfo.overlapEnd) end
    
    local newBoundaries = {}
    
    for _, piece in ipairs(sliceInfo.pieces) do
        local pieceCenterProj = (piece.start + piece.finish) / 2
        local offset = pieceCenterProj - sliceInfo.boundaryCenterProj
        local newCenterX = sliceInfo.centerX + axis.x * offset
        local newCenterY = sliceInfo.centerY + axis.y * offset
        
        local newW, newH
        if sliceInfo.isLengthAxisW then
            newW = piece.length
            newH = sliceInfo.originalH
        else
            newW = sliceInfo.originalW
            newH = piece.length
        end
        
        if piece.type == "dynamic" then
            -- ==== CONVERT TO ENTITY BOX ====
            -- ==== FIX 1: Shave size very slightly so it doesn't jam inside static pieces ====
            local padding = 1.5
            local boxW = math.max(1, newW - padding)
            local boxH = math.max(1, newH - padding)
            
            local density = 1.0
            local newBox = Entities.createBox(newCenterX, newCenterY, boxW, boxH, sliceInfo.angle, density, sliceInfo.friction)
            
            if newBox and newBox.fixture then
                newBox.fixture:setRestitution(sliceInfo.restitution)
                if sliceInfo.categories then
                    newBox.fixture:setFilterData(sliceInfo.categories, sliceInfo.mask, sliceInfo.group)
                end
            end
        else
            -- ==== KEEP AS STATIC BOUNDARY ====
            local newBody = love.physics.newBody(WorldManager.world, newCenterX, newCenterY, "static")
            local newShape = love.physics.newRectangleShape(newW, newH)
            local newFixture = love.physics.newFixture(newBody, newShape, 0)
            
            newFixture:setFriction(sliceInfo.friction)
            newFixture:setRestitution(sliceInfo.restitution)
            
            if sliceInfo.categories then
                newFixture:setFilterData(sliceInfo.categories, sliceInfo.mask, sliceInfo.group)
            end
            
            newBody:setAngle(sliceInfo.angle)
            
            local newBoundary = {
                body = newBody, shape = newShape, fixture = newFixture,
                w = newW, h = newH, type = "boundary"
            }
            table.insert(WorldManager.boundaries, newBoundary)
            table.insert(newBoundaries, newBoundary)
        end
    end
    
    -- ==== FIX 2 CONTINUED: Generate particle sparks explicitly at the cut regions ====
    local function spawnSparksAtCut(p)
        local cutCenterX = sliceInfo.centerX + axis.x * (p - sliceInfo.boundaryCenterProj)
        local cutCenterY = sliceInfo.centerY + axis.y * (p - sliceInfo.boundaryCenterProj)
        for i = 1, 10 do
            local t = love.math.random() * 2 - 1 -- Span across full edge width
            local sparkX = cutCenterX + perpX * halfW * t
            local sparkY = cutCenterY + perpY * halfW * t
            local angle = love.math.random() * math.pi * 2
            local speed = love.math.random(50, 150)
            local vx = math.cos(angle) * speed
            local vy = math.sin(angle) * speed - 30
            EffectsSystem.createParticle(sparkX, sparkY, vx, vy, 18, 350, 2.5, "orangeSpark")
        end
    end

    if sliceInfo.overlapStart then spawnSparksAtCut(sliceInfo.overlapStart) end
    if sliceInfo.overlapEnd then spawnSparksAtCut(sliceInfo.overlapEnd) end
    
    return newBoundaries
end

function WorldManager.removeBoundary(boundary)
    if not boundary or not boundary.body then return end
    for i, b in ipairs(WorldManager.boundaries) do
        if b == boundary then
            table.remove(WorldManager.boundaries, i)
            break
        end
    end
    local okFire, Fire = pcall(require, "fire")
    if okFire and Fire and Fire.onBodyDestroyedOrSplit and boundary.body and not boundary.body:isDestroyed() then
        Fire.onBodyDestroyedOrSplit(boundary.body)
    end
    if boundary.body and not boundary.body:isDestroyed() then
        boundary.body:destroy()
    end
end

function WorldManager.sliceBoundaryAtPlayer(player)
    if not player or not player.body then return end
    local boundary, contact = WorldManager.getCollidingBoundary(player)
    if not boundary then return end
    
    local sliceInfo = WorldManager.computeSliceInfo(boundary, player.body, player.shape, contact)
    if not sliceInfo then return end
    
    WorldManager.performSlice(boundary, sliceInfo)
    WorldManager.removeBoundary(boundary)
end

return WorldManager