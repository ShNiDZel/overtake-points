-- Author: NiDZ
-- Version: 0.9.2.1

-- Constants
local requiredSpeed = 25

-- Game State Variables
local timePassed = 0
local totalScore = 0
local comboMeter = 1
local comboColor = 0
local highestScore = 0
local dangerouslySlowTimer = 0
local carsState = {}
local wheelsWarningTimeout = 0

-- Utility function to initialize car state
local function initializeCarState(index)
    carsState[index] = {
        maxPosDot = -1,
        overtaken = false,
        collided = false,
        drivingAlong = true,
        nearMissHandled = false,  -- Track if near miss has been handled
        nearHitOvertakeHandled = false  -- Track if near hit during overtaking has been handled
    }
end

-- Prepare function to run before the main start
function script.prepare(dt)
    -- Initialize carsState for existing cars at the start
    local sim = ac.getSimState()
    for i = 1, sim.carsCount do
        initializeCarState(i)
    end
end

-- Function to handle near misses
local function handleNearMiss(car, player, state)
    local nearMissThreshold = 5
    local veryCloseNearMissThreshold = 3

    -- Check if the near miss condition is met
    if not state.nearMissHandled and car.pos:closerToThan(player.pos, nearMissThreshold) then
        if car.pos:closerToThan(player.pos, veryCloseNearMissThreshold) then
            totalScore = totalScore + math.ceil(10 * comboMeter)
            comboMeter = comboMeter + 3
            comboColor = comboColor + 90
            addMessage("Very close near miss!", comboMeter > 10 and 1 or 0)
        else
            totalScore = totalScore + math.ceil(15 * comboMeter)
            comboMeter = comboMeter + 1
            comboColor = comboColor + 90
            addMessage("Near miss: bonus combo", comboMeter > 15 and 1 or 0)
        end
        state.nearMissHandled = true
    end
end

-- Function to handle collisions
local function handleCollision(car, player, state)
    if not state.collided and car.collidedWith == 0 then
        addMessage("Collision", -1)
        state.collided = true

        if totalScore > highestScore then
            highestScore = math.floor(totalScore)
            ac.sendChatMessage("Score " .. totalScore .. " Total Points")
        end
        totalScore = 0
        comboMeter = 1
    end
end

-- Function to handle overtakes and near hits during overtaking
local function handleOvertake(car, player, state)
    local posDir = (car.pos - player.pos):normalize()
    local posDot = math.dot(posDir, car.look)
    state.maxPosDot = math.max(state.maxPosDot, posDot)

    -- Check for near hit during overtaking
    local nearHitThreshold = 2.0
    if not state.nearHitOvertakeHandled and car.pos:closerToThan(player.pos, nearHitThreshold) then
        totalScore = totalScore + math.ceil(5 * comboMeter)
        comboMeter = comboMeter + 1
        comboColor = comboColor + 90
        addMessage("Near hit during overtaking", comboMeter > 10 and 1 or 0)
        state.nearHitOvertakeHandled = true
    end

    -- Check for successful overtake
    if posDot < -0.5 and state.maxPosDot > 0.5 then
        totalScore = totalScore + math.ceil(20 * comboMeter)
        comboMeter = comboMeter + 2
        comboColor = comboColor + 90
        addMessage("Overtake", comboMeter > 20 and 1 or 0)
        state.overtaken = true
    end
end

