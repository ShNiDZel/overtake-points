-- Author: NiDZ
-- Version: 1.0

-- Constants
local requiredSpeed = 35    -- Speed required to avoid penalty
local nearMissThreshold = 3  -- Distance threshold for near miss
local nearHitThreshold = 1.5 -- Distance threshold for near hit
local slipstreamThreshold = 5 -- Distance threshold for slipstreaming
local overtakeDotThreshold = 0.5 -- Dot product threshold for overtaking

-- Variables
local totalScore = 0        -- Total score accumulated
local comboMeter = 1        -- Combo meter starting value
local highestScore = 0      -- Highest score achieved
local dangerouslySlowTimer = 0   -- Timer for penalties when speed is too low
local wheelsWarningTimeout = 0   -- Timer for warnings when wheels are outside
local carsState = {}        -- State tracking for each car in simulation

-- Storage for highest score
local stored = { playerscore = ac.storage('playerscore', highestScore) }
highestScore = stored.playerscore:get()  -- Load highest score from storage

-- Function to send highest score to connected clients
local function sendHighscore(connectedCarIndex, connectedSessionID)
    ac.sendChatMessage("Highscore: " .. highestScore .. " pts.")
end
ac.onClientConnected(sendHighscore)

-- Function to reset score if current score surpasses highest score
local function resetScore()
    if totalScore > highestScore then
        highestScore = math.floor(totalScore)
        stored.playerscore:set(highestScore)
        ac.sendChatMessage("NEW highscore: " .. totalScore .. " pts.")
    end
    totalScore, comboMeter = 0, 1  -- Reset total score and combo meter
end

-- Function to check if player's speed is too low and apply penalties
local function checkSpeed(dt)
    local player = ac.getCarState(1)
    if player.speedKmh < requiredSpeed then
        dangerouslySlowTimer = dangerouslySlowTimer + dt
        -- Penalize if speed is low for too long
        if dangerouslySlowTimer > 3 then
            resetScore()
        elseif dangerouslySlowTimer == dt then
            addMessage("Too Slow", -1)  -- Example function call, assumed elsewhere
        end
        comboMeter = 1  -- Reset combo meter if speed is low
        return true
    else
        dangerouslySlowTimer = 0
        return false
    end
end

-- Function to update combo meter based on player's speed and actions
local function updateCombo(dt, player)
    -- Adjust combo meter based on speed and other factors
    comboMeter = math.max(1, comboMeter - dt * (0.5 * math.lerp(1, 0.1, math.lerpInvSat(player.speedKmh, 80, 200)) + player.wheelsOutside))
end

-- Main update function called every frame
function script.update(dt)
    local player = ac.getCarState(1)  -- Get state of the player's car

    -- Check if player's car is destroyed (example condition)
    if player.engineLifeLeft < 1 then
        resetScore()  -- Reset score if engine is destroyed
        return
    end

    updateCombo(dt, player)  -- Update combo meter based on current speed and actions

    local sim = ac.getSimState()  -- Get state of the simulation

    -- Ensure carsState array is ready for all cars in simulation
    for i = #carsState + 1, sim.carsCount do
        carsState[i] = {}  -- Initialize state for new cars in the simulation
    end

    -- Handle warning for wheels outside the track
    if wheelsWarningTimeout > 0 then
        wheelsWarningTimeout = wheelsWarningTimeout - dt
    elseif player.wheelsOutside > 0 then
        if wheelsWarningTimeout == 0 then
            addMessage("Car is outside", -1)  -- Example function call, assumed elsewhere
            wheelsWarningTimeout = 60
        end
    end

    -- Check if player's speed is too low
    if checkSpeed(dt) then return end

    -- Loop through all cars in the simulation
    for i = 1, sim.carsCount do
        local car, state = ac.getCarState(i), carsState[i]

        -- Check if the car is close to the player
        if car.pos:closerToThan(player.pos, 10) then
            local drivingAlong = math.dot(car.look, player.look) > 0.2

            -- Handle near misses
            if not drivingAlong and not state.nearMiss and car.pos:closerToThan(player.pos, nearMissThreshold) then
                state.nearMiss = true
                if car.pos:closerToThan(player.pos, nearHitThreshold) then
                    comboMeter = comboMeter + 3
                    totalScore = totalScore + 10  -- Add points for very close near miss
                    addMessage("Very close near miss!", 1)  -- Example function call, assumed elsewhere
                else
                    comboMeter = comboMeter + 1
                    totalScore = totalScore + 5  -- Add points for near miss
                    addMessage("Near miss: bonus combo", 0)  -- Example function call, assumed elsewhere
                end
            end

            -- Handle collisions
            if car.collidedWith == 0 then
                addMessage("Collision", -1)  -- Example function call, assumed elsewhere
                state.collided = true
                resetScore()  -- Reset score if collision occurs
            end

            -- Handle overtakes
            if not state.overtaken and not state.collided and state.drivingAlong then
                local posDir = (car.pos - player.pos):normalize()
                local posDot = math.dot(posDir, car.look)
                state.maxPosDot = math.max(state.maxPosDot or -1, posDot)
                if posDot < -overtakeDotThreshold and state.maxPosDot > overtakeDotThreshold then
                    totalScore = totalScore + math.ceil(10 * comboMeter)
                    comboMeter = comboMeter + 1
                    addMessage("Overtake", comboMeter > 20 and 1 or 0)  -- Example function call, assumed elsewhere
                    state.overtaken = true
                end
            end

            -- Handle near hits
            if not state.nearHit and car.pos:closerToThan(player.pos, nearHitThreshold) then
                state.nearHit = true
                totalScore = totalScore + 5  -- Add points for near hit
                comboMeter = comboMeter + 1
                addMessage("Near hit", comboMeter > 20 and 1 or 0)  -- Example function call, assumed elsewhere
            end

            -- Handle slipstreaming (drafting)
            if not state.slipstreaming and car.pos:closerToThan(player.pos, slipstreamThreshold) and drivingAlong then
                state.slipstreaming = true
                totalScore = totalScore + 2  -- Add points for slipstreaming
                comboMeter = comboMeter + 1
                addMessage("Slipstreaming", comboMeter > 20 and 1 or 0)  -- Example function call, assumed elsewhere
            end
        else
            -- Reset state if car is no longer close to player
            state.maxPosDot, state.overtaken, state.collided, state.drivingAlong, state.nearMiss, state.nearHit, state.slipstreaming = -1, false, false, true, false, false, false
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
