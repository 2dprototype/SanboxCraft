-- main.lua (FIXED - added camera position initialization and proper chunk loading)
local Config = require("config")
local Camera = require("camera")
local WorldManager = require("world_manager")
local RopeSystem = require("rope")
local EffectsSystem = require("effects")
local Entities = require("entities")
local Water = require("water")
local Whale = require("whale")
local b2debugDraw = require("b2debugDraw")
local Vegetation = require("vegetation")
local Fire = require("fire")
local Trees = require("trees")

local game = { debugMode = false, state = "playing" }
local debugDrawEnabled = false
local cameraInstructions = {
    "F1: Follow Player", "F2: Object", "F3: Free Move",
    "Wheel or -/+: Zoom", "WASD: Free Move", "Backspace: Reset Zoom",
    "F5: Toggle Debug Mode", "SPACE: Grab/Release Object",
    "E: Grab Enemy", "SHIFT: Connect two objects & detach",
    "G/T/N/R: Grenade/TNT/Nuke/Radium",
    "F: Put / Intensify Fire",
    "Z: Slice / C: Chop Tree"
}

function love.load()
    WorldManager.init()
    Fire.init()
    
    -- Instantiate Scene Objects
    -- Entities.createPlayer(-820, 0)
    -- Entities.createPlayer(-1135, 1505)
    -- Entities.createPlayer(-1385, 800)
    Entities.createPlayer(-500, 200)
    
    -- Populating Physical Rigid Props
    Entities.createBox(-800, 570, 8, 80, 0, 2, 0.2)
    Entities.createBox(-840, 570, 8, 80, 0, 2, 0.2)
    Entities.createBox(-820, 300, 80, 30, 0, 0.6, 0.2)
    Entities.createBall(260, 430, 12.5, -700, 2, 0.5)
    Entities.createBall(-390, 150, 25, 0, 1, 0.1)
    
    
    Entities.createBox(-1250, 700, 50, 50, 0, 100, 5, "", 1000000000)
    

    for r = 0, 3 do
        for c = 0, 2 do
            Entities.createBox(-1600 + (c * 30), 800 - (r * 30), 28, 28, 0, 0.5, 0.2, string.format("Grid%d%d", c, r), 600)
        end
    end
    
    -- Add more boxes to make the map interesting
    -- Entities.createBox(-900, 400, 20, 20, 0, 1.5, 0.3, "box1", 1000)
    -- Entities.createBox(-750, 350, 15, 40, 0.5, 1.2, 0.2, "box2", 1000)
    -- Entities.createBox(-1000, 600, 25, 25, 0, 2.0, 0.1, "box3",  1000)
    -- Entities.createBox(-1100, 650, 12, 60, 0.3, 0.8, 0.4, "box4", 1000)
    
    -- Add more balls
    Entities.createBall(-1590, 1000, 28, 0, 0.1, 0.8)
    Entities.createBall(-1300, 1000, 30, 0, 776, 0.8)
    
    -- Enemies
    -- Entities.createEnemy(-8900, -520, 12.5, 25, 0)
    -- Entities.createEnemy(-8850, -550, 15, 20, 0)
    
    -- -- Populating Static Ground Structures
    -- WorldManager.createBoundary(320, 500, 600, 10, 0)
    -- WorldManager.createBoundary(-100, 350, 600, 10, 0.3)
    -- WorldManager.createBoundary(-485, 261, 200, 10, 0)
    -- WorldManager.createBoundary(-265, 589, 600, 10, -0.3)
    -- WorldManager.createBoundary(-700, 605, 300, 10, 0)
    -- WorldManager.createBoundary(-700, 678, 300, 10, 0)
    -- WorldManager.createBoundary(-1260, 820, 300, 10, 0)
    -- WorldManager.createBoundary(-1540, 825, 180, 10, 0)
    -- WorldManager.createBoundary(-1565, 1005, 250, 10, 0)
    -- WorldManager.createBoundary(-1300, 1005, 250, 10, 0)
    -- WorldManager.createBoundary(-1685, 905, 10, 200, 0)
    -- WorldManager.createBoundary(-980, 749, 300, 10, -0.5)
    -- WorldManager.createBoundary(-440, 620, 80, 5, 0.4)
    
    -- Populating Static Ground Structures
    WorldManager.createBoundary(320, 500, 600, 10, 0)
    WorldManager.createBoundary(-100, 350, 600, 10, 0.3)
    local shelf1  = WorldManager.createBoundary(-485, 261, 200, 10, 0)
    WorldManager.createBoundary(-265, 589, 600, 10, -0.3)
    WorldManager.createBoundary(-700, 605, 300, 10, 0)
    WorldManager.createBoundary(-700, 678, 300, 10, 0)
    WorldManager.createBoundary(-1260, 820, 300, 10, 0)
    WorldManager.createBoundary(-1540, 825, 180, 10, 0)
    WorldManager.createBoundary(-1565, 1005, 250, 10, 0)
    WorldManager.createBoundary(-1300, 1005, 250, 10, 0)
    WorldManager.createBoundary(-1685, 905, 10, 200, 0) 
    WorldManager.createBoundary(-980, 749, 300, 10, -0.5)
    WorldManager.createBoundary(-440, 620, 80, 5, 0.4)

    
    -- new
    WorldManager.createBoundary(-1885, 905, 10, 200, 0)
    WorldManager.createBoundary(-1785, 1005, 210, 10, 0)
    
    WorldManager.createBoundary(-1885, 1305, 10, 600, 0)
    WorldManager.createBoundary(-1485, 1605, 810, 10, 0)
    WorldManager.createBoundary(-1085, 1305, 10, 600, 0)
    
    WorldManager.createBoundary(-885, 1605, 410, 10, 0)
    WorldManager.createBoundary(-285, 1605, 410, 10, 0)
    WorldManager.createBoundary(-485, 2005, 10, 800, 0)
    WorldManager.createBoundary(-685, 2005, 10, 800, 0)
    WorldManager.createBoundary(-585, 2400, 200, 10, 0)
    
    
    WorldManager.createBoundary(-1520, 555, 10, 530, 0)
    WorldManager.createBoundary(-1465, 540, 10, 500, 0)
    WorldManager.createBoundary(-1575, 680, 100, 10, 0)
    
    -- edge
    WorldManager.createBoundary(-1885, -195, 10, 2000, 0)
    WorldManager.createBoundary(-390, -1200, 3000, 10, 0)
    
    -- Initialize vegetation storage
    Vegetation.init()
    if shelf1 and shelf1.body then Vegetation.populateBody(shelf1.body, 1.0) end
    
    -- Initialize Rainforest Trees
    Trees.init()
    -- Trees.create(-530, 256, 1.25)
    -- Trees.create(-440, 256, 1.15)
    -- Trees.create(180, 495, 1.40)
    Trees.create(440, 495, 1.30)
    -- Trees.create(-720, 600, 1.20)
    -- Trees.create(-1280, 815, 1.45)
    -- Trees.create(-1580, 1000, 1.25)
    
    -- Create water areas
    Water.createArea(-1880, 850, 190, 150, 0.8, 0.6, "basic") 
    Water.createArea(-1880, 1050, 790, 550, 1.4, 1.2, "deep") 
    Water.createArea(-680, 1650, 190, 750, 1.9, 1.5, "algae") 
    
    Whale.create(-1580, 1200, "baby", 45, 28)   
    Whale.create(-1480, 1300, "gentle", 45, 28)   
    Whale.create(-585, 2100, "aggressive", 45, 28)   
    
           
    
    -- Water.createArea(-600, 350, 200, 150, 1.1, 0.8)    -- Slight float
    -- Water.createArea(0, 500, 300, 100, 0.8, 0.7)       -- Sinking water (danger)
    
    -- Create whales in water areas
    
    -- Water.createArea(-1800, 500, 1500, 550, 1.2, 0.9)   -- Floating water
    -- Whale.create(-1500, 650, "aggressive", 30, 18)       
    -- Whale.create(-1500, 350, "baby", 30, 18)       
    
    WorldManager.updateSpatialGrid(Entities.list)
    
    -- Set camera to player position
    local player = Entities.player
    if player and player.body then
        local px, py = player.body:getPosition()
        Camera.x = px
        Camera.y = py
    end
    
    WorldManager.optimizeActiveChunks(Camera.x, Camera.y)
