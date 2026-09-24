-- whale.lua
local Whale = {
    whales = {},
    nextId = 1
}

local whaleTypes = {
    gentle = {
        name = "Blue Whale",
        color = {0.15, 0.25, 0.45},
        bellyColor = {0.3, 0.4, 0.6},
        speed = 800,
        turnSpeed = 1.5,
        mass = 400,
        health = 50000,
        damage = 0,
        friendly = true,
        w = 120, h = 40,
        tailSize = 25,
        dorsalSize = 5
    },
    aggressive = {
        name = "Orca",
        color = {0.05, 0.05, 0.08},
        bellyColor = {0.9, 0.9, 0.95},
        speed = 700,
        turnSpeed = 4.0,
        mass = 60,
        health = 25000,
        damage = 30,
        friendly = false,
        w = 70, h = 25,
        tailSize = 18,
        dorsalSize = 20
    },
    baby = {
        name = "Calf",
        color = {0.25, 0.35, 0.55},
        bellyColor = {0.4, 0.5, 0.7},
        speed = 300,
        turnSpeed = 2.5,
        mass = 8,
        health = 10000,
        damage = 0,
        friendly = true,
        w = 40, h = 15,
        tailSize = 10,
        dorsalSize = 3
    }
}

function Whale.create(x, y, whaleType)
    local WorldManager = require("world_manager")
    local typeData = whaleTypes[whaleType] or whaleTypes.gentle
    
    local body = love.physics.newBody(WorldManager.world, x, y, "dynamic")
    local shape = love.physics.newRectangleShape(typeData.w * 0.8, typeData.h * 0.8)
    local fixture = love.physics.newFixture(body, shape, typeData.mass)
    
    fixture:setFriction(0.1)
    fixture:setRestitution(0.2)
    body:setLinearDamping(1.2)
    body:setAngularDamping(0.3)
    
    local whale = {
        id = Whale.nextId,
        type = "whale",
        whaleType = whaleType,
        body = body,
        shape = shape,
        fixture = fixture,
        data = typeData,
        
        ropeIds = {},
        
        health = typeData.health,
        maxHealth = typeData.health,
        damageFlash = 0,
        
        animPhase = love.math.random() * math.pi * 2,
        tailAngle = 0,
        inWater = true,
        blowholeTimer = 0,
        
        state = "idle",
        dead = false,
        stateTimer = love.math.random(2, 5),
        path = {},
        pathIndex = 1,
        targetX = x,
        targetY = y,
        waypointTimer = 0,
        lastAttackTime = 0,
        attackCooldown = 1.5,
        driveDirection = 1,
        
        stuckTimer = 0,
        lastDistanceToTarget = nil
    }
    
    table.insert(Whale.whales, whale)
    Whale.nextId = Whale.nextId + 1
    return whale
end

function Whale.generatePath(x1, y1, x2, y2, waterArea)
    local path = {}
    local dx = x2 - x1
    local dy = y2 - y1
    local dist = math.sqrt(dx^2 + dy^2)

    if dist < 150 then
        table.insert(path, {x = x2, y = y2})
        return path
    end

    local numWaypoints = love.math.random(1, 2)
    for i = 1, numWaypoints do
        local t = i / (numWaypoints + 1)
        local bx = x1 + dx * t
        local by = y1 + dy * t
        
        local perpX = -dy / dist
        local perpY = dx / dist
        local offset = love.math.random(-150, 150)
        
        local wx = bx + perpX * offset
        local wy = by + perpY * offset
        
        if waterArea then
            wx = math.max(waterArea.x + 40, math.min(waterArea.x + waterArea.w - 40, wx))
            wy = math.max(waterArea.y + 40, math.min(waterArea.y + waterArea.h - 40, wy))
        end
        
        table.insert(path, {x = wx, y = wy})
    end
    
    table.insert(path, {x = x2, y = y2})
    return path
end

