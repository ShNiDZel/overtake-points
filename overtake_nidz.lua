-- Author: NiDZ (Modified by Assistant)
-- Version: 0.2.0

local math, vec2, rgbm, hsv, ac, ui = math, vec2, rgbm, hsv, ac, ui

-- Constants
local REQUIRED_SPEED = 35
local MAX_MESSAGES = 4
local NEAR_MISS_DISTANCE = 3
local VERY_CLOSE_NEAR_MISS_DISTANCE = 2.5
local OVERTAKE_DISTANCE = 4

-- Global state variables
local timeElapsed, totalScore, comboMeter, comboColor, highestScore = 0, 0, 1, 0, 0
local dangerouslySlowTimer, wheelsWarningTimeout, glitterCount, speedWarning = 0, 0, 0, 0
local carsState, messages, glitter, serverScores = {}, {}, {}, {}
local playerName, playerRanking = "", 1

-- Message arrays
local overtakeMessages = {
    "Nice Overtake", "Smooth Move", "Perfect Pass", "Slick Maneuver", "Clean Overtake"
}
local nearHitOvertakeMessages = {
    "That's So Close!", "Cutting It Fine!", "Threading the Needle!",
    "Razor-thin Margin!", "Daring Move!"
}

-- Helper functions
local function getRandomMessage(messageArray)
    return messageArray[math.random(#messageArray)]
end

local function addMessage(text, mood)
    table.insert(messages, 1, {text = text, age = 0, targetPos = 1, currentPos = 1, mood = mood})
    if #messages > MAX_MESSAGES then table.remove(messages) end
    if mood == 1 then addGlitter(60) end
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

local function updatePlayerRanking()
    playerRanking = 1
    for name, score in pairs(serverScores) do
        if name ~= playerName and score > highestScore then
            playerRanking = playerRanking + 1
        end
    end
end

local function sendScore()
    ac.sendChatMessage("SCORE:" .. playerName .. ":" .. highestScore)
end

local function parseScoreMessage(message)
    local prefix, name, score = message:match("(SCORE:)(%S+):(%d+)")
    if prefix == "SCORE:" and name and score then
        serverScores[name] = tonumber(score)
        updatePlayerRanking()
    end
end

local function initializePlayer()
    playerName = ac.getDriverName(0)
    serverScores[playerName] = 0
end

local function updateCombo(player, dt)
    local comboFadingRate = 0.5 * math.lerp(1, 0.1, math.lerpInvSat(player.speedKmh, 80, 200)) + player.wheelsOutside
    comboMeter = math.max(1, comboMeter - dt * comboFadingRate)
end

local function checkWheelsWarning(player, dt)
    if wheelsWarningTimeout > 0 then
        wheelsWarningTimeout = wheelsWarningTimeout - dt
    elseif player.wheelsOutside > 0 and wheelsWarningTimeout == 0 then
        addMessage("Car is off track", -1)
        wheelsWarningTimeout = 60
    end
end

local function checkSpeed(player, dt)
    if player.speedKmh < REQUIRED_SPEED then
        if dangerouslySlowTimer > 3 then
            if totalScore > highestScore then
                highestScore = math.floor(totalScore)
                ac.sendChatMessage("Scored " .. totalScore .. " points.")
            end
            totalScore, comboMeter = 0, 1
        else
            if dangerouslySlowTimer == 0 then addMessage("Speed up!", -1) end
        end
        dangerouslySlowTimer = dangerouslySlowTimer + dt
        comboMeter = 1
        return true
    else
        dangerouslySlowTimer = 0
        return false
    end
end

local function updateScore()
    if totalScore > highestScore then
        highestScore = math.floor(totalScore)
        serverScores[playerName] = highestScore
        sendScore()
        updatePlayerRanking()
    end
end

local function handleNearMiss(state, distance)
    state.nearMiss = true
    if distance < VERY_CLOSE_NEAR_MISS_DISTANCE then
        comboMeter = comboMeter + 3
        addMessage("Very close near miss!", 1)
    else
        comboMeter = comboMeter + 1
        addMessage("Near miss: bonus combo", 0)
    end
    ac.debug("Near miss detected", distance)
end

local function handleOvertake(state, distance)
    totalScore = totalScore + math.ceil(10 * comboMeter)
    if distance < OVERTAKE_DISTANCE and distance >= VERY_CLOSE_NEAR_MISS_DISTANCE then
        comboMeter = comboMeter + 3.5
        comboColor = comboColor + 120
        addMessage(getRandomMessage(nearHitOvertakeMessages), comboMeter > 20 and 1 or 0)
        ac.debug("Near hit overtake", distance)
    else
        comboMeter = comboMeter + 3
        comboColor = comboColor + 90
        addMessage(getRandomMessage(overtakeMessages), comboMeter > 20 and 1 or 0)
    end
    state.overtaken = true
end

-- Main functions
function script.prepare(dt)
    ac.debug("speed", ac.getCarState(1).speedKmh)
    return ac.getCarState(1).speedKmh > 60
end

function script.update(dt)
    if timeElapsed == 0 then
        initializePlayer()
        addMessage("Let's start!", 0)
    end

    local player = ac.getCarState(1)
    if player.engineLifeLeft < 1 then
        if totalScore > highestScore then
            highestScore = math.floor(totalScore)
            ac.sendChatMessage("Scored " .. highestScore .. " points.")
            sendScore()
        end
        totalScore, comboMeter = 0, 1
        return
    end

    timeElapsed = timeElapsed + dt
    updateCombo(player, dt)
    checkWheelsWarning(player, dt)
    if checkSpeed(player, dt) then return end
    updateScore()

    local sim = ac.getSimState()
    while sim.carsCount > #carsState do table.insert(carsState, {}) end

    for i = 1, sim.carsCount do
        local car = ac.getCarState(i)
        local state = carsState[i]

        if car.pos:closerToThan(player.pos, 10) then
            local drivingAlong = math.dot(car.look, player.look) > 0.2
            if not drivingAlong then
                state.drivingAlong = false
                if not state.nearMiss and car.pos:closerToThan(player.pos, NEAR_MISS_DISTANCE) then
                    handleNearMiss(state, car.pos:distance(player.pos))
                end
            end

            if car.collidedWith == 0 then
                addMessage("Collision", -1)
                state.collided = true
                if totalScore > highestScore then
                    highestScore = math.floor(totalScore)
                    ac.sendChatMessage("Scored " .. totalScore .. " points.")
                end
                totalScore, comboMeter = 0, 1
            end

            if not state.overtaken and not state.collided and state.drivingAlong then
                local posDir = (car.pos - player.pos):normalize()
                local posDot = math.dot(posDir, car.look)
                state.maxPosDot = math.max(state.maxPosDot or -1, posDot)
                if posDot < -0.5 and state.maxPosDot > 0.5 then
                    handleOvertake(state, car.pos:distance(player.pos))
                end
            end
        else
            state.maxPosDot, state.overtaken, state.collided = -1, false, false
            state.drivingAlong, state.nearMiss = true, false
        end
    end
end

function script.onChatMessage(message)
    parseScoreMessage(message)
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
            if i < glitterCount then glitter[i] = glitter[glitterCount] end
            glitterCount = glitterCount - 1
        end
    end
    if comboMeter > 10 and math.random() > 0.98 then
        addGlitter(math.floor(comboMeter), vec2(195, 75))
    end
end

function script.drawUI()
    local uiState = ac.getUiState()
    updateMessages(uiState.dt)

    local speedRelative = math.saturate(math.floor(ac.getCarState(1).speedKmh) / REQUIRED_SPEED)
    speedWarning = math.applyLag(speedWarning, speedRelative < 1 and 1 or 0, 0.5, uiState.dt)

    local colorDark = rgbm(0.4, 0.4, 0.4, 1)
    local colorGrey = rgbm(0.7, 0.7, 0.7, 1)
    local colorAccent = rgbm.new(hsv(speedRelative * 120, 1, 1):rgb(), 1)
    local colorCombo = rgbm.new(hsv(comboColor, math.saturate(comboMeter / 10), 1):rgb(), math.saturate(comboMeter / 4))

    local function speedMeter(ref)
        ui.drawRectFilled(ref + vec2(0, -4), ref + vec2(180, 5), colorDark, 1)
        ui.drawLine(ref + vec2(0, -4), ref + vec2(0, 4), colorGrey, 1)
        ui.drawLine(ref + vec2(REQUIRED_SPEED, -4), ref + vec2(REQUIRED_SPEED, 4), colorGrey, 1)

        local speed = math.min(ac.getCarState(1).speedKmh, 180)
        if speed > 1 then
            ui.drawLine(ref + vec2(0, 0), ref + vec2(speed, 0), colorAccent, 4)
        end
    end

    ui.beginTransparentWindow("overtakeScore", vec2(200, 100), vec2(400 * 2.5, 400 * 2.5))
    ui.beginOutline()

    ui.pushStyleVar(ui.StyleVar.Alpha, 1 - speedWarning)
    ui.pushFont(ui.Font.Title)
    ui.text('No HESI BABY!!!')
    ui.text("Highest Score: " .. highestScore .. " pts")
    ui.text("Current Score: " .. math.floor(totalScore) .. " pts")
    ui.text("Your Ranking: " .. playerRanking .. " / " .. table.count(serverScores))
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
        ui.textColored(m.text, m.mood == 1 and rgbm(0, 1, 0, f) or m.mood == -1 and rgbm(1, 0, 0, f) or rgbm(1, 1, 1, f))
    end
    for i = 1, glitterCount do
        local g = glitter[i]
        if g then ui.drawLine(g.pos, g.pos + g.velocity * 4, g.color, 2) end
    end
    ui.popFont()
    ui.setCursor(startPos + vec2(0, 4 * 30))

    ui.pushStyleVar(ui.StyleVar.Alpha, speedWarning)
    ui.setCursorY(0)
    ui.pushFont(ui.Font.Main)
    ui.textColored("Keep speed above " .. REQUIRED_SPEED .. " km/h:", colorAccent)
    speedMeter(ui.getCursor() + vec2(-9 * 0.5, 4 * 0.2))

    ui.popFont()
    ui.popStyleVar()

    ui.endTransparentWindow()
end
