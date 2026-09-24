-- trees.lua
-- Flexible, hyper-realistic physics-based tall branching trees with Box2D collision,
-- tapered branch geometry, spring revolute joints, and solid black silhouette rendering.
--
-- The physics body of each branch is a COMPOSITE of fixtures that exactly match
-- the drawn silhouette: main tapered trapezoid polygon + start/end fillet cap
-- circles + twig rectangle polygons + twig tip circles.
--
-- ELASTIC BEHAVIOR
--   Each branch is a spring-mass oscillator around its revolute joint. To make
--   the tree both FLEXIBLE (visible sway) and STABLE (returns to rest without
--   drifting), the spring damping is computed from the physics body itself:
--
--       damping = 2 * zeta * sqrt(stiffness * inertia)
--
--   where zeta is the dimensionless damping ratio. Values < 1 give elastic
--   spring-back (bends, wobbles, settles). zeta ~= 0.45 is a nice, lively
--   elastic feel. Body-level linear/angular damping stays at 0 so the tree
--   feels alive and sway persists naturally.
--
-- NOTE: The tree has NO VISIBLE ROOT. The static anchor body exists only to hold
-- the first trunk segment's revolute joint. The base trunk extends a small
-- amount below the joint anchor so no gap opens up while the tree sways —
-- keeping its base visually embedded in the ground at all times.
local EffectsSystem = require("effects")
local Entities = require("entities")
local WorldManager = require("world_manager")

local Trees = {
    list = {}
}

-- Spring damping ratio for elastic return. 1.0 = critically damped (no wobble),
-- < 1 = elastic oscillation. 0.45 gives a lively, springy tree.
local ELASTIC_ZETA = 0.45

-- How far (in world units, scaled) the base trunk is extended downward past
-- its joint anchor, so the tree's base always looks planted in the ground.
local BASE_GROUND_EXTEND = 8

-- Health values (chopping damage = 45 by default, so these are tough)
local HP = {
    TRUNK_1   = 4000,
    TRUNK_2   = 3500,
    TRUNK_3   = 3000,
    TRUNK_4   = 2500,
    TRUNK_5   = 2000,
    TIER2     = 1500,
    TIER2_SUB = 900,
    TIER3     = 1200,
    TIER3_SUB = 700,
    TIER4     = 900,
    TIER4_SUB = 500,
    CROWN     = 700
}

function Trees.init()
    for _, tree in ipairs(Trees.list) do
        for _, branch in ipairs(tree.branches) do
            if branch.joint and not branch.joint:isDestroyed() then
                branch.joint:destroy()
            end
            branch.joint = nil
            if branch.body and not branch.body:isDestroyed() then
                branch.body:destroy()
            end
            branch.body = nil
        end
        if tree.rootBody and not tree.rootBody:isDestroyed() then
            tree.rootBody:destroy()
            tree.rootBody = nil
        end
    end
    Trees.list = {}
end

local function pointToSegmentDistance(px, py, ax, ay, bx, by)
    local vx, vy = bx - ax, by - ay
    local wx, wy = px - ax, py - ay
    local c1 = wx * vx + wy * vy
    if c1 <= 0 then
        return math.sqrt((px - ax) ^ 2 + (py - ay) ^ 2)
    end
    local c2 = vx * vx + vy * vy
    if c2 <= c1 then
        return math.sqrt((px - bx) ^ 2 + (py - by) ^ 2)
    end
    local b = c1 / c2
    local projX, projY = ax + b * vx, ay + b * vy
    return math.sqrt((px - projX) ^ 2 + (py - projY) ^ 2)
end

local function generateTwigForks(scale, w2)
    local forks = {}
    local s = scale or 1
    if w2 > 9 * s then return forks end
    local numForks = love.math.random(2, 4)
    for i = 1, numForks do
        local side = (i % 2 == 0) and 1 or -1
        table.insert(forks, {
            relAng = side * (0.30 + love.math.random() * 0.55),
            len = (12 + love.math.random() * 16) * s,
            w1 = math.max(1.4, w2 * 0.55),
            w2 = 0.7
        })
    end
    return forks