end

function love.update(dt)
    if game.state ~= "playing" then return end
    local physicsDt = math.min(dt, 0.033)
    
    WorldManager.world:update(physicsDt)
    Entities.update(physicsDt)
    Trees.update(physicsDt, Entities.list, Vegetation.list)
    Whale.update(physicsDt, Entities.player, Entities.list)
    Vegetation.update(physicsDt, Entities.list)
    Fire.update(physicsDt, Entities.list, Vegetation.list)
    Water.update(Entities.list)
    Entities.checkCollisions()
    RopeSystem.updateVisuals()
    EffectsSystem.update(dt) -- Visuals can use regular dt
    Camera.update(dt, Entities.player, Entities.list)
    
    -- Throttled Spatial Grid Chunk Optimization Processing Block
    WorldManager.timer = WorldManager.timer + dt
    if WorldManager.timer >= Config.chunks.updateInterval then
        WorldManager.timer = 0
        WorldManager.updateSpatialGrid(Entities.list)
        WorldManager.optimizeActiveChunks(Camera.x, Camera.y)
    end
end

function love.draw()
    love.graphics.clear(0.15, 0.15, 0.15)
    love.graphics.push()
    
    Camera.apply()
    
    local oldFont = love.graphics.getFont()
    local smallFont = love.graphics.newFont(8)
    love.graphics.setFont(smallFont)
    
    if debugDrawEnabled then
        local width = love.graphics.getWidth()
        local height = love.graphics.getHeight()
        local topLeftX = Camera.x - (width/2) / Camera.scale
        local topLeftY = Camera.y - (height/2) / Camera.scale
        local viewWidth = width / Camera.scale
        local viewHeight = height / Camera.scale
        
        b2debugDraw(WorldManager.world, topLeftX, topLeftY, viewWidth, viewHeight)
        Trees.draw()
        Vegetation.draw()
        Fire.draw()
        EffectsSystem.draw()
        Water.draw()
    else
        Trees.draw()
        Entities.draw()
        RopeSystem.drawAll(game.debugMode)
        Vegetation.draw()
        Fire.draw()
        EffectsSystem.draw()
        Whale.draw(game.debugMode)
        Water.draw()
        WorldManager.drawBoundaries()
    end
    
    love.graphics.setFont(oldFont)
    if game.debugMode then drawDebugData() end

    love.graphics.pop()
    drawUI()
