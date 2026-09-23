local EffectsSystem = {
    particles = {},
    damageEffects = {},
    shockwaves = {},
    flashes = {}
}

local function radiumT(mergePower)
    return math.min(1, math.max(0, ((mergePower or 1) - 1) / 9))
end

local function lerp(a, b, t) return a + (b - a) * t end

function EffectsSystem.createFlash(x, y, radius, intensity, colorType, mergePower)
    table.insert(EffectsSystem.flashes, {
        x = x, y = y,
        radius = radius,
        currentRadius = 0,
        life = 0.15,
        maxLife = 0.15,
        intensity = math.min(1, intensity),
        colorType = colorType or "fire",
        mergePower = mergePower or 1
    })
end

function EffectsSystem.createShockwave(x, y, radius, intensity, colorType, mergePower)
    table.insert(EffectsSystem.shockwaves, {
        x = x, y = y,
        radius = radius,
        currentRadius = 5,
        life = 0.4,
        maxLife = 0.4,
        intensity = math.min(1, intensity),
        colorType = colorType or "fire",
        mergePower = mergePower or 1
    })
end

function EffectsSystem.createDamageEffect(x1, y1, x2, y2, isLessIntense)
    table.insert(EffectsSystem.damageEffects, {
        x1 = x1, y1 = y1,
        x2 = x2, y2 = y2,
        life = isLessIntense and 0.12 or 0.30,
        isLessIntense = isLessIntense,
        type = "cutLine"
    })
    
    local numSparks = isLessIntense and 2 or 12
    for i = 1, numSparks do
        local t = love.math.random()
        local sparkX = x1 + (x2 - x1) * t
        local sparkY = y1 + (y2 - y1) * t
        
        local angle = love.math.random() * math.pi * 2
        local speed = isLessIntense and love.math.random(20, 50) or love.math.random(40, 90)
        local vx = math.cos(angle) * speed
        local vy = math.sin(angle) * speed
        
        EffectsSystem.createParticle(sparkX, sparkY, vx, vy, 12, 350, 1.5, "orangeSpark")
    end
end

function EffectsSystem.createParticle(x, y, vx, vy, life, fadeSpeed, size, pType, mergePower)
    table.insert(EffectsSystem.particles, {
        x = x, y = y, vx = vx, vy = vy,
        life = life, fadeSpeed = fadeSpeed,
        size = size or 2, type = pType, scale = 1,
        mergePower = mergePower or 1
    })
end

function EffectsSystem.update(dt)
    for i = #EffectsSystem.damageEffects, 1, -1 do
        local fx = EffectsSystem.damageEffects[i]
        fx.life = fx.life - dt
        if fx.life <= 0 then table.remove(EffectsSystem.damageEffects, i) end
    end
    
    for i = #EffectsSystem.particles, 1, -1 do
        local p = EffectsSystem.particles[i]
        p.life = p.life - dt * (p.fadeSpeed or 200)
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        p.vy = p.vy + 0.05
        if p.scale then p.scale = p.scale - dt * 2 end
        if p.life <= 0 then table.remove(EffectsSystem.particles, i) end
    end
    
    for i = #EffectsSystem.shockwaves, 1, -1 do
        local sw = EffectsSystem.shockwaves[i]
        sw.life = sw.life - dt
        if sw.life <= 0 then
            table.remove(EffectsSystem.shockwaves, i)
        else
            local t = 1 - (sw.life / sw.maxLife)
            sw.currentRadius = sw.radius * t
        end
    end
    
    for i = #EffectsSystem.flashes, 1, -1 do
        local f = EffectsSystem.flashes[i]
        f.life = f.life - dt
        if f.life <= 0 then
            table.remove(EffectsSystem.flashes, i)
        else
            local t = 1 - (f.life / f.maxLife)
            f.currentRadius = f.radius * t
        end
    end
end