-- Main update function to be called every frame
function script.update(dt)
    -- When time passes 0, display the "Start!" message
    if timePassed == 0 then
        addMessage("Lets GO!!!", 0)
    end

    -- Get the car state
    local player = ac.getCarState(1)

    -- If the engine life is less than 1
    if player.engineLifeLeft < 1 then
        -- If the score is higher than the previous one
        if totalScore > highestScore then
            highestScore = math.floor(totalScore)
            -- Send in-game chat to the server
            ac.sendChatMessage("Score " .. totalScore .. " Total Points")
        end
        -- Reset everything when total score is 0
        totalScore = 0
        comboMeter = 1
        return
    end

    -- Increase the time elapsed from the last frame
    timePassed = timePassed + dt

    -- Calculate combo fading rate based on time and car speed
    local comboFadingRate = 0.5 * math.lerp(1, 0.1, math.lerpInvSat(player.speedKmh, 80, 200)) + player.wheelsOutside
    comboMeter = math.max(1, comboMeter - dt * comboFadingRate)

    -- Get the simulation state
    local sim = ac.getSimState()

    -- Decrease the wheels warning timeout if it is greater than 0
    if wheelsWarningTimeout > 0 then
        wheelsWarningTimeout = wheelsWarningTimeout - dt
    elseif player.wheelsOutside > 0 then
        -- Display a warning message if the car's wheels are outside the track
        if wheelsWarningTimeout == 0 then
            addMessage("Car is outside", -1)
        end
        wheelsWarningTimeout = 60
    end

    -- Check if the player's speed is below the required speed
    if player.speedKmh < requiredSpeed then
        if dangerouslySlowTimer > 3 then
            if totalScore > highestScore then
                highestScore = math.floor(totalScore)
                ac.sendChatMessage("scored " .. totalScore .. " points.")
            end
            totalScore = 0
            comboMeter = 1
        else
            if dangerouslySlowTimer == 0 then
                addMessage("Too Slow BRO!!!", -1)
            end
        end
        dangerouslySlowTimer = dangerouslySlowTimer + dt
        comboMeter = 1
        return
    else
        dangerouslySlowTimer = 0
    end

    -- Process each car in the simulation
    for i = 1, sim.carsCount do
        local car = ac.getCarState(i)
        local state = carsState[i]

        -- Reset near miss handling flag if car is no longer close
        if not car.pos:closerToThan(player.pos, 10) then
            state.nearMissHandled = false
        end

        -- Reset near hit overtaking handling flag if car is no longer close or overtaken
        if not car.pos:closerToThan(player.pos, 10) or state.overtaken then
            state.nearHitOvertakeHandled = false
        end

        if car.pos:closerToThan(player.pos, 10) then
            local drivingAlong = math.dot(car.look, player.look) > 0.5
            if not drivingAlong then
                state.drivingAlong = false

                -- Only handle near miss if it hasn't been handled yet
                if not state.nearMissHandled then
                    handleNearMiss(car, player, state)
                end
            end

            -- Check and handle collision only if not already handled
            if not state.collided then
                handleCollision(car, player, state)
            end

            -- Only handle overtake if the car is not collided and driving along
            if not state.overtaken and not state.collided and state.drivingAlong then
                handleOvertake(car, player, state)
            end
        else
            -- Reset state if the car is no longer close to the player
            state.maxPosDot = -1
            state.overtaken = false
            state.collided = false
            state.drivingAlong = true
            state.nearMissHandled = false
            state.nearHitOvertakeHandled = false
        end
    end
end

local messages = {}
local glitter = {}
local glitterCount = 0