end

-- Creates an individual tapered branch segment.
-- `damping` parameter is IGNORED in favour of a physical damping computed
-- from the body's actual inertia, so every branch gets a consistent, elastic
-- spring response regardless of its size or mass.
local function createBranchSegment(tree, parent, startX, startY, angle, length, w1, w2, stiffness, damping, maxDeflection, health, hasLeaves)
    w2 = w2 or (w1 * 0.65)
    local endX = startX + math.cos(angle) * length
    local endY = startY + math.sin(angle) * length
    local midX = (startX + endX) * 0.5
    local midY = (startY + endY) * 0.5

    local body = love.physics.newBody(WorldManager.world, midX, midY, "dynamic")
    body:setAngle(angle)
    -- No body-level damping. All energy dissipation happens through the
    -- physical spring-damper on the joint, which keeps the tree lively.

    local hw1, hw2 = w1 * 0.5, w2 * 0.5
    local hl = length * 0.5
    local density = 2.0 + (w1 / 18.0)

    -- -----------------------------------------------------------------
    -- COMPOSITE PHYSICS FIXTURES (match rendered silhouette exactly)
    -- -----------------------------------------------------------------
    local allFixtures = {}
    local isBaseTrunk = (parent == nil)

    -- Base trunk gets a small downward extension so its bottom edge stays
    -- embedded in the ground even while the tree sways side to side.
    -- The extension lives below the joint anchor, so it is only ever
    -- visible during the deepest tilts (and prevents the "floating trunk" gap).
    local baseExtend = isBaseTrunk and (BASE_GROUND_EXTEND * (tree.scale or 1)) or 0

    -- (1) Main tapered trapezoid polygon (extended downward on base trunk)
    local shape = love.physics.newPolygonShape(
        -hl - baseExtend, -hw1,
         hl,               -hw2,
         hl,                hw2,
        -hl - baseExtend,   hw1
    )
    local fixture = love.physics.newFixture(body, shape, density)
    fixture:setFriction(0.85)
    fixture:setRestitution(0.05)
    table.insert(allFixtures, fixture)

    -- (2) Fillet cap circles. Start cap is SKIPPED for the base trunk so the
    --     bottom edge is flat (this also lets the extension blend cleanly
    --     with the ground).
    -- if not isBaseTrunk then
        -- local capStartShape = love.physics.newCircleShape(-hl, 0, hw1)
        -- local capStartFix = love.physics.newFixture(body, capStartShape, density)
        -- capStartFix:setFriction(0.85); capStartFix:setRestitution(0.05)
        -- table.insert(allFixtures, capStartFix)
    -- end

    -- local capEndShape = love.physics.newCircleShape(hl, 0, hw2)
    -- local capEndFix = love.physics.newFixture(body, capEndShape, density)
    -- capEndFix:setFriction(0.85); capEndFix:setRestitution(0.05)
    -- table.insert(allFixtures, capEndFix)

    -- (3) Twig forks
    local twigForks = generateTwigForks(tree.scale, w2)
    local twigDensity = density * 0.25
    for _, fork in ipairs(twigForks) do
        local cosT, sinT = math.cos(fork.relAng), math.sin(fork.relAng)
        local twigHw = fork.w1 * 0.5
        local sx, sy = hl, 0
        local ex, ey = hl + cosT * fork.len, sinT * fork.len
        local px, py = -sinT, cosT
        local x1, y1 = sx + px * twigHw, sy + py * twigHw
        local x2, y2 = ex + px * twigHw, ey + py * twigHw
        local x3, y3 = ex - px * twigHw, ey - py * twigHw
        local x4, y4 = sx - px * twigHw, sy - py * twigHw
        local twigShape = love.physics.newPolygonShape(x1, y1, x2, y2, x3, y3, x4, y4)
        local twigFix = love.physics.newFixture(body, twigShape, twigDensity)
        twigFix:setFriction(0.85); twigFix:setRestitution(0.05)
        table.insert(allFixtures, twigFix)

        -- local tipShape = love.physics.newCircleShape(ex, ey, fork.w2 * 0.5)
        -- local tipFix = love.physics.newFixture(body, tipShape, twigDensity)
        -- tipFix:setFriction(0.85); tipFix:setRestitution(0.05)
        -- table.insert(allFixtures, tipFix)
    end

    -- -----------------------------------------------------------------
    -- ELASTIC SPRING DAMPING (computed from physical inertia)
    --   c = 2 * zeta * sqrt(k * I)
    -- -----------------------------------------------------------------
    local inertia = body:getInertia()
    local elasticDamping = 2 * ELASTIC_ZETA * math.sqrt(stiffness * inertia)

    -- -----------------------------------------------------------------
    -- JOINT (spring revolute)
    -- Anchored at (startX, startY) — the original top-of-trunk pivot point,
    -- unchanged by the base extension (which extends downward past it).
    -- -----------------------------------------------------------------
    local parentBody = parent and parent.body or tree.rootBody
    local joint = love.physics.newRevoluteJoint(parentBody, body, startX, startY, false)
    joint:setLimitsEnabled(true)
    joint:setLimits(-maxDeflection, maxDeflection)

    local branch = {
        tree = tree,
        parent = parent,
        children = {},
        body = body,
        shape = shape,
        fixture = fixture,
        fixtures = allFixtures,
        joint = joint,
        length = length,
        w1 = w1,
        w2 = w2,
        angle = angle,
        restRelAngle = body:getAngle() - parentBody:getAngle(),
        stiffness = stiffness,
        damping = elasticDamping,       -- computed elastic damping
        maxDeflection = maxDeflection,
        health = health or 100,
        maxHealth = health or 100,
        hasLeaves = hasLeaves,
        twigForks = twigForks,
        isBaseTrunk = isBaseTrunk,
        baseExtend = baseExtend,
        isSevered = false,
        windPhase = love.math.random() * math.pi * 2,
        windForce = (10 + love.math.random() * 20) * (w1 / 18)
    }

    if parent then
        table.insert(parent.children, branch)
    end

    local branchEntity = {
        type = "box",
        body = body,
        shape = shape,
        fixture = fixture,
        w = length,
        h = math.max(w1, w2),
        label = "Tree Branch",
        health = branch.health,
        maxHealth = branch.maxHealth,
        isBranch = true,
        branchRef = branch,
        ropeIds = {}
    }
    table.insert(Entities.list, branchEntity)
    branch.entity = branchEntity

    table.insert(tree.branches, branch)
    return branch