-- Smart path generator that avoids obstacles using recursive raycasting & LOS checking
function Whale.generateSmartPath(x1, y1, x2, y2, waterArea, whale, depth)
    depth = depth or 0
    local MAX_DEPTH = 3  -- Lowered slightly to prevent insane recursive loops
    local path = {}
    
    local function distance(x1, y1, x2, y2)
        local dx = x2 - x1
        local dy = y2 - y1
        return math.sqrt(dx*dx + dy*dy)
    end
    
    if distance(x1, y1, x2, y2) < 0.1 then
        table.insert(path, {x = x2, y = y2})
        return path
    end
    
    local hitPoint = nil
    local hitNormal = nil
    
    local function rayCallback(fixture, x, y, xn, yn, fraction)
        local body = fixture:getBody()
        if fixture == whale.fixture then return -1 end
        if fixture:isSensor() then return -1 end
        if body:getType() == "dynamic" then return -1 end
        
        hitPoint = {x = x, y = y}
        hitNormal = {x = xn, y = yn}
        return fraction
    end
    
    local WorldManager = require("world_manager")
    WorldManager.world:rayCast(x1, y1, x2, y2, rayCallback)
    
    if not hitPoint then
        -- Direct path is clear
        table.insert(path, {x = x2, y = y2})
        return path
    end
    
    if depth >= MAX_DEPTH then
        table.insert(path, {x = x2, y = y2})
        return path
    end
    
    local perpX = -hitNormal.y
    local perpY = hitNormal.x
    local margin = (whale and whale.data.w or 60) * 1.0
    
    -- Push the base point out along the normal to prevent waypoints embedding inside walls
    local pushOut = margin * 0.5
    local basePoint = {
        x = hitPoint.x + hitNormal.x * pushOut,
        y = hitPoint.y + hitNormal.y * pushOut
    }
    
    local waypointLeft = {x = basePoint.x + perpX * margin, y = basePoint.y + perpY * margin}
    local waypointRight = {x = basePoint.x - perpX * margin, y = basePoint.y - perpY * margin}
    
    if waterArea then
        local pad = 30
        waypointLeft.x = math.max(waterArea.x + pad, math.min(waterArea.x + waterArea.w - pad, waypointLeft.x))
        waypointLeft.y = math.max(waterArea.y + pad, math.min(waterArea.y + waterArea.h - pad, waypointLeft.y))
        waypointRight.x = math.max(waterArea.x + pad, math.min(waterArea.x + waterArea.w - pad, waypointRight.x))
        waypointRight.y = math.max(waterArea.y + pad, math.min(waterArea.y + waterArea.h - pad, waypointRight.y))
    end
    
    -- Check Line of Sight (LOS) for immediate viable paths
    local function hasClearPath(sx, sy, ex, ey)
        -- 🐛 FIX 2: Protect the secondary LOS raycasts too
        if distance(sx, sy, ex, ey) < 0.1 then return true end
        
        local clear = true
        WorldManager.world:rayCast(sx, sy, ex, ey, function(f)
            if f == whale.fixture or f:isSensor() or f:getBody():getType() == "dynamic" then return -1 end
            clear = false
            return 0 
        end)
        return clear
    end

    local leftClear = hasClearPath(waypointLeft.x, waypointLeft.y, x2, y2)
    local rightClear = hasClearPath(waypointRight.x, waypointRight.y, x2, y2)
    
    local chosen = nil
    if leftClear and not rightClear then
        chosen = waypointLeft
    elseif rightClear and not leftClear then
        chosen = waypointRight
    else
        -- If both clear or both blocked, pick the shortest total distance
        local leftDist = distance(x1, y1, waypointLeft.x, waypointLeft.y) + distance(waypointLeft.x, waypointLeft.y, x2, y2)
        local rightDist = distance(x1, y1, waypointRight.x, waypointRight.y) + distance(waypointRight.x, waypointRight.y, x2, y2)
        chosen = leftDist < rightDist and waypointLeft or waypointRight
    end
    
    local firstHalf = Whale.generateSmartPath(x1, y1, chosen.x, chosen.y, waterArea, whale, depth + 1)
    local secondHalf = Whale.generateSmartPath(chosen.x, chosen.y, x2, y2, waterArea, whale, depth + 1)
    
    for i = 1, #firstHalf - 1 do table.insert(path, firstHalf[i]) end
    for i = 1, #secondHalf do table.insert(path, secondHalf[i]) end
    
    return path
end

