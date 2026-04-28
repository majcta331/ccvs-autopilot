-- Advanced Autopilot
-- New program with destination workflow + in-flight adjustment panel

function pos(...) return term.setCursorPos(...) end
function cls(...) return term.clear() end
function tCol(...) return term.setTextColor(...) end
function bCol(...) return term.setBackgroundColor(...) end
function box(...) return paintutils.drawFilledBox(...) end
function line(...) return paintutils.drawLine(...) end

local screenW, screenH = term.getSize()
local currentMenu = "main"

local settings = {
    targetSpeed = 7,
    targetAltitude = nil,
    arrivalRadius = 30,
}

local destinations = {
    {name = "Village", x = -144, z = -520},
    {name = "BAZA", x = 1930, z = -2482},
    {name = "HISA", x = 4120, z = -2811},
}

local selectedDeparture = 1
local selectedArrival = 2

local flight = {
    active = false,
    departure = nil,
    arrival = nil,
    distance = 0,
    eta = "-",
    status = "IDLE",
}

local function drawFrame(title)
    cls()
    box(1, 1, screenW, screenH, colors.lightBlue)
    box(7, 4, screenW - 7, screenH - 3, colors.gray)
    line(7, 4, screenW - 7, 4, colors.lightGray)

    tCol(colors.black)
    bCol(colors.lightBlue)
    pos(math.max(2, math.floor((screenW - #title) / 2)), 2)
    write(title)
end

local function getYaw()
    local rot = ship.getQuaternion()
    return math.atan2(2 * rot.y * rot.w - 2 * rot.x * rot.z, 1 - 2 * rot.y * rot.y - 2 * rot.z * rot.z)
end

local function getIdealYaw(destX, destZ)
    local p = ship.getWorldspacePosition()
    return math.atan2(p.x - destX, p.z - destZ)
end

local function getDistance(destX, destZ)
    local p = ship.getWorldspacePosition()
    return math.sqrt((destX - p.x) ^ 2 + (destZ - p.z) ^ 2)
end

local function getSpeed()
    local vel = ship.getVelocity()
    return math.sqrt(vel.x ^ 2 + vel.z ^ 2)
end

local function rotateToward(destX, destZ)
    local ideal = getIdealYaw(destX, destZ)
    local shipYaw = getYaw()
    local yawDelta = math.abs(shipYaw - ideal)

    if yawDelta < 0.1 then
        return
    end

    local sCalc = shipYaw + math.pi
    local iCalc = ideal + math.pi
    local dCalc = math.abs(sCalc - iCalc)
    if (dCalc > math.pi) == (sCalc < iCalc) then
        ship.applyRotDependentTorque(0, -1000 * ship.getMass(), 0)
    else
        ship.applyRotDependentTorque(0, 1000 * ship.getMass(), 0)
    end
end

local function holdAltitude()
    if settings.targetAltitude == nil then
        return
    end

    local p = ship.getWorldspacePosition()
    local diff = settings.targetAltitude - p.y
    local mass = ship.getMass()

    if math.abs(diff) > 0.8 then
        local lift = math.max(-100, math.min(100, diff * 8))
        ship.applyInvariantForce(0, lift * mass, 0)
    end
end

local function openNumberPrompt(label, defaultValue)
    box(10, screenH - 7, screenW - 10, screenH - 3, colors.lightGray)
    tCol(colors.black)
    bCol(colors.lightGray)
    pos(12, screenH - 6)
    write(label)
    pos(12, screenH - 5)
    write("Current: " .. tostring(defaultValue))
    pos(12, screenH - 4)
    write("> ")
    local raw = read()
    local v = tonumber(raw)
    if v ~= nil then
        return v
    end
    return nil
end

local function drawMain()
    drawFrame(" ADVANCED AUTOPILOT ")
    tCol(colors.yellow)
    bCol(colors.blue)
    pos(18, 8) write(" DESTINATIONS ")
    pos(15, 10) write(" MAKE DESTINATION ")
    pos(20, 12) write(" SETTINGS ")
end

local function drawDestinations()
    drawFrame(" DESTINATIONS ")
    tCol(colors.black)
    bCol(colors.gray)

    pos(10, 7) write("Departure:")
    bCol(colors.lightGray)
    pos(22, 7) write(" " .. destinations[selectedDeparture].name .. " ")

    bCol(colors.gray)
    pos(10, 9) write("Arrival  :")
    bCol(colors.lightGray)
    pos(22, 9) write(" " .. destinations[selectedArrival].name .. " ")

    tCol(colors.white)
    bCol(colors.green)
    pos(14, 12) write(" < DEP > ")
    pos(26, 12) write(" < ARR > ")

    bCol(colors.orange)
    pos(18, 14) write(" ENGAGE ")

    bCol(colors.red)
    pos(20, 16) write(" BACK ")
end

local function drawMakeDestination()
    drawFrame(" MAKE DESTINATION ")
    tCol(colors.black)
    bCol(colors.gray)
    pos(10, 7) write("Create a new saved destination")
    pos(10, 9) write("Click ADD to enter name, X, Z")

    tCol(colors.white)
    bCol(colors.green)
    pos(20, 12) write(" ADD ")

    bCol(colors.red)
    pos(20, 16) write(" BACK ")
end

local function drawSettings()
    drawFrame(" SETTINGS ")
    tCol(colors.black)
    bCol(colors.gray)
    pos(10, 7) write("Speed Target : " .. math.floor(settings.targetSpeed + 0.5))
    pos(10, 9)
    write("Altitude Hold: " .. (settings.targetAltitude and math.floor(settings.targetAltitude + 0.5) or "OFF"))
    pos(10, 11) write("Arrival Dist : " .. math.floor(settings.arrivalRadius + 0.5))

    tCol(colors.white)
    bCol(colors.blue)
    pos(10, 13) write(" SET SPEED ")
    pos(24, 13) write(" SET ALT ")
    pos(36, 13) write(" SET ARR ")

    bCol(colors.red)
    pos(20, 16) write(" BACK ")
end

local function drawEngaged()
    drawFrame(" AUTOPILOT PANEL ")

    -- Top MCP-style strip
    box(8, 5, screenW - 8, 7, colors.black)
    line(8, 5, screenW - 8, 5, colors.lightGray)

    tCol(colors.lime)
    bCol(colors.black)
    pos(10, 6) write("SPD " .. math.floor(settings.targetSpeed + 0.5))
    pos(20, 6)
    if settings.targetAltitude then
        write("ALT " .. math.floor(settings.targetAltitude + 0.5))
    else
        write("ALT OFF")
    end
    pos(32, 6) write("STAT " .. flight.status)

    tCol(colors.black)
    bCol(colors.gray)
    pos(10, 9) write("From: " .. flight.departure.name)
    pos(10, 10) write("To  : " .. flight.arrival.name)
    pos(10, 11) write("Distance: " .. math.floor(flight.distance + 0.5))
    pos(10, 12) write("ETA: " .. flight.eta)
    pos(10, 13) write("Speed: " .. math.floor(getSpeed() + 0.5))
    pos(10, 14) write("Altitude: " .. math.floor(ship.getWorldspacePosition().y + 0.5))

    tCol(colors.white)
    bCol(colors.blue)
    pos(28, 9) write(" SPD- ")
    pos(35, 9) write(" SPD+ ")
    pos(28, 11) write(" ALT- ")
    pos(35, 11) write(" ALT+ ")

    bCol(colors.green)
    pos(28, 13) write(" LOCK ")
    bCol(colors.red)
    pos(35, 13) write("ABORT")
end

local function addDestinationPrompt()
    drawMakeDestination()
    box(10, 6, screenW - 10, screenH - 5, colors.lightGray)
    tCol(colors.black)
    bCol(colors.lightGray)
    pos(12, 7) write("Name:")
    pos(12, 8) local name = read()
    pos(12, 9) write("X:")
    pos(12, 10) local x = tonumber(read())
    pos(12, 11) write("Z:")
    pos(12, 12) local z = tonumber(read())

    if name ~= "" and x ~= nil and z ~= nil then
        table.insert(destinations, {name = name, x = x, z = z})
    end
end

local function beginFlight()
    if selectedDeparture == selectedArrival then
        flight.active = false
        flight.status = "SELECT DIFFERENT ARR"
        return
    end

    flight.departure = destinations[selectedDeparture]
    flight.arrival = destinations[selectedArrival]
    flight.active = true
    flight.status = "ENGAGED"
    currentMenu = "engaged"
end

local function stopFlight()
    flight.active = false
    flight.status = "ABORTED"
    currentMenu = "main"
end

local function flightTick()
    if not flight.active then
        return
    end

    local ax, az = flight.arrival.x, flight.arrival.z
    rotateToward(ax, az)

    local mass = ship.getMass()
    local speed = getSpeed()
    if speed < settings.targetSpeed then
        ship.applyRotDependentForce(0, 0, -70 * mass)
    end

    holdAltitude()

    flight.distance = getDistance(ax, az)
    local etaHours = flight.distance / (30 * math.max(speed, 0.1))
    local days = math.floor(etaHours / 24)
    local hours = math.floor(etaHours % 24)
    local minutes = math.floor((etaHours % 1) * 60)
    flight.eta = days .. "d " .. hours .. "h " .. minutes .. "m"

    if flight.distance < settings.arrivalRadius then
        flight.active = false
        flight.status = "ARRIVED"
        currentMenu = "main"
    end
end

local function handleMainClick(mx, my)
    if mx >= 18 and mx <= 31 and my == 8 then
        currentMenu = "destinations"
    elseif mx >= 15 and mx <= 32 and my == 10 then
        currentMenu = "makeDestination"
    elseif mx >= 20 and mx <= 29 and my == 12 then
        currentMenu = "settings"
    end
end

local function handleDestinationsClick(mx, my)
    if mx >= 14 and mx <= 21 and my == 12 then
        selectedDeparture = selectedDeparture + 1
        if selectedDeparture > #destinations then selectedDeparture = 1 end
    elseif mx >= 26 and mx <= 33 and my == 12 then
        selectedArrival = selectedArrival + 1
        if selectedArrival > #destinations then selectedArrival = 1 end
    elseif mx >= 18 and mx <= 25 and my == 14 then
        beginFlight()
    elseif mx >= 20 and mx <= 25 and my == 16 then
        currentMenu = "main"
    end
end

local function handleMakeDestinationClick(mx, my)
    if mx >= 20 and mx <= 24 and my == 12 then
        addDestinationPrompt()
    elseif mx >= 20 and mx <= 25 and my == 16 then
        currentMenu = "main"
    end
end

local function handleSettingsClick(mx, my)
    if mx >= 10 and mx <= 20 and my == 13 then
        local v = openNumberPrompt("Set target speed", settings.targetSpeed)
        if v and v > 0 then settings.targetSpeed = v end
    elseif mx >= 24 and mx <= 32 and my == 13 then
        local v = openNumberPrompt("Set altitude (blank=off)", settings.targetAltitude or 0)
        if v then
            settings.targetAltitude = v
        else
            settings.targetAltitude = nil
        end
    elseif mx >= 36 and mx <= 44 and my == 13 then
        local v = openNumberPrompt("Set arrival radius", settings.arrivalRadius)
        if v and v >= 10 then settings.arrivalRadius = v end
    elseif mx >= 20 and mx <= 25 and my == 16 then
        currentMenu = "main"
    end
end

local function handleEngagedClick(mx, my)
    if mx >= 28 and mx <= 33 and my == 9 then
        settings.targetSpeed = math.max(1, settings.targetSpeed - 1)
    elseif mx >= 35 and mx <= 40 and my == 9 then
        settings.targetSpeed = settings.targetSpeed + 1
    elseif mx >= 28 and mx <= 33 and my == 11 then
        if settings.targetAltitude ~= nil then
            settings.targetAltitude = settings.targetAltitude - 5
        end
    elseif mx >= 35 and mx <= 40 and my == 11 then
        if settings.targetAltitude == nil then
            settings.targetAltitude = ship.getWorldspacePosition().y
        end
        settings.targetAltitude = settings.targetAltitude + 5
    elseif mx >= 28 and mx <= 33 and my == 13 then
        -- LOCK simply confirms current setpoints
        flight.status = "LOCKED"
    elseif mx >= 35 and mx <= 39 and my == 13 then
        stopFlight()
    end
end

while true do
    if currentMenu == "main" then
        drawMain()
    elseif currentMenu == "destinations" then
        drawDestinations()
    elseif currentMenu == "makeDestination" then
        drawMakeDestination()
    elseif currentMenu == "settings" then
        drawSettings()
    elseif currentMenu == "engaged" then
        drawEngaged()
    end

    local tick = os.startTimer(currentMenu == "engaged" and 0.1 or 0.25)
    local event, p1, p2, p3 = os.pullEvent()

    if event == "timer" and p1 == tick then
        if currentMenu == "engaged" then
            flightTick()
        end
    elseif event == "mouse_click" then
        local _, mx, my = p1, p2, p3
        if currentMenu == "main" then
            handleMainClick(mx, my)
        elseif currentMenu == "destinations" then
            handleDestinationsClick(mx, my)
        elseif currentMenu == "makeDestination" then
            handleMakeDestinationClick(mx, my)
        elseif currentMenu == "settings" then
            handleSettingsClick(mx, my)
        elseif currentMenu == "engaged" then
            handleEngagedClick(mx, my)
        end
    end
end