end

function Trees.create(rootX, rootY, heightScale)
    local s = heightScale or 1.35

    -- Invisible static anchor for trunk base
    local rootBody = love.physics.newBody(WorldManager.world, rootX, rootY, "static")
    local rootShape = love.physics.newRectangleShape(4 * s, 4 * s)
    local rootFixture = love.physics.newFixture(rootBody, rootShape)

    local tree = {
        id = #Trees.list + 1,
        rootX = rootX,
        rootY = rootY,
        scale = s,
        rootBody = rootBody,
        rootShape = rootShape,
        rootFixture = rootFixture,
        branches = {}
    }

    -- =========================================================
    -- TALL TRUNK SPINE (5 soaring, tapering vertical segments)
    -- =========================================================
    local t1 = createBranchSegment(tree, nil, rootX, rootY, -math.pi * 0.5, 68 * s, 36 * s, 30 * s, 26000, 0, 0.12, HP.TRUNK_1, false)
    local x, y = t1.body:getWorldPoint(t1.length * 0.5, 0)

    local t2 = createBranchSegment(tree, t1, x, y, -math.pi * 0.5 + (love.math.random() - 0.5) * 0.04, 62 * s, 30 * s, 24 * s, 18000, 0, 0.16, HP.TRUNK_2, false)
    x, y = t2.body:getWorldPoint(t2.length * 0.5, 0)

    local t3 = createBranchSegment(tree, t2, x, y, -math.pi * 0.5 + (love.math.random() - 0.5) * 0.05, 58 * s, 24 * s, 18 * s, 12000, 0, 0.20, HP.TRUNK_3, false)
    x, y = t3.body:getWorldPoint(t3.length * 0.5, 0)

    local t4 = createBranchSegment(tree, t3, x, y, -math.pi * 0.5 + (love.math.random() - 0.5) * 0.06, 52 * s, 18 * s, 13 * s, 8000, 0, 0.24, HP.TRUNK_4, false)
    x, y = t4.body:getWorldPoint(t4.length * 0.5, 0)

    local t5 = createBranchSegment(tree, t4, x, y, -math.pi * 0.5 + (love.math.random() - 0.5) * 0.08, 46 * s, 13 * s, 8 * s, 5000, 0, 0.28, HP.TRUNK_5, false)

    -- =========================================================
    -- REALISTIC MULTI-TIERED BRANCHING LIMBS
    -- =========================================================
    -- Tier 2 Limbs (T2)
    local bx, by = t2.body:getWorldPoint(t2.length * 0.5, 0)
    local l2L = createBranchSegment(tree, t2, bx, by, -math.pi * 0.5 - 0.65, 48 * s, 18 * s, 11 * s, 4500, 0, 0.35, HP.TIER2, false)
    local lx, ly = l2L.body:getWorldPoint(l2L.length * 0.5, 0)
    createBranchSegment(tree, l2L, lx, ly, l2L.angle - 0.25, 36 * s, 11 * s, 5 * s, 1800, 0, 0.45, HP.TIER2_SUB, false)

    local l2R = createBranchSegment(tree, t2, bx, by, -math.pi * 0.5 + 0.65, 48 * s, 18 * s, 11 * s, 4500, 0, 0.35, HP.TIER2, false)
    local rx, ry = l2R.body:getWorldPoint(l2R.length * 0.5, 0)
    createBranchSegment(tree, l2R, rx, ry, l2R.angle + 0.25, 36 * s, 11 * s, 5 * s, 1800, 0, 0.45, HP.TIER2_SUB, false)

    -- Tier 3 Limbs (T3)
    bx, by = t3.body:getWorldPoint(t3.length * 0.5, 0)
    local l3L = createBranchSegment(tree, t3, bx, by, -math.pi * 0.5 - 0.55, 46 * s, 15 * s, 9 * s, 3800, 0, 0.38, HP.TIER3, false)
    lx, ly = l3L.body:getWorldPoint(l3L.length * 0.5, 0)
    createBranchSegment(tree, l3L, lx, ly, l3L.angle - 0.28, 34 * s, 9 * s, 4 * s, 1500, 0, 0.48, HP.TIER3_SUB, false)
    createBranchSegment(tree, l3L, lx, ly, l3L.angle + 0.22, 30 * s, 8 * s, 4 * s, 1300, 0, 0.48, HP.TIER3_SUB, false)

    local l3R = createBranchSegment(tree, t3, bx, by, -math.pi * 0.5 + 0.55, 46 * s, 15 * s, 9 * s, 3800, 0, 0.38, HP.TIER3, false)
    rx, ry = l3R.body:getWorldPoint(l3R.length * 0.5, 0)
    createBranchSegment(tree, l3R, rx, ry, l3R.angle - 0.22, 30 * s, 8 * s, 4 * s, 1300, 0, 0.48, HP.TIER3_SUB, false)
    createBranchSegment(tree, l3R, rx, ry, l3R.angle + 0.28, 34 * s, 9 * s, 4 * s, 1500, 0, 0.48, HP.TIER3_SUB, false)

    -- Tier 4 Limbs (T4)
    bx, by = t4.body:getWorldPoint(t4.length * 0.5, 0)
    local l4L = createBranchSegment(tree, t4, bx, by, -math.pi * 0.5 - 0.48, 42 * s, 12 * s, 7 * s, 2800, 0, 0.42, HP.TIER4, false)
    lx, ly = l4L.body:getWorldPoint(l4L.length * 0.5, 0)
    createBranchSegment(tree, l4L, lx, ly, l4L.angle - 0.30, 32 * s, 7 * s, 3 * s, 1200, 0, 0.50, HP.TIER4_SUB, false)

    local l4R = createBranchSegment(tree, t4, bx, by, -math.pi * 0.5 + 0.48, 42 * s, 12 * s, 7 * s, 2800, 0, 0.42, HP.TIER4, false)
    rx, ry = l4R.body:getWorldPoint(l4R.length * 0.5, 0)
    createBranchSegment(tree, l4R, rx, ry, l4R.angle + 0.30, 32 * s, 7 * s, 3 * s, 1200, 0, 0.50, HP.TIER4_SUB, false)

    -- Crown Top Limbs (T5 Top)
    bx, by = t5.body:getWorldPoint(t5.length * 0.5, 0)
    createBranchSegment(tree, t5, bx, by, -math.pi * 0.5 - 0.35, 38 * s, 9 * s, 4 * s, 2000, 0, 0.45, HP.CROWN, false)
    createBranchSegment(tree, t5, bx, by, -math.pi * 0.5 + (love.math.random() - 0.5) * 0.1, 36 * s, 9 * s, 4 * s, 2000, 0, 0.45, HP.CROWN, false)
    createBranchSegment(tree, t5, bx, by, -math.pi * 0.5 + 0.35, 38 * s, 9 * s, 4 * s, 2000, 0, 0.45, HP.CROWN, false)

    table.insert(Trees.list, tree)
    return tree