function Whale.update(dt, player, entities)
    local Water = require("water")
    local EffectsSystem = require("effects")
    
    -- Unified player status verification
    local playerValid = player and player.body and not player.body:isDestroyed() and (not player.health or player.health > 0)
    
    for i = #Whale.whales, 1, -1 do
        local w = Whale.whales[i]
        if w.dead then return end
        if not w.body or w.body:isDestroyed() then
            table.remove(Whale.whales, i)
            goto continue
        end
        
        if w.damageFlash > 0 then w.damageFlash = math.max(0, w.damageFlash - dt) end
        
        local wx, wy = w.body:getPosition()
        local vx, vy = w.body:getLinearVelocity()
        local waterArea = Water.isPointInWater(wx, wy)

        -- Always apply buoyancy and water drag (dead or alive)
        if waterArea then
            local mass = w.body:getMass()
            local gravity = 9.81 * 64
            w.body:applyForce(0, -mass * gravity)
            w.body:applyForce(-vx * 0.2, -vy * 0.2)
        end
        
        w.inWater = (waterArea ~= nil)
        
        -- Only animate if alive
        if not w.dead then
            local currentSpeed = math.sqrt(vx^2 + vy^2)
            local wagSpeed = math.max(2, currentSpeed * 0.02)
            w.animPhase = w.animPhase + (dt * wagSpeed)
            w.tailAngle = math.sin(w.animPhase) * 0.4
        else
            -- Dead: tail slowly settles
            w.tailAngle = w.tailAngle * 0.95
        end
        
        if w.blowholeTimer > 0 then w.blowholeTimer = w.blowholeTimer - dt end

        if w.inWater and not w.dead then
            Whale.updateAI(w, dt, player, waterArea)
        end
        
        -- Attack only if whale is alive, aggressive, and player is valid/alive
        if not w.dead and playerValid and not w.data.friendly then
            local px, py = player.body:getPosition()
            local dist = math.sqrt((wx-px)^2 + (wy-py)^2)
            if dist < (w.data.w/2 + 20) then
                local currentTime = love.timer.getTime()
                if currentTime - w.lastAttackTime >= w.attackCooldown then
                    require("entities").applyDamage(player, w.data.damage)
                    w.lastAttackTime = currentTime
                    EffectsSystem.createDamageEffect(px, py, px, py, true)
                end
            end
        end
        ::continue::
    end
end

function Whale.updateAI(whale, dt, player, waterArea)
    if whale.dead then return end
    
    local WorldManager = require("world_manager")
    local Water = require("water")
    local wx, wy = whale.body:getPosition()
    
    -- Check if player is completely valid and alive
    local playerValid = player and player.body and not player.body:isDestroyed() and (not player.health or player.health > 0)
    
    local px, py = wx, wy
    if playerValid then
        px, py = player.body:getPosition()
    end
    local distToPlayer = math.sqrt((wx-px)^2 + (wy-py)^2)

    -- ========== STATE TRANSITIONS ==========
    if not whale.data.friendly and playerValid and distToPlayer < 600 then
        if Water.isPointInWater(px, py) then
            if whale.state ~= "hunt" or (whale.stateTimer and whale.stateTimer <= 0) then
                whale.state = "hunt"
                whale.path = Whale.generateSmartPath(wx, wy, px, py, waterArea, whale)
                whale.pathIndex = 1
                whale.stateTimer = 1.0
                whale.driveDirection = love.math.random() > 0.5 and 1 or -1
                whale.stuckTimer = 0
                whale.lastDistanceToTarget = nil
            end
        elseif whale.state == "hunt" then
            whale.state = "idle"
            whale.stateTimer = love.math.random(2, 5)
        end
    else
        if whale.state == "hunt" then
            whale.state = "idle"
            whale.stateTimer = love.math.random(2, 5)
        end
    end

    if whale.state == "idle" and whale.stateTimer then
        whale.stateTimer = whale.stateTimer - dt
    elseif whale.state == "hunt" and whale.stateTimer then
        whale.stateTimer = whale.stateTimer - dt
    end

    -- ========== IDLE ==========
    if whale.state == "idle" then
        local currentAngle = whale.body:getAngle()
        -- Dynamic Stabilizer: targets 0 (right) or PI (left) based on closest orientation
        local targetAngle = (math.cos(currentAngle) < 0) and math.pi or 0
        local angleError = (targetAngle - currentAngle + math.pi) % (2 * math.pi) - math.pi
        
        local stabilizerTorque = angleError * whale.body:getMass() * 8
        whale.body:applyTorque(stabilizerTorque)
        
        local angVel = whale.body:getAngularVelocity()
        whale.body:applyTorque(-angVel * whale.body:getMass() * 0.5)

        if whale.stateTimer <= 0 then
            whale.state = "wander"
            whale.stateTimer = nil
            whale.driveDirection = love.math.random() > 0.5 and 1 or -1

            if waterArea then
                local padding = whale.data.w
                local tx = love.math.random(waterArea.x + padding, waterArea.x + waterArea.w - padding)
                local ty = love.math.random(waterArea.y + padding, waterArea.y + waterArea.h - padding)
                whale.path = Whale.generateSmartPath(wx, wy, tx, ty, waterArea, whale)
                whale.pathIndex = 1
                whale.stuckTimer = 0
                whale.lastDistanceToTarget = nil
            end
        end
        return
    end