function addMessage(text, mood)
    for i = math.min(#messages + 1, 4), 2, -1 do
        messages[i] = messages[i - 1]
        messages[i].targetPos = i
    end
    messages[1] = {text = text, age = 0, targetPos = 1, currentPos = 1, mood = mood}
    if mood == 1 then
        for i = 1, 60 do
            local dir = vec2(math.random() - 0.5, math.random() - 0.5)
            glitterCount = glitterCount + 1
            glitter[glitterCount] = {
                color = rgbm.new(hsv(math.random() * 360, 1, 1):rgb(), 1),
                pos = vec2(80, 140) + dir * vec2(40, 20),
                velocity = dir:normalize():scale(0.2 + math.random()),
                life = 0.5 + 0.5 * math.random()
            }
        end
    end
end

local function updateMessages(dt)
    comboColor = comboColor + dt * 10 * comboMeter
    if comboColor > 360 then
        comboColor = comboColor - 360
    end
    for i = 1, #messages do
        local m = messages[i]
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
            if i < glitterCount then
                glitter[i] = glitter[glitterCount]
            end
            glitterCount = glitterCount - 1
        end
    end
    if comboMeter > 10 and math.random() > 0.98 then
        for i = 1, math.floor(comboMeter) do
            local dir = vec2(math.random() - 0.5, math.random() - 0.5)
            glitterCount = glitterCount + 1
            glitter[glitterCount] = {
                color = rgbm.new(hsv(math.random() * 360, 1, 1):rgb(), 1),
                pos = vec2(195, 75) + dir * vec2(40, 20),
                velocity = dir:normalize():scale(0.2 + math.random()),
                life = 0.5 + 0.5 * math.random()
            }
        end
    end
end

local speedWarning = 0
    function script.drawUI()
        local uiState = ac.getUiState()
        updateMessages(uiState.dt)

        local speedRelative = math.saturate(math.floor(ac.getCarState(1).speedKmh) / requiredSpeed)
        speedWarning = math.applyLag(speedWarning, speedRelative < 1 and 1 or 0, 0.5, uiState.dt)

        local colorDark = rgbm(0.4, 0.4, 0.4, 1)
        local colorGrey = rgbm(0.7, 0.7, 0.7, 1)
        local colorAccent = rgbm.new(hsv(speedRelative * 120, 1, 1):rgb(), 1)
        local colorCombo =
            rgbm.new(hsv(comboColor, math.saturate(comboMeter / 10), 1):rgb(), math.saturate(comboMeter / 4))

        local function speedMeter(ref)
            ui.drawRectFilled(ref + vec2(0, -4), ref + vec2(180, 5), colorDark, 1)
            ui.drawLine(ref + vec2(0, -4), ref + vec2(0, 4), colorGrey, 1)
            ui.drawLine(ref + vec2(requiredSpeed, -4), ref + vec2(requiredSpeed, 4), colorGrey, 1)

            local speed = math.min(ac.getCarState(1).speedKmh, 180)
            if speed > 1 then
                ui.drawLine(ref + vec2(0, 0), ref + vec2(speed, 0), colorAccent, 4)
            end
        end

        ui.beginTransparentWindow("overtakeScore", vec2(100, 100), vec2(400 * 1.5, 400 * 1.5))
        ui.beginOutline()

        ui.pushStyleVar(ui.StyleVar.Alpha, 1 - speedWarning)
        ui.pushFont(ui.Font.Title)
        ui.text('NiDZ No Hesi')
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
        for i = 1, #messages do
            local m = messages[i]
            local f = math.saturate(4 - m.currentPos) * math.saturate(8 - m.age)
            ui.setCursor(startPos + vec2(20 * 0.5 + math.saturate(1 - m.age * 10) ^ 2 * 50, (m.currentPos - 1) * 15))
            ui.textColored(
                m.text,
                m.mood == 1 and rgbm(0, 1, 0, f) or m.mood == -1 and rgbm(1, 0, 0, f) or rgbm(1, 1, 1, f)
            )
        end
        for i = 1, glitterCount do
            local g = glitter[i]
            if g ~= nil then
                ui.drawLine(g.pos, g.pos + g.velocity * 4, g.color, 2)
            end
        end
        ui.popFont()
        ui.setCursor(startPos + vec2(0, 4 * 30))

        ui.pushStyleVar(ui.StyleVar.Alpha, speedWarning)
        ui.setCursorY(0)
        ui.pushFont(ui.Font.Main)
        ui.textColored("Keep speed above " .. requiredSpeed .. " km/h:", colorAccent)
        speedMeter(ui.getCursor() + vec2(-9 * 0.5, 4 * 0.2))

        ui.popFont()
        ui.popStyleVar()

        ui.endTransparentWindow()
    end
