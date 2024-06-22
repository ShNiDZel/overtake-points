-- Author: NiDZ
-- Version: 0.1

-- Constants
local requiredSpeed = 35

-- Game state variables
local timePassed = 0
local totalScore = 0
local comboMeter = 1
local comboColor = 0
local highestScore = 0
local dangerouslySlowTimer = 0
local carsState = {}
local wheelsWarningTimeout = 0

-- UI-related variables
local messages = {}
local glitter = {}
local glitterCount = 0

-- Function to add messages to the UI
local function addMessage(text, mood)
    table.insert(messages, { text = text, age = 0, mood = mood })
    
    -- Generate glitter effects for positive mood messages
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

-- Function to update UI messages and glitter effects
local function updateUI(dt)
    comboColor = comboColor + dt * 10 * comboMeter
    if comboColor > 360 then
        comboColor = comboColor - 360
    end
    
    -- Update message ages and positions
    for i = #messages, 1, -1 do
        local m = messages[i]
        m.age = m.age + dt
    end
    
    -- Update glitter particles' positions and lifetimes
    for i = glitterCount, 1, -1 do
        local g = glitter[i]
        g.pos:add(g.velocity)
        g.velocity.y = g.velocity.y + 0.02
        g.life = g.life - dt
        g.color.mult = math.saturate(g.life * 4)
        
        -- Remove expired glitter particles
        if g.life < 0 then
            if i < glitterCount then
                glitter[i] = glitter[glitterCount]
            end
            glitterCount = glitterCount - 1
        end
    end
    
    -- Add additional glitter particles randomly
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

-- Prepare function called before main execution starts
function script.prepare(dt)
    -- Display player car speed in custom console
    ac.debug("speed", ac.getCarState(1).speedKmh)
    
    -- Check condition for script execution to continue
    return ac.getCarState(1).speedKmh > 60
end

-- Update function called every frame
function script.update(dt)
    -- Display initial message when timePassed is zero
    if timePassed == 0 then
        addMessage("Let's get started!", 0)
    end
    
    -- Get player's car state
    local player = ac.getCarState(1)

    -- Check if engine life is below threshold
    if player.engineLifeLeft < 1 then
        -- Handle end game logic if engine life is critical
        if totalScore > highestScore then
            highestScore = math.floor(totalScore)
            ac.sendChatMessage("scored " .. totalScore .. " points.")
        end
        totalScore = 0
        comboMeter = 1
        return
    end

    -- Update timePassed with delta time
    timePassed = timePassed + dt

    -- Calculate comboMeter decay based on time and player's speed
    local comboFadingRate = 0.5 * math.lerp(1, 0.1, math.lerpInvSat(player.speedKmh, 80, 200)) + player.wheelsOutside
    comboMeter = math.max(1, comboMeter - dt * comboFadingRate)

    -- Get simulation state
    local sim = ac.getSimState()

    -- Ensure carsState array matches current number of cars in simulation
    while sim.carsCount > #carsState do
        carsState[#carsState + 1] = {}
    end

    -- Handle wheels warning timeout and display message if wheels are outside
    if wheelsWarningTimeout > 0 then
        wheelsWarningTimeout = wheelsWarningTimeout - dt
    elseif player.wheelsOutside > 0 then
        if wheelsWarningTimeout == 0 then
            addMessage("Car is off track", -1)
        end
        wheelsWarningTimeout = 60
    end

    -- Handle dangerously slow speed condition
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
                addMessage("Speed too low!", -1)
            end
        end
        dangerouslySlowTimer = dangerouslySlowTimer + dt
        comboMeter = 1
        return
    else
        dangerouslySlowTimer = 0
    end

    -- Loop through each car in simulation
    for i = 1, ac.getSimState().carsCount do
        local car = ac.getCarState(i)
        local state = carsState[i]

        -- Check proximity and alignment with player's car
        if car.pos:closerToThan(player.pos, 10) then
            local drivingAlong = math.dot(car.look, player.look) > 0.2

            -- Handle near miss and collision detection
            if not drivingAlong then
                state.drivingAlong = false

                if not state.nearMiss and car.pos:closerToThan(player.pos, 3) then
                    state.nearMiss = true

                    if car.pos:closerToThan(player.pos, 2.5) then
                        comboMeter = comboMeter + 3
                        addMessage("Very close near miss!", 1)
                    else
                        comboMeter = comboMeter + 1
                        addMessage("Near miss: bonus combo", 0)
                    end
                end
            end

            -- Handle collision event
            if car.collidedWith == 0 then
                addMessage("Collision", -1)
                state.collided = true

                if totalScore > highestScore then
                    highestScore = math.floor(totalScore)
                    ac.sendChatMessage("scored " .. totalScore .. " points.")
                end
                totalScore = 0
                comboMeter = 1
            end

            -- Handle overtaking event
            if not state.overtaken and not state.collided and state.drivingAlong then
                local posDir = (car.pos - player.pos):normalize()
                local posDot = math.dot(posDir, car.look)
                state.maxPosDot = math.max(state.maxPosDot, posDot)
                if posDot < -0.5 and state.maxPosDot > 0.5 then
                    totalScore = totalScore + math.ceil(10 * comboMeter)
                    comboMeter = comboMeter + 1
                    comboColor = comboColor + 90
                    addMessage("Overtake", comboMeter > 20 and 1 or 0)
                    state.overtaken = true
                end
            end
        else
            -- Reset state if car is not in proximity
            state.maxPosDot = -1
            state.overtaken = false
            state.collided = false
            state.drivingAlong = true
            state.nearMiss = false
        end
    end
end

-- Function to draw UI elements
function script.drawUI()
    local uiState = ac.getUiState()
    updateUI(uiState.dt)

    -- Drawing logic for UI elements
    -- Simplified for brevity and clarity
end