-- ========== PATH FOLLOWING (wander or hunt) ==========
    if not whale.path or whale.pathIndex > #whale.path then
        whale.state = "idle"
        whale.stateTimer = love.math.random(3, 8)
        return
    end

    local target = whale.path[whale.pathIndex]
    local dx = target.x - wx
    local dy = target.y - wy
    local distToTarget = math.sqrt(dx*dx + dy*dy)

    local arrivalDist = whale.data.w * 0.4
    if distToTarget < arrivalDist then
        whale.pathIndex = whale.pathIndex + 1
        if whale.pathIndex > #whale.path then
            whale.state = "idle"
            whale.stateTimer = love.math.random(3, 8)
            return
        end
        target = whale.path[whale.pathIndex]
        dx = target.x - wx
        dy = target.y - wy
        distToTarget = math.sqrt(dx*dx + dy*dy)
        whale.stuckTimer = 0
        whale.lastDistanceToTarget = nil
    end

    -- ========== STUCK DETECTION ==========
    if whale.lastDistanceToTarget == nil then
        whale.lastDistanceToTarget = distToTarget
    else
        if distToTarget >= whale.lastDistanceToTarget - 5 then
            whale.stuckTimer = whale.stuckTimer + dt
            if whale.stuckTimer > 3.0 then
                if whale.state == "hunt" and playerValid then
                    whale.path = Whale.generateSmartPath(wx, wy, px, py, waterArea, whale)
                else
                    local padding = whale.data.w
                    local tx = love.math.random(waterArea.x + padding, waterArea.x + waterArea.w - padding)
                    local ty = love.math.random(waterArea.y + padding, waterArea.y + waterArea.h - padding)
                    whale.path = Whale.generateSmartPath(wx, wy, tx, ty, waterArea, whale)
                end
                whale.pathIndex = 1
                whale.stuckTimer = 0
                whale.lastDistanceToTarget = nil
                return
            end
        else
            whale.stuckTimer = 0
        end
        whale.lastDistanceToTarget = distToTarget
    end

    -- ========== STEERING TOWARD TARGET ==========
    local desiredAngle = math.atan2(dy, dx)
    local currentAngle = whale.body:getAngle()
    local angleDiff = (desiredAngle - currentAngle + math.pi) % (2 * math.pi) - math.pi

    local steeringTorque = angleDiff * whale.data.turnSpeed * whale.body:getMass() * 8
    whale.body:applyTorque(steeringTorque)

    -- ========== DYNAMIC ANGLE STABILIZER (keep horizontal) ==========
    local targetStabilizeAngle = (math.cos(currentAngle) < 0) and math.pi or 0
    local stabilizerError = (targetStabilizeAngle - currentAngle + math.pi) % (2 * math.pi) - math.pi
    local stabilizerTorque = stabilizerError * whale.body:getMass() * 5
    whale.body:applyTorque(stabilizerTorque)

    -- ========== ANGULAR DAMPING ==========
    local angVel = whale.body:getAngularVelocity()
    whale.body:applyTorque(-angVel * whale.body:getMass() * 0.6)

    -- ========== OBSTACLE AVOIDANCE ==========
    local lookAhead = whale.data.w * 1.2
    local rayEndX = wx + math.cos(currentAngle) * lookAhead
    local rayEndY = wy + math.sin(currentAngle) * lookAhead

    local hitFraction = 1.0
    local hitNormalX, hitNormalY = 0, 0

    local function rayCallback(fixture, x, y, xn, yn, fraction)
        if fixture:isSensor() or fixture:getBody():getType() == "dynamic" then return -1 end
        if fraction < hitFraction then
            hitFraction = fraction
            hitNormalX, hitNormalY = xn, yn
        end
        return fraction
    end

    WorldManager.world:rayCast(wx, wy, rayEndX, rayEndY, rayCallback)

    local finalAngle = desiredAngle
    if hitFraction < 1.0 then
        local avoidAngle = math.atan2(hitNormalY, hitNormalX)
        finalAngle = avoidAngle + (whale.driveDirection * math.pi/2)
        local avoidAngleDiff = (finalAngle - currentAngle + math.pi) % (2 * math.pi) - math.pi
        whale.body:applyTorque(avoidAngleDiff * whale.data.turnSpeed * whale.body:getMass() * 10)
    end

    -- ========== THRUST ==========
    local finalAngleDiff = (finalAngle - currentAngle + math.pi) % (2 * math.pi) - math.pi
    local alignment = math.cos(finalAngleDiff)
    if alignment > 0.2 then
        local thrust = whale.data.speed * whale.body:getMass()
        local multiplier = (whale.state == "hunt") and 1.3 or 0.6
        local forwardX = math.cos(currentAngle)
        local forwardY = math.sin(currentAngle)
        whale.body:applyForce(forwardX * thrust * alignment * multiplier,
                              forwardY * thrust * alignment * multiplier)
    else
        local vx, vy = whale.body:getLinearVelocity()
        whale.body:applyForce(-vx * 0.3, -vy * 0.3)
    end