end

function love.mousepressed(x, y, button, istouch)
    local worldX, worldY = Camera:screenToWorld(x, y)
    
    if button == 1 then -- Left click: grab object
        local player = Entities.player
        if not player or #(player.ropeIds or {}) >= 2 then return end
        
        local closest, minDist = nil, Config.enemy.grabRadius * 2
        
        -- Check regular entities
        for _, e in ipairs(Entities.list) do
            if e.body and not e.body:isDestroyed() and e ~= player then
                if not RopeSystem.connects(player, e) then
                    local ex, ey = e.body:getPosition()
                    local dx, dy = worldX - ex, worldY - ey
                    local dist = math.sqrt(dx*dx + dy*dy)
                    if dist < minDist then
                        minDist = dist
                        closest = e
                    end
                end
            end
        end
        
        -- Also check whales!
        local whales = Whale.getAll()
        for _, w in ipairs(whales) do
            if w.body and not w.body:isDestroyed() then
                if not RopeSystem.connects(player, w) then
                    local wx, wy = w.body:getPosition()
                    local dx, dy = worldX - wx, worldY - wy
                    local dist = math.sqrt(dx*dx + dy*dy)
                    -- Use whale's size for threshold
                    local threshold = w.data.w / 2 + 20
                    if dist < minDist and dist < threshold then
                        minDist = dist
                        closest = w
                    end
                end
            end
        end
        
        if closest then
            RopeSystem.create(player, closest)
        end
        
    elseif button == 2 then -- Right click: release all ropes from player
        local player = Entities.player
        if player then
            RopeSystem.destroyAllForObject(player)
        end
    end
    
    -- Camera target selection (only when in follow_target mode)
    if button == 1 and Camera.mode == "follow_target" then
        -- Find the closest entity under the mouse cursor
        local closestEntity = nil
        local minDist = 60   -- detection radius

        -- Check regular entities
        for _, e in ipairs(Entities.list) do
            if e.body and not e.body:isDestroyed() then
                local ex, ey = e.body:getPosition()
                local dx, dy = worldX - ex, worldY - ey
                local dist = math.sqrt(dx*dx + dy*dy)
                local threshold = (e.r or math.max(e.w or 20, e.h or 20)) + 15
                if dist < threshold and dist < minDist then
                    minDist = dist
                    closestEntity = e
                end
            end
        end

        -- Also check whales
        if not closestEntity then
            local whales = Whale.getAll()
            for _, w in ipairs(whales) do
                if w.body and not w.body:isDestroyed() then
                    local wx, wy = w.body:getPosition()
                    local dx, dy = worldX - wx, worldY - wy
                    local dist = math.sqrt(dx*dx + dy*dy)
                    local threshold = w.data.w / 2 + 20
                    if dist < threshold and dist < minDist then
                        minDist = dist
                        closestEntity = w
                    end
                end
            end
			end

        if closestEntity then
            Camera.followTarget = closestEntity
            print("Now following: " .. (closestEntity.type or "whale"))
        else
            print("No object clicked – target unchanged")
        end
    end