end

function Trees.update(dt, entitiesList, vegetationList)
    local _, gy = WorldManager.world:getGravity()
    local time = love.timer.getTime()

    for _, tree in ipairs(Trees.list) do
        for _, branch in ipairs(tree.branches) do
            if branch.body and not branch.body:isDestroyed() then
                local mass = branch.body:getMass()

                if not branch.isSevered then
                    -- Standing tree counteracts 97% gravity to stand tall
                    branch.body:applyForce(0, -gy * mass * 0.97)

                    -- Ambient wind sway
                    local wind = math.sin(time * 1.5 + branch.windPhase) * branch.windForce
                    branch.body:applyTorque(wind)

                    -- Elastic spring restoring torque relative to parent
                    if branch.joint and not branch.joint:isDestroyed()
                       and branch.parent and branch.parent.body
                       and not branch.parent.body:isDestroyed() then
                        local childAngle = branch.body:getAngle()
                        local parentAngle = branch.parent.body:getAngle()
                        local currentRel = childAngle - parentAngle
                        local diff = currentRel - branch.restRelAngle

                        while diff > math.pi do diff = diff - 2 * math.pi end
                        while diff < -math.pi do diff = diff + 2 * math.pi end

                        local relAngVel = branch.body:getAngularVelocity() - branch.parent.body:getAngularVelocity()
                        local torque = -branch.stiffness * diff - branch.damping * relAngVel

                        branch.body:applyTorque(torque)
                        if branch.parent.body:getType() == "dynamic" then
                            branch.parent.body:applyTorque(-torque * 0.6)
                        end
                    end
                end
            end
        end
    end