function EffectsSystem.draw()
    for _, fx in ipairs(EffectsSystem.damageEffects) do
        if fx.type == "cutLine" then
            local alpha = math.min(1, fx.life * 4)
            if fx.isLessIntense then alpha = alpha * 0.35 end
            
            love.graphics.setLineWidth(fx.isLessIntense and 3 or 6)
            love.graphics.setColor(1, 0.25, 0, alpha * 0.4)
            love.graphics.line(fx.x1, fx.y1, fx.x2, fx.y2)
            
            love.graphics.setLineWidth(fx.isLessIntense and 1.5 or 3)
            love.graphics.setColor(1, 0.50, 0, alpha * 0.7)
            love.graphics.line(fx.x1, fx.y1, fx.x2, fx.y2)
            
            if not fx.isLessIntense then
                love.graphics.setLineWidth(1.2)
                love.graphics.setColor(1, 0.85, 0.3, alpha)
                love.graphics.line(fx.x1, fx.y1, fx.x2, fx.y2)
            end
            
            love.graphics.setLineWidth(1)
        end
    end
    
    -- Draw flashes (bright expanding circles)
    for _, f in ipairs(EffectsSystem.flashes) do
        local alpha = f.intensity * (1 - f.life / f.maxLife) * 0.9
        if f.colorType == "radium" then
            local t = radiumT(f.mergePower)
            love.graphics.setColor(lerp(0.10, 0.60, t), 0.9, lerp(0.20, 0.05, t), alpha * 0.5)
            love.graphics.circle("fill", f.x, f.y, f.currentRadius * 1.2)
            love.graphics.setColor(lerp(0.30, 0.90, t), 1.0, lerp(0.40, 0.10, t), alpha)
            love.graphics.circle("fill", f.x, f.y, f.currentRadius)
            love.graphics.setColor(lerp(0.80, 1.00, t), 1.0, lerp(0.90, 0.60, t), alpha * 0.85)
            love.graphics.circle("fill", f.x, f.y, f.currentRadius * 0.5)
        else
            love.graphics.setColor(1, 0.8, 0.3, alpha * 0.5)
            love.graphics.circle("fill", f.x, f.y, f.currentRadius * 1.2)
            love.graphics.setColor(1, 0.9, 0.5, alpha)
            love.graphics.circle("fill", f.x, f.y, f.currentRadius)
            love.graphics.setColor(1, 1, 0.9, alpha * 0.8)
            love.graphics.circle("fill", f.x, f.y, f.currentRadius * 0.5)
        end
    end
    
    for _, p in ipairs(EffectsSystem.particles) do
        local alpha = math.min(1, p.life / 50)
        
        if p.type == "thruster" then
            love.graphics.setColor(1, 0.5 + (p.life / 100) * 0.5, 0, alpha * 0.8)
        elseif p.type == "enemy_thruster" then
            love.graphics.setColor(1, 0.2 + (p.life / 100) * 0.3, 0, alpha * 0.7)
        elseif p.type == "orangeSpark" then
            local intensity = 0.8 + math.random() * 0.4
            love.graphics.setColor(1, 0.5 * intensity, 0.1, alpha)
        elseif p.type == "ember" then
            love.graphics.setColor(1, 0.4, 0.05, alpha * 0.9)
        elseif p.type == "radiumSpark" or p.type == "greenSpark" then
            local intensity = 0.8 + math.random() * 0.4
            local t = radiumT(p.mergePower)
            love.graphics.setColor(lerp(0.40, 0.95, t) * intensity, 1.0, lerp(0.60, 0.10, t) * intensity, alpha)
        elseif p.type == "radiumGlow" then
            local t = radiumT(p.mergePower)
            love.graphics.setColor(lerp(0.15, 0.85, t), 1.0, lerp(0.35, 0.10, t), alpha * 0.85)
        elseif p.type == "radiumSmoke" then
            local t = radiumT(p.mergePower)
            love.graphics.setColor(lerp(0.10, 0.45, t), lerp(0.30, 0.40, t), lerp(0.15, 0.10, t), alpha * 0.45)
        elseif p.type == "smoke" then
            love.graphics.setColor(0.3, 0.3, 0.3, alpha * 0.5)
        elseif p.type == "debris" then
            love.graphics.setColor(0.3, 0.2, 0.1, alpha)
            love.graphics.rectangle("fill", p.x - p.size/2, p.y - p.size/2, p.size, p.size)
        elseif p.type == "grassDebris" then
            local r = 0.70 + math.random() * 0.15
            local g = 0.65 + math.random() * 0.15
            local b = 0.12
            love.graphics.setColor(r, g, b, alpha * 0.9)
            love.graphics.rectangle("fill", p.x - p.size/2, p.y - p.size, p.size, p.size * 2)
        elseif p.type == "flame" then
            local t = math.min(1, p.life / 20)
            local r = 1.0
            local g = math.max(0.1, math.min(1.0, t * 1.3))
            local b = math.max(0.0, math.min(0.8, (t - 0.4) * 1.5))
            love.graphics.setColor(r, g, b, alpha * 0.9)
        elseif p.type == "steam" then
            local shade = 0.85 + math.random() * 0.15
            love.graphics.setColor(shade, shade, shade, alpha * 0.4)
        elseif p.type == "water" then
            local blue = 0.5 + math.random() * 0.5
            love.graphics.setColor(0.2, 0.5, blue, alpha * 0.8)
        else
            love.graphics.setColor(1, 1, 1, alpha)
        end
        
        local sz = (p.size or 2) * (p.scale or 1)
        love.graphics.circle("fill", p.x, p.y, math.max(0.5, sz))
    end
    
    for _, sw in ipairs(EffectsSystem.shockwaves) do
        local alpha = sw.intensity * (sw.life / sw.maxLife) * 0.8
        if sw.colorType == "radium" then
            local t = radiumT(sw.mergePower)
            love.graphics.setColor(lerp(0.20, 0.90, t), 1.0, lerp(0.30, 0.05, t), alpha)
            love.graphics.setLineWidth(4 * sw.intensity)
            love.graphics.circle("line", sw.x, sw.y, sw.currentRadius)
            love.graphics.setLineWidth(2 * sw.intensity)
            love.graphics.setColor(lerp(0.60, 1.00, t), 1.0, lerp(0.70, 0.30, t), alpha * 0.7)
            love.graphics.circle("line", sw.x, sw.y, sw.currentRadius * 0.7)
        else
            love.graphics.setColor(1, 0.6, 0.2, alpha)
            love.graphics.setLineWidth(4 * sw.intensity)
            love.graphics.circle("line", sw.x, sw.y, sw.currentRadius)
            love.graphics.setLineWidth(2 * sw.intensity)
            love.graphics.setColor(1, 0.9, 0.4, alpha * 0.7)
            love.graphics.circle("line", sw.x, sw.y, sw.currentRadius * 0.7)
        end
    end
    love.graphics.setLineWidth(1)
end

return EffectsSystem