end

function love.mousemoved(x, y)
    local worldX, worldY = Camera:screenToWorld(x, y)
    hoveredEntity = nil
    local minDist = 50 -- hover detection radius
    for _, e in ipairs(Entities.list) do
        if e.body and not e.body:isDestroyed() then
            local ex, ey = e.body:getPosition()
            local dx, dy = worldX - ex, worldY - ey
            local dist = math.sqrt(dx*dx + dy*dy)
            -- Rough distance based on entity size
            local threshold = (e.r or math.max(e.w or 20, e.h or 20)) + 10
            if dist < threshold and dist < minDist then
                minDist = dist
                hoveredEntity = e
            end
        end
    end
end

-- Helper function to avoid code duplication
function setTimerOnTouchedExplosive(seconds)
    local player = Entities.player
    if player and player.body then
        local px, py = player.body:getPosition()
        for _, e in ipairs(Entities.list) do
            if (e.type == "grenade" or e.type == "tnt" or e.type == "nuke" or e.type == "radium") and e.body and not e.body:isDestroyed() then
                local ex, ey = e.body:getPosition()
                local dist = math.sqrt((px-ex)^2 + (py-ey)^2)
                if dist < 40 then   -- contact range
                    e.timer = seconds
                    break
                end
            end
        end
    end
end

local timer_input_buffer = ""
local timer_input_time = 0