end

local function severBranchRecursive(branch)
    if not branch or branch.isSevered then return end
    branch.isSevered = true

    if branch.body and not branch.body:isDestroyed() then
        if branch.joint then
            if not branch.joint:isDestroyed() then
                branch.joint:destroy()
            end
            branch.joint = nil
        end
        branch.body:setAwake(true)
        
        -- Apply normal physical damping so the separate body settles realistically
        branch.body:setLinearDamping(0.8)
        branch.body:setAngularDamping(1.5)
        
        if branch.entity then
            branch.entity.isBranch = true
            branch.entity.isSeveredBranch = true
        end
    end

    if branch.children then
        for i = #branch.children, 1, -1 do
            severBranchRecursive(branch.children[i])
        end
    end
end

function Trees.severBranch(branch)
    if not branch or branch.isSevered then return end

    local jx, jy = branch.body:getPosition()
    if branch.joint and not branch.joint:isDestroyed() then
        jx, jy = branch.joint:getAnchors()
    end

    severBranchRecursive(branch)

    EffectsSystem.createShockwave(jx, jy, 40, 0.6, "fire")
    for _ = 1, 22 do
        local ang = love.math.random() * math.pi * 2
        local spd = love.math.random(50, 160)
        EffectsSystem.createParticle(jx, jy, math.cos(ang) * spd, math.sin(ang) * spd - 30, 30, 220, 3.5, "woodChip")
    end
    for _ = 1, 10 do
        EffectsSystem.createParticle(jx + love.math.random(-15, 15), jy + love.math.random(-15, 15),
            love.math.random(-30, 30), love.math.random(-20, 40), 20, 150, 2.5, "ember")
    end
