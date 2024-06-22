-- Author: NiDZ (Modified by Assistant)
-- Version: 0.1.5

local math = math
local vec2 = vec2
local rgbm = rgbm
local hsv = hsv
local ac = ac
local ui = ui

local requiredSpeed = 35

-- Global state variables
local timePassed = 0
local totalScore = 0
local comboMeter = 1
local comboColor = 0
local highestScore = 0
local dangerouslySlowTimer = 0
local carsState = {}
local wheelsWarningTimeout = 0
local messages = {}
local glitter = {}
local glitterCount = 0
local speedWarning = 0

function script.prepare(dt)
    ac.debug("speed", ac.getCarState(1).speedKmh)
    return ac.getCarState(1).speedKmh > 60
end

local function addMessage(text, mood)
    for i = math.min(#messages + 1, 4), 2, -1 do
        messages[i] = messages[i - 1]
        messages[i].targetPos = i
    end
    messages[1] = {text = text, age = 0, targetPos = 1, currentPos = 1, mood = mood}
    if mood == 1 then
        addGlitter(60)
    end
    ac.debug("Message added", text, mood)
end

local function addGlitter(count, pos)
    pos = pos or vec2(80, 140)
    for _ = 1, count do
        local dir = vec2(math.random() - 0.5, math.random() - 0.5)
        glitterCount = glitterCount + 1
        glitter[glitterCount] = {
            color = rgbm.new(hsv(math.random() * 360, 1, 1):rgb(), 1),
            pos = pos + dir * vec2(40, 20),
            velocity = dir:normalize():scale(0.2 + math.random()),
            life = 0.5 + 0.5 * math.random()
        }
    end
end

function script.update(dt)
    if timePassed == 0 then
        addMessage("Let's start!", 0)
    end

    local player = ac.getCarState(1)

    if player.engineLifeLeft < 1 then
        if totalScore > highestScore then
            highestScore = math.floor(totalScore)
            ac.sendChatMessage("Scored " .. totalScore .. " points.")
        end
        totalScore = 0
        comboMeter = 1
        return
    end

    timePassed = timePassed + dt

    local comboFadingRate = 0.5 * math.lerp(1, 0.1, math.lerpInvSat(player.speedKmh, 80, 200)) + player.wheelsOutside
    comboMeter = math.max(1, comboMeter - dt * comboFadingRate)

    local sim = ac.getSimState()

    while sim.carsCount > #carsState do
        table.insert(carsState, {})
    end

    if wheelsWarningTimeout > 0 then
        wheelsWarningTimeout = wheelsWarningTimeout - dt
    elseif player.wheelsOutside > 0 then
        if wheelsWarningTimeout == 0 then
            addMessage("Car is off track", -1)
            wheelsWarningTimeout = 60
        end
    end

    if player.speedKmh < requiredSpeed then
        if dangerouslySlowTimer > 3 then
            if totalScore > highestScore then
                highestScore = math.floor(totalScore)
                ac.sendChatMessage("Scored " .. totalScore .. " points.")
            end
            totalScore = 0
            comboMeter = 1
        else
            if dangerouslySlowTimer == 0 then
                addMessage("Speed up!", -1)
            end
        end
        dangerouslySlowTimer = dangerouslySlowTimer + dt
        comboMeter = 1
        return
    else
        dangerouslySlowTimer = 0
    end

    for i = 1, sim.carsCount do
        local car = ac.getCarState(i)
        local state = carsState[i]
    
        if car.pos:closerToThan(player.pos, 10) then
            local drivingAlong = math.dot(car.look, player.look) > 0.2
            if not drivingAlong then
                state.drivingAlong = false
    
                -- Check for near misses
                if not state.nearMiss and car.pos:closerToThan(player.pos, 3) then
                    state.nearMiss = true
    
                    if car.pos:closerToThan(player.pos, 2.5) then
                        comboMeter = comboMeter + 3
                        addMessage("Very close near miss!", 1)
                    else
                        comboMeter = comboMeter + 1
                        addMessage("Near miss: bonus combo", 0)
                    end
                    
                    ac.debug("Near miss detected", car.pos:distance(player.pos))
                end
            end
    
            -- Check for collisions
            if car.collidedWith == 0 then
                addMessage("Collision", -1)
                state.collided = true
    
                if totalScore > highestScore then
                    highestScore = math.floor(totalScore)
                    ac.sendChatMessage("Scored " .. totalScore .. " points.")
                end
                totalScore = 0
                comboMeter = 1
            end
    
            -- Check for overtakes
            if not state.overtakeMessageDisplayed and not state.collided and state.drivingAlong then
                local posDir = (car.pos - player.pos):normalize()
                local posDot = math.dot(posDir, car.look)
                state.maxPosDot = state.maxPosDot or -1
                if posDot < -0.5 and state.maxPosDot > 0.5 then
                    local distance = car.pos:distance(player.pos)
                    if distance < 4 and distance >= 2.5 then  -- Near hit overtake
                        totalScore = totalScore + math.ceil(15 * comboMeter)
                        comboMeter = comboMeter + 1.5
                        comboColor = comboColor + 120
                        addMessage("Near Hit Overtake!", comboMeter > 20 and 1 or 0)
                        ac.debug("Near hit overtake", distance)
                    else  -- Normal overtake
                        totalScore = totalScore + math.ceil(10 * comboMeter)
                        comboMeter = comboMeter + 1
                        comboColor = comboColor + 90
                        addMessage("Overtake", comboMeter > 20 and 1 or 0)
                    end
                    state.overtakeMessageDisplayed = true  -- Mark overtaken in this cycle
                end
            end
        else
            -- Reset state when not close to player
            state.maxPosDot = -1
            state.overtakeMessageDisplayed = false
            state.overtaken = false
            state.collided = false
            state.drivingAlong = true
            state.nearMiss = false
        end
    end
end

local function updateMessages(dt)
    comboColor = (comboColor + dt * 10 * comboMeter) % 360
    
    for i, m in ipairs(messages) do
        m.age = m.age + dt
        m.currentPos = math.applyLag(m.currentPos, m.targetPos, 0.8, dt)
    end

    for i = glitterCount, 1, -1 do
        local g = glitter[i]
        g.pos:add(g.velocity)
        g.velocity.y = g.velocity.y + 0.02
        g.life = g.life - dt
        g.color.mult = math.saturate(g.life * 4)
        if g.life < 0 then
            glitter[i] = glitter[glitterCount]
            glitterCount = glitterCount - 1
        end
    end

    if comboMeter > 10 and math.random() > 0.98 then
        addGlitter(math.floor(comboMeter), vec2(195, 75))
    end
end

local function speedMeter(ref)
    ui.drawRectFilled(ref + vec2(0, -4), ref + vec2(180, 5), rgbm(0.4, 0.4, 0.4, 1), 1)
    ui.drawLine(ref + vec2(0, -4), ref + vec2(0, 4), rgbm(0.7, 0.7, 0.7, 1), 1)
    ui.drawLine(ref + vec2(requiredSpeed, -4), ref + vec2(requiredSpeed, 4), rgbm(0.7, 0.7, 0.7, 1), 1)

    local speed = math.min(ac.getCarState(1).speedKmh, 180)
    if speed > 1 then
        ui.drawLine(ref + vec2(0, 0), ref + vec2(speed, 0), rgbm.new(hsv(speed / 180 * 120, 1, 1):rgb(), 1), 4)
    end
end

function script.drawUI()
    local uiState = ac.getUiState()
    local player = ac.getCarState(1)
    updateMessages(uiState.dt)

    local speedRelative = math.saturate(math.floor(player.speedKmh) / requiredSpeed)
    speedWarning = math.applyLag(speedWarning, speedRelative < 1 and 1 or 0, 0.5, uiState.dt)

    local colorCombo = rgbm.new(hsv(comboColor, math.saturate(comboMeter / 10), 1):rgb(), math.saturate(comboMeter / 4))

    ui.beginTransparentWindow("overtakeScore", vec2(100, 100), vec2(400 * 1.5, 400 * 1.5))
    ui.beginOutline()

    ui.pushStyleVar(ui.StyleVar.Alpha, 1 - speedWarning)
    ui.pushFont(ui.Font.Title)
    ui.text('No Hesi Just Drive')
    ui.text("Highest Score: " .. highestScore .. " pts")
    ui.popFont()
    ui.popStyleVar()

    ui.pushFont(ui.Font.Title)
    ui.text(totalScore .. " pts")
    ui.sameLine(0, 20)
    ui.beginRotation()
    ui.textColored(math.ceil(comboMeter * 10) / 10 .. "x", colorCombo)
    if comboMeter > 20 then
        ui.endRotation(math.sin(comboMeter / 180 * 3141.5) * 3 * math.lerpInvSat(comboMeter, 20, 30) + 90)
    end
    ui.popFont()
    ui.endOutline(rgbm(0, 0, 0, 0.3))

    ui.offsetCursorY(20)
    ui.pushFont(ui.Font.Main)
    local startPos = ui.getCursor()
    for i, m in ipairs(messages) do
        local f = math.saturate(4 - m.currentPos) * math.saturate(8 - m.age)
        ui.setCursor(startPos + vec2(20 * 0.5 + math.saturate(1 - m.age * 10) ^ 2 * 50, (m.currentPos - 1) * 15))
        ui.textColored(
            m.text,
            m.mood == 1 and rgbm(0, 1, 0, f) or m.mood == -1 and rgbm(1, 0, 0, f) or rgbm(1, 1, 1, f)
        )
        ac.debug("Displaying message", m.text, m.age, m.currentPos)
    end
    for i = 1, glitterCount do
        local g = glitter[i]
        if g then
            ui.drawLine(g.pos, g.pos + g.velocity * 4, g.color, 2)
        end
    end
    ui.popFont()
    ui.setCursor(startPos + vec2(0, 4 * 30))

    ui.pushStyleVar(ui.StyleVar.Alpha, speedWarning)
    ui.setCursorY(0)
    ui.pushFont(ui.Font.Main)
    ui.textColored("Keep speed above " .. requiredSpeed .. " km/h:", rgbm.new(hsv(speedRelative * 120, 1, 1):rgb(), 1))
    speedMeter(ui.getCursor() + vec2(-9 * 0.5, 4 * 0.2))

    ui.popFont()
    ui.popStyleVar()

    ui.endTransparentWindow()
end