function love.keypressed(key)
    
    -- Number keys 0-9: set timer on touched explosive (supports 1-2 digits)
    local num = tonumber(key)
    if num and num >= 0 and num <= 9 then
        local current_time = love.timer.getTime()
        
        -- Clear buffer if it's been more than 1 second since last keypress
        if current_time - timer_input_time > 1 then
            timer_input_buffer = ""
        end
        
        if key == "0" and timer_input_buffer == "" then
            -- Leading zero: start buffer for "01", "02", etc.
            timer_input_buffer = "0"
            timer_input_time = current_time
        elseif timer_input_buffer == "0" and num >= 1 and num <= 9 then
            -- Complete two-digit number starting with 0 (01-09)
            local seconds = tonumber("0" .. tostring(num))
            setTimerOnTouchedExplosive(seconds)
            timer_input_buffer = ""
        elseif timer_input_buffer == "" then
            -- First digit (1-9)
            timer_input_buffer = tostring(num)
            timer_input_time = current_time
        else
            -- Second digit (0-9) - complete two-digit number
            local seconds = tonumber(timer_input_buffer .. tostring(num))
            setTimerOnTouchedExplosive(seconds)
            timer_input_buffer = ""
        end
    end
    
    if key == "escape" then love.event.quit()
    elseif key == "f1" then Camera.mode = "follow_player"
    elseif key == "f2" then  Camera.mode = "follow_target"
    elseif key == "f3" then Camera.mode = "free_move"
    elseif key == "=" or key == "+" then Camera.scale = math.min(Camera.scale + 0.1, Config.camera.maxScale)
    elseif key == "-" or key == "_" then Camera.scale = math.max(Camera.scale - 0.1, Config.camera.minScale)
    elseif key == "backspace" then Camera.scale = 1.0 
    elseif key == "f5" then
        game.debugMode = not game.debugMode
        Entities.setDebugMode(game.debugMode)
    elseif key == "f6" then
        Water.setDebug(not Water.debugMode)
    elseif key == "f7" then
        debugDrawEnabled = not debugDrawEnabled
    elseif key == "p" then game.state = (game.state == "playing") and "paused" or "playing"
    elseif key == "tab" then
        local p = Entities.player
        if p then
            RopeSystem.destroyAllForObject(p) 
        end
    elseif key == "space" then
        local p = Entities.player
        if p then
            if p.ropeIds and #p.ropeIds == 2 then 
                RopeSystem.destroyAllForObject(p) 
            else 
                Entities.grab(false) 
            end
        end
    elseif key == "e" then
        Entities.grab(true)
    elseif key == "c" then
        local mx, my = Camera:screenToWorld(love.mouse.getPosition())
        Trees.chopAt(mx, my, Entities.player)
    elseif key == "z" then
        local player = Entities.player
        if player then
            if player.body and not player.body:isDestroyed() then
                local px, py = player.body:getPosition()
                Trees.sliceAt(px, py, 75)
            end
            WorldManager.sliceBoundaryAtPlayer(player)
        end
    elseif key == "m" then
        local player = Entities.player
        if player then
            Entities.mergeBoxesTouchingPlayer(player)
            Entities.mergeExplosivesNearPlayer(player)
        end
    elseif key == "g" and (love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")) then
        -- Shift+G: Create inert grenade (damageless)
        local mx, my = Camera:screenToWorld(love.mouse.getPosition())
        local grenade = Entities.createGrenade(mx, my)
        grenade.explosionDamage = 0
        grenade.isInert = true
        grenade.mergePower = 0 
        grenade.sensitivity = love.keyboard.isDown("lctrl") and 0.5 or 0
        
    elseif key == "t" and (love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")) then
        -- Shift+T: Create inert TNT (damageless)
        local mx, my = Camera:screenToWorld(love.mouse.getPosition())
        local tnt = Entities.createTNTBox(mx, my, 30, 30)
        tnt.explosionDamage = 0
        tnt.isInert = true
        tnt.mergePower = 0
        tnt.sensitivity = love.keyboard.isDown("lctrl") and 0.5 or 0
        
    elseif key == "n" and (love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")) then
        -- Shift+N: Create inert nuke (damageless)
        local mx, my = Camera:screenToWorld(love.mouse.getPosition())
        local nuke = Entities.createNuke(mx, my)
        nuke.explosionDamage = 0
        nuke.isInert = true
        nuke.mergePower = 0
        nuke.sensitivity = love.keyboard.isDown("lctrl") and 0.5 or 0
    elseif key == "r" and (love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")) then
        -- Shift+R: Create inert radium (damageless)
        local mx, my = Camera:screenToWorld(love.mouse.getPosition())
        local radium = Entities.createRadium(mx, my)
        radium.explosionDamage = 0
        radium.isInert = true
        radium.mergePower = 0
        radium.sensitivity = love.keyboard.isDown("lctrl") and 0.5 or 0
    elseif key == "g" then
        local mx, my = Camera:screenToWorld(love.mouse.getPosition())
        local sensitivity = love.keyboard.isDown("lctrl") and 0.5 or 0
        Entities.createGrenade(mx, my, sensitivity)
    elseif key == "t" then
        local mx, my = Camera:screenToWorld(love.mouse.getPosition())
        local sensitivity = love.keyboard.isDown("lctrl") and 0.5 or 0
        Entities.createTNTBox(mx, my, 30, 30, sensitivity)
    elseif key == "n" then
        local mx, my = Camera:screenToWorld(love.mouse.getPosition())
        local sensitivity = love.keyboard.isDown("lctrl") and 0.5 or 0
        Entities.createNuke(mx, my, sensitivity)
    elseif key == "r" then
        local mx, my = Camera:screenToWorld(love.mouse.getPosition())
        local sensitivity = love.keyboard.isDown("lctrl") and 0.5 or 0
        Entities.createRadium(mx, my, sensitivity)
    elseif key == "f" then
        local mx, my = Camera:screenToWorld(love.mouse.getPosition())
        Fire.igniteAt(mx, my, Entities.player, Entities.list, Vegetation.list)
    elseif key == "k" then
        if Entities.player and Entities.player.body and not Entities.player.body:isDestroyed() then
            Entities.player.autopilotEnabled = not Entities.player.autopilotEnabled
        end
    
    elseif key == "v" then
        local player = Entities.player
        if not player or not player.body or player.body:isDestroyed() then return end

        -- Get all contacts from the physics world
        local contacts = WorldManager.world:getContacts()
        local addedToAny = false

        for _, contact in ipairs(contacts) do
            if not contact:isDestroyed() and contact:isEnabled() and contact:isTouching() then
                local fa, fb = contact:getFixtures()
                if fa and fb and not fa:isDestroyed() and not fb:isDestroyed() then
                    local bodyA = fa:getBody()
                    local bodyB = fb:getBody()
                    local otherBody = nil

                    -- Identify the body that is NOT the player
                    if bodyA == player.body then
                        otherBody = bodyB
                    elseif bodyB == player.body then
                        otherBody = bodyA
                    end

                    if otherBody then
                        local isValidTarget = false
                        
                        -- 1. Check if the body is an allowed active entity
                        for _, e in ipairs(Entities.list) do
                            if e.body == otherBody then
                                -- Restrict planting to these types:
                                if e.type == "box" or e.type == "ball" or e.type == "grenade" or e.type == "tnt" or e.type == "nuke" or e.type == "radium" then
                                    isValidTarget = true
                                end
                                break
                            end
                        end
                        
                        -- 2. If it wasn't an entity, check if it's a map boundary
                        if not isValidTarget then
                            for _, b in ipairs(WorldManager.boundaries) do
                                if b.body == otherBody then
                                    isValidTarget = true
                                    break
                                end
                            end
                        end

                        -- If valid, add the grass to the body dynamically
                        if isValidTarget then
                            Vegetation.populateBody(otherBody, 1.0)
                            addedToAny = true
                        end
                    end
                end
            end
        end

        if not addedToAny then
            print("No valid colliding object found. Grass only grows on boxes, bounds, balls, and bombs.")
        else
            print("Grass added to surface.")
        end
        
    elseif key == "lshift" then
        local p = Entities.player
        if p and p.ropeIds and #p.ropeIds == 2 then
            local ids = {}
            for _, id in ipairs(p.ropeIds) do table.insert(ids, id) end
            if #ids >= 2 then
                local r1, r2 = RopeSystem.collection[ids[1]], RopeSystem.collection[ids[2]]
                if r1 and r2 then
                    local o1 = (r1.obj1 == p) and r1.obj2 or r1.obj1
                    local o2 = (r2.obj1 == p) and r2.obj2 or r2.obj1
                    if o1 and o2 then
                        RopeSystem.destroy(ids[1])
                        RopeSystem.destroy(ids[2])
                        RopeSystem.create(o1, o2)
                        -- local jx, jy = p.body:getWorldPoint(0, p.h / 2)
                        -- for i = 1, 20 do EffectsSystem.createDamageEffect(jx, jy) end
                    end
                end
            end
        end
    end
end

function love.wheelmoved(x, y)
    local factor = Config.camera.zoomFactor
    if y > 0 then Camera.scale = math.min(Camera.scale * factor, Config.camera.maxScale)
    elseif y < 0 then Camera.scale = math.max(Camera.scale / factor, Config.camera.minScale)
    end
end

function drawUI()
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("State: " .. game.state, 10, 10)
    love.graphics.print("Camera Mode: " .. Camera.mode, 10, 30)
    love.graphics.print("Zoom: " .. string.format("%.2f", Camera.scale), 10, 50)
    
    local p = Entities.player
    if p and p.body and not p.body:isDestroyed() then
        local px, py = p.body:getPosition()
        love.graphics.print("Player: " .. math.floor(px) .. ", " .. math.floor(py), 10, 80)
        love.graphics.print("Ropes Attached: " .. #(p.ropeIds or {}) .. "/2", 10, 100)
    end
    
    if game.debugMode then
        love.graphics.setColor(1, 0, 0)
        love.graphics.print("DEBUG MODE ACTIVE", 10, 130)
        love.graphics.setColor(1, 1, 1)
        local count = 0 for _ in pairs(RopeSystem.collection) do count = count + 1 end
        love.graphics.print("Active Ropes: " .. count, 10, 150)
        love.graphics.print("Total Entities: " .. #Entities.list, 10, 170)
        local vegStatus = Vegetation.isDestroyed() and "DESTROYED" or (#Vegetation.list .. " tufts")
        love.graphics.print("Vegetation: " .. vegStatus, 10, 190)
        love.graphics.print("Active Fires: " .. #Fire.list, 10, 210)
        love.graphics.print("Trees: " .. #Trees.list .. " standing", 10, 230)
    end
    
    love.graphics.print("Controls:", love.graphics.getWidth() - 220, 10)
    for i, inst in ipairs(cameraInstructions) do
        love.graphics.print(inst, love.graphics.getWidth() - 220, 10 + i * 18)
    end
end

function drawDebugData()
    love.graphics.setColor(0, 0.5, 0, 0.3)
    for _, b in ipairs(WorldManager.boundaries) do
        if b.body and not b.body:isDestroyed() then
            love.graphics.polygon("line", b.body:getWorldPoints(b.shape:getPoints()))
        end
    end
    
    local p = Entities.player
    if p and p.body and not p.body:isDestroyed() then
        local x, y = p.body:getPosition()
        local vx, vy = p.body:getLinearVelocity()
        love.graphics.setColor(0, 0.5, 1, 0.8)
        love.graphics.line(x, y, x + vx, y + vy)
    end
    
    -- Draw explosive blast radii and timers
    love.graphics.setLineWidth(0.5)
    for _, e in ipairs(Entities.list) do
        if (e.type == "grenade" or e.type == "tnt" or e.type == "nuke" or e.type == "radium") and e.body and not e.body:isDestroyed() then
            local x, y = e.body:getPosition()
            -- Blast radius circle (semi-transparent green for radium, red for others)
            if e.type == "radium" then
                love.graphics.setColor(0.1, 1, 0.2, 0.10)
                love.graphics.circle("fill", x, y, e.explosionRadius)
                love.graphics.setColor(0.2, 1, 0.3, 0.25)
                love.graphics.circle("line", x, y, e.explosionRadius)
            else
                love.graphics.setColor(1, 0, 0, 0.09)
                love.graphics.circle("fill", x, y, e.explosionRadius)
                love.graphics.setColor(1, 0, 0, 0.17)
                love.graphics.circle("line", x, y, e.explosionRadius)
            end
            -- Timer info
            if e.timer and e.timer > 0 then
                love.graphics.setColor(1, 1, 0, 1)
                love.graphics.print(string.format("Timer: %.1f", e.timer), x - 15, y - e.explosionRadius - 10)
            else
                love.graphics.setColor(0.5, 0.5, 0.5, 1)
                love.graphics.print("Inert", x - 10, y - e.explosionRadius - 10)
            end
            -- Show damage/force values
            love.graphics.setColor(1, 1, 1, 0.8)
            love.graphics.print(string.format("Dmg:%d Force:%d Sensi:%d", e.explosionDamage, e.explosionForce, e.sensitivity), x - 20, y + e.explosionRadius + 5)
        end
    end
    love.graphics.setLineWidth(1)
end