end

function Trees.chopAt(worldX, worldY, player, damageAmount)
    local dmg = damageAmount or 45
    local targetBranch, bestDist = nil, 65

    for _, tree in ipairs(Trees.list) do
        for _, branch in ipairs(tree.branches) do
            if branch.body and not branch.body:isDestroyed() and not branch.isSevered then
                local ax, ay = branch.body:getWorldPoint(-branch.length * 0.5, 0)
                local bx, by = branch.body:getWorldPoint(branch.length * 0.5, 0)
                local dist = pointToSegmentDistance(worldX, worldY, ax, ay, bx, by)

                if dist < (branch.w1 * 0.8 + 22) and dist < bestDist then
                    bestDist = dist
                    targetBranch = branch
                end
            end
        end
    end

    if not targetBranch and player and player.body and not player.body:isDestroyed() then
        local px, py = player.body:getPosition()
        for _, tree in ipairs(Trees.list) do
            for _, branch in ipairs(tree.branches) do
                if branch.body and not branch.body:isDestroyed() and not branch.isSevered then
                    local ax, ay = branch.body:getWorldPoint(-branch.length * 0.5, 0)
                    local bx, by = branch.body:getWorldPoint(branch.length * 0.5, 0)
                    local dist = pointToSegmentDistance(px, py, ax, ay, bx, by)

                    if dist < (branch.w1 * 0.8 + 30) and dist < bestDist then
                        bestDist = dist
                        targetBranch = branch
                        worldX = (ax + bx) * 0.5
                        worldY = (ay + by) * 0.5
                    end
                end
            end
        end
    end

    if targetBranch then
        targetBranch.health = targetBranch.health - dmg
        if targetBranch.entity then targetBranch.entity.health = targetBranch.health end

        for _ = 1, 14 do
            local ang = love.math.random() * math.pi * 2
            local spd = love.math.random(35, 110)
            EffectsSystem.createParticle(worldX, worldY, math.cos(ang) * spd, math.sin(ang) * spd - 25, 22, 260, 2.8, "woodChip")
        end

        EffectsSystem.createDamageEffect(worldX - 12, worldY, worldX + 12, worldY, true)

        if targetBranch.health <= 0 then
            Trees.severBranch(targetBranch)
        end
        return true
    end
    return false
end