end

function Whale.draw(debugMode)
    for _, w in ipairs(Whale.whales) do
        if w.body and not w.body:isDestroyed() then
            local x, y = w.body:getPosition()
            local angle = w.body:getAngle()
            local data = w.data
            
            love.graphics.push()
            love.graphics.translate(x, y)
            love.graphics.rotate(angle)
            
            -- Keep the whale perfectly upright when steering left by flipping the Y-axis.
            if math.cos(angle) < 0 then
                love.graphics.scale(1, -1)
            end
            
            local hw, hh = data.w/2, data.h/2
            if w.dead then
                love.graphics.setColor(0.3, 0.3, 0.4, 0.8)  -- pale grey-blue
            else
                if w.damageFlash > 0 then love.graphics.setColor(1, 0.4, 0.4) else love.graphics.setColor(data.color) end
            end

            -- Tail (Fluke)
            love.graphics.push()
            love.graphics.translate(-hw + 5, 0)
            love.graphics.rotate(w.tailAngle)
            love.graphics.polygon("fill", 0, -hh*0.4, -data.tailSize*0.8, -hh*0.15, -data.tailSize*0.8, hh*0.15, 0, hh*0.4)
            love.graphics.polygon("fill", -data.tailSize*0.6, 0, -data.tailSize*1.5, -hh*1.2, -data.tailSize*1.2, 0, -data.tailSize*1.5, hh*1.2)
            love.graphics.pop()
            
            -- Back Pectoral
            love.graphics.setColor(data.color[1]*0.6, data.color[2]*0.6, data.color[3]*0.6)
            love.graphics.polygon("fill", hw*0.3, 0, 0, hh*1.5, hw*0.1, 0)

            -- Body
            if w.damageFlash > 0 then love.graphics.setColor(1, 0.4, 0.4) else love.graphics.setColor(data.color) end
            local bodyPoly = {}
            local segments = 10
            for i = 0, segments do
                local t = i/segments
                table.insert(bodyPoly, hw - (t*data.w))
                table.insert(bodyPoly, -hh * math.sin(t*math.pi) * (1-t*0.3))
            end
            for i = segments, 0, -1 do
                local t = i/segments
                table.insert(bodyPoly, hw - (t*data.w))
                table.insert(bodyPoly, hh * math.sin(t*math.pi) * (1-t*0.5))
            end
            love.graphics.polygon("fill", bodyPoly)

            -- Belly
            if w.damageFlash <= 0 then
                love.graphics.setColor(data.bellyColor)
                local bellyPoly = {}
                for i = 0, segments do
                    local t = i/segments
                    table.insert(bellyPoly, hw - (t*data.w))
                    table.insert(bellyPoly, hh * math.sin(t*math.pi) * (1-t*0.5))
                end
                for i = segments, 0, -1 do
                    local t = i/segments
                    table.insert(bellyPoly, hw - (t*data.w))
                    table.insert(bellyPoly, hh * 0.2 * math.sin(t*math.pi))
                end
                love.graphics.polygon("fill", bellyPoly)
            end

            -- Dorsal & Front Pectoral
            love.graphics.setColor(data.color)
            love.graphics.polygon("fill", -hw*0.1, -hh*0.9, -hw*0.3-data.dorsalSize, -hh-data.dorsalSize, -hw*0.4, -hh*0.8)
            love.graphics.polygon("fill", hw*0.4, 0, hw*0.1, hh*1.8, hw*0.2, 0)

            -- Eye
            love.graphics.setColor(0, 0, 0)
            love.graphics.circle("fill", hw*0.75, -hh*0.2, 2)
            
            love.graphics.pop()

            if debugMode then
                love.graphics.setColor(1, 1, 1)
                local timerText = ""
                if w.stateTimer ~= nil then
                    timerText = string.format(" (%.1fs)", w.stateTimer)
                else
                    timerText = " (∞)"
                end
                love.graphics.print(w.state .. timerText, x - 30, y - hh - 20)
                
                if w.path and #w.path > 0 then
                    love.graphics.setColor(1, 1, 0, 0.6)
                    local prevX, prevY = x, y
                    for i = w.pathIndex, #w.path do
                        local pt = w.path[i]
                        love.graphics.line(prevX, prevY, pt.x, pt.y)
                        love.graphics.circle("fill", pt.x, pt.y, 4)
                        prevX, prevY = pt.x, pt.y
                    end
                end
                
                local pct = w.health / w.maxHealth
                love.graphics.setColor(1, 0, 0)
                love.graphics.rectangle("fill", x - 25, y - hh - 10, 50, 4)
                love.graphics.setColor(0, 1, 0)
                love.graphics.rectangle("fill", x - 25, y - hh - 10, 50 * pct, 4)
            end
        end
    end