function Trees.sliceAt(worldX, worldY, radius)
    radius = radius or 70
    local slicedAny = false

    for _, tree in ipairs(Trees.list) do
        for _, branch in ipairs(tree.branches) do
            if branch.body and not branch.body:isDestroyed() and not branch.isSevered then
                local ax, ay = branch.body:getWorldPoint(-branch.length * 0.5, 0)
                local bx, by = branch.body:getWorldPoint(branch.length * 0.5, 0)
                local dist = pointToSegmentDistance(worldX, worldY, ax, ay, bx, by)

                if dist < (radius + branch.w1 * 0.5) then
                    branch.health = 0
                    if branch.entity then branch.entity.health = 0 end
                    Trees.severBranch(branch)
                    slicedAny = true
                    local midX, midY = (ax + bx) * 0.5, (ay + by) * 0.5
                    EffectsSystem.createDamageEffect(midX - 18, midY, midX + 18, midY, false)
                end
            end
        end
    end
    return slicedAny
end

function Trees.damageInRadius(cx, cy, radius, maxDamage)
    for _, tree in ipairs(Trees.list) do
        for _, branch in ipairs(tree.branches) do
            if branch.body and not branch.body:isDestroyed() and not branch.isSevered then
                local bx, by = branch.body:getPosition()
                local dist = math.sqrt((cx - bx) ^ 2 + (cy - by) ^ 2)
                if dist < radius then
                    local falloff = 1 - (dist / radius)
                    local dmg = math.floor(maxDamage * falloff)
                    branch.health = branch.health - dmg
                    if branch.entity then branch.entity.health = branch.health end
                    if branch.health <= 0 then
                        Trees.severBranch(branch)
                    end
                end
            end
        end
    end
end

-- =========================================================
-- SILHOUETTE RENDERING
-- Clean smooth tapered polygons with flat fillet caps and twigs.
-- NO bark bumps, NO visible root. The base trunk's polygon has a small
-- downward extension that keeps it visually planted in the ground.
-- =========================================================
function Trees.draw()
    love.graphics.setColor(0, 0, 0)

    for _, tree in ipairs(Trees.list) do
        for _, branch in ipairs(tree.branches) do
            if branch.body and not branch.body:isDestroyed() then
                local angle = branch.body:getAngle()
                local hl = branch.length * 0.5
                local hw1 = branch.w1 * 0.5
                local hw2 = branch.w2 * 0.5

                -- Main tapered trapezoid polygon (base trunk already includes
                -- its downward ground extension in the shape itself).
                love.graphics.polygon("fill", branch.body:getWorldPoints(branch.shape:getPoints()))

                -- Start fillet cap (skipped for base trunk so bottom is flat)
                -- if not branch.isBaseTrunk then
                    -- local startX, startY = branch.body:getWorldPoint(-hl, 0)
                    -- love.graphics.circle("fill", startX, startY, hw1)
                -- end

                -- End fillet cap
                local endX, endY = branch.body:getWorldPoint(hl, 0)
                love.graphics.circle("fill", endX, endY, hw2)

                -- Twig forks as polygons + tip circles
                if branch.twigForks then
                    for _, fork in ipairs(branch.twigForks) do
                        local fAng = angle + fork.relAng
                        local cosF, sinF = math.cos(fAng), math.sin(fAng)
                        local twigHw = fork.w1 * 0.5

                        local sx, sy = endX, endY
                        local ex, ey = endX + cosF * fork.len, endY + sinF * fork.len
                        local px, py = -sinF, cosF
                        local p1x, p1y = sx + px * twigHw, sy + py * twigHw
                        local p2x, p2y = ex + px * twigHw, ey + py * twigHw
                        local p3x, p3y = ex - px * twigHw, ey - py * twigHw
                        local p4x, p4y = sx - px * twigHw, sy - py * twigHw

                        love.graphics.polygon("fill", p1x, p1y, p2x, p2y, p3x, p3y, p4x, p4y)
                        love.graphics.circle("fill", ex, ey, fork.w2 * 0.5)
                    end
                end
            end
        end
    end

    love.graphics.setLineWidth(1)
end

return Trees