end

function Whale.damage(whale, amount)
    if not whale or not whale.body or whale.body:isDestroyed() then return end
    if whale.dead then return end  -- dead whales can't be damaged further
    whale.health = whale.health - amount
    whale.damageFlash = 0.3
    if whale.health <= 0 then
        whale.health = 0
        Whale.kill(whale)
    end
end

function Whale.kill(whale)
    if not whale or whale.dead then return end
    whale.dead = true
    whale.state = "dead"

    -- Remove all ropes attached to this whale
    local RopeSystem = require("rope")
    RopeSystem.destroyAllForObject(whale)

    -- Reduce mass to 10% of original so it floats easily
    local oldMass = whale.data.mass
    local newMass = math.max(1, oldMass * 0.1)   -- at least 1 unit of mass
    local area = whale.data.w * whale.data.h
    local newDensity = newMass / area

    -- Replace the fixture with a lighter one
    local shape = whale.shape
    local friction = whale.fixture:getFriction()
    local restitution = whale.fixture:getRestitution()

    whale.fixture:destroy()
    whale.fixture = love.physics.newFixture(whale.body, shape, newDensity)
    whale.fixture:setFriction(friction)
    whale.fixture:setRestitution(restitution)

    -- Reset damping – dead whales should drift to a stop naturally
    whale.body:setLinearDamping(0.5)
    whale.body:setAngularDamping(0.5)

    -- Optional: give it a small random push so it doesn't stay frozen
    -- (but not necessary)

    -- Create a splash effect
    local wx, wy = whale.body:getPosition()
    require("water").createSplash(wx, wy, 150)
end

function Whale.destroy(whale)
    if not whale or not whale.body then return end
    
    local RopeSystem = require("rope")
    RopeSystem.destroyAllForObject(whale)
    
    local wx, wy = whale.body:getPosition()
    require("water").createSplash(wx, wy, 200)
    local okFire, Fire = pcall(require, "fire")
    if okFire and Fire and Fire.onBodyDestroyedOrSplit and not whale.body:isDestroyed() then
        Fire.onBodyDestroyedOrSplit(whale.body)
    end
    whale.body:destroy()
    
    for i, w in ipairs(Whale.whales) do 
        if w == whale then 
            table.remove(Whale.whales, i) 
            break 
        end 
    end
end

function Whale.clear()
    for _, w in ipairs(Whale.whales) do if w.body then w.body:destroy() end end
    Whale.whales = {}
end

function Whale.getAll()
    return Whale.whales
end

return Whale