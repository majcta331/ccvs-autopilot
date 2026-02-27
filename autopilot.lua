-- Autopilot for boats for newer versions vs:cc
-- Tested in 1.20.1 fabric
-- Some figures can be changed in the script below (see comment after the -- marks)
-- Keep in mind that the position of your ship can be different from your position.
-- IMPORTANT: works only correct when ship is assembled heading north!
-- In this version you can enter more waypoints.
-- By Arjen de Vries (with pieces of code borrowed from other programmers)

function pos(...) return term.setCursorPos(...) end
function cls(...) return term.clear() end
function tCol(...) return term.setTextColor(...) end
function bCol(...) return term.setBackgroundColor(...) end
function box(...) return paintutils.drawFilledBox(...) end
function line(...) return paintutils.drawLine(...) end

x, y = term.getSize()

local currentMenu = "main"

-- Rednet master/slave command settings
local MODEM_SIDE = "bottom"
local REDNET_PROTOCOL = "ccvs-autopilot"

local COMMAND_TARGETS = {
    MSL_LEFT = 13,
    CANNON = 12,
    MSL_RIGHT = 13,
    BOMBS_1 = 12,
    BOMBS_2 = 12,
    BOMBS_3 = 13,
    BOMBS_4 = 13,
    FLARES = 14,
    AIRSTAIR_DOOR_ON = 12,
    AIRSTAIR_DOOR_OFF = 12,
}

local DISPLAY_SLAVES = {
    TELEMETRY = 19,
    EVENTS = 20,
}

local displayState = {
    mode = "IDLE",
    nav = "DISENGAGED",
    target = "-",
    distance = 0,
    rtt = "-",
}

local rednetReady = false

function initRednet()
    if rednetReady then
        return true
    end

    if peripheral.getType(MODEM_SIDE) ~= "modem" then
        return false
    end

    if not rednet.isOpen(MODEM_SIDE) then
        rednet.open(MODEM_SIDE)
    end

    rednetReady = rednet.isOpen(MODEM_SIDE)
    return rednetReady
end

function sendSlaveCommand(commandKey)
    local targetId = COMMAND_TARGETS[commandKey]
    if targetId == nil then
        return false
    end

    if not initRednet() then
        return false
    end

    rednet.send(targetId, commandKey, REDNET_PROTOCOL)
    return true
end

function getShipSpeed()
    local vel = ship.getVelocity()
    return math.sqrt(vel.x^2 + vel.z^2)
end

function sendDisplayTelemetry()
    if not initRednet() then
        return false
    end

    local payload = {
        kind = "telemetry",
        speed = math.floor(getShipSpeed() + 0.5),
        mode = displayState.mode,
        nav = displayState.nav,
        target = tostring(displayState.target),
        distance = math.floor((displayState.distance or 0) + 0.5),
        rtt = tostring(displayState.rtt or "-"),
    }

    rednet.send(DISPLAY_SLAVES.TELEMETRY, payload, REDNET_PROTOCOL)
    return true
end

function sendDisplayEvent(label)
    if not initRednet() then
        return false
    end

    rednet.send(DISPLAY_SLAVES.EVENTS, {kind = "event", text = label}, REDNET_PROTOCOL)
    return true
end

------------------------------------------------------------
function enterWaypoints()
    box(1,1,x,y,colors.lightBlue) --Background
    box(12,6,40,13,colors.gray) --Login Menu
    line(12,6,40,6,colors.lightGray) -- Top Bar
    tCol(colors.black)
    bCol(colors.lightBlue)
    pos(13,3)
    write(" SHIP AUTO-NAVIGATOR MENU ")
    pos(15,8)
    bCol(colors.gray)
    print("Number of waypoints:")
    line(25,10,26,10,colors.white)
    pos(25,10)
    n = tonumber(read())

    waypoints = {}

    for t=1, n do
        box(12,6,40,13,colors.gray) --Login Menu
        line(12,6,40,6,colors.lightGray) -- Top Bar
        pos(13,6)
        bCol(colors.lightGray)
        print("Waypoint " .. t)
        pos(15,8)
        bCol(colors.gray)
        print("Enter X coordinate:")
        line(15,9,37,9,colors.white)
        pos(15,9)
        local x = tonumber(read())
        pos(15,11)
        bCol(colors.gray)
        print("Enter Z coordinate:")
        line(15,12,37,12,colors.white)
        pos(15,12)
        local z = tonumber(read())
        table.insert(waypoints, {x=x, z=z})
    end
    box(12,6,40,13,colors.gray) --Login Menu
    line(12,6,40,6,colors.lightGray) -- Top Bar
    pos(18,9)
    bCol(colors.gray)
    tCol(colors.green)
    print("Waypoints ready!")
    sleep (3)
end

------------------------------------------------------------
function getYaw()
    local rot = ship.getQuaternion()
    return math.atan2(2*rot.y*rot.w-2*rot.x*rot.z, 1-2*rot.y*rot.y-2*rot.z*rot.z)
end

------------------------------------------------------------
function getIdealYaw(destX, destZ)
    local pos = ship.getWorldspacePosition()
    return math.atan2(pos.x - destX, pos.z - destZ)
end

------------------------------------------------------------
function getDistance(destX, destZ)
    local pos = ship.getWorldspacePosition()
    return math.sqrt((destX - pos.x)^2 + (destZ - pos.z)^2)
end

------------------------------------------------------------
function rotateShip(destX, destZ)
    local facing = false
    while not facing do
        local idealYaw = getIdealYaw(destX, destZ)
        local shipYaw = getYaw()

        if math.abs(shipYaw - idealYaw) < 0.1 then
            facing = true
        else
            local sCalc = shipYaw + math.pi
            local iCalc = idealYaw + math.pi
            local dCalc = math.abs(sCalc - iCalc)

            if (dCalc > math.pi) == (sCalc < iCalc) then
                ship.applyRotDependentTorque(0, -1000 * ship.getMass(), 0) -- clockwise
            else
                ship.applyRotDependentTorque(0, 1000 * ship.getMass(), 0) -- counterclockwise
            end
        end
        sleep(0)
    end
end

------------------------------------------------------------
function moveShip(destX, destZ, wp)
    local distance
    local spd = 7

    repeat
        if redstone.getInput("top") == true then
           manual()
        end
        rotateShip(destX, destZ)

        local mass = ship.getMass()
        local speed = math.sqrt(ship.getVelocity().x^2 + ship.getVelocity().z^2)
        if speed < spd then
            ship.applyRotDependentForce(0, 0, -70 * mass)
        end

        distance = getDistance(destX, destZ)
        local time = distance / (30 * math.max(speed, 0.1))
        local days, hours, minutes = math.floor(time/24), math.floor(time % 24), math.floor((time % 1) * 60)

        displayState.mode = currentMenu
        displayState.nav = "ENGAGED"
        displayState.target = "WP " .. tostring(wp)
        displayState.distance = distance
        displayState.rtt = days .. "d " .. hours .. "h " .. minutes .. "m"
        sendDisplayTelemetry()

        -- MONITOR BLOCK
        local monitor = peripheral.find("monitor")
        if monitor ~= nil then
            monitor.setTextScale(0.5)
            monitor.clear()
            monitor.setCursorPos(1, 1)
            monitor.write("Nav. to wp: " .. wp)
            monitor.setCursorPos(1, 3)
            monitor.write("Speed   : " .. math.floor(speed + 0.5))
            monitor.setCursorPos(1, 4)
            monitor.write("Distance: " .. math.floor(distance + 0.5))
            monitor.setCursorPos(1, 6)
            monitor.write("RTT: " .. days .. "d " .. hours .. "h " .. minutes .. "m")
        end
        sleep(0)
    until distance < 25
end

------------------------------------------------------------
function stopClick()
  local event, button, mx, my = os.pullEvent("mouse_click")
end

------------------------------------------------------------
function trustL()
    sleep(1)
    box(1,1,x,y,colors.lightBlue) --Background
    box(12,6,40,13,colors.gray) --Login Menu
    line(12,6,40,6,colors.lightGray) -- Top Bar
    tCol(colors.black)
    bCol(colors.orange)
    pos(6,16)
    write(" <<< TRUST ")

    repeat
        local mass = ship.getMass()
        local vel = ship.getVelocity()
        local speed = math.sqrt(vel.x^2+vel.z^2)
            if speed < 0.6 then
                ship.applyRotDependentForce(-10 * mass, 0, 0)
                sleep(0.1)
           end
    until false

end

------------------------------------------------------------
function trustR()
    sleep(1)
    box(1,1,x,y,colors.lightBlue) --Background
    box(12,6,40,13,colors.gray) --Login Menu
    line(12,6,40,6,colors.lightGray) -- Top Bar
    tCol(colors.black)
    bCol(colors.orange)
    pos(35,16)
    write(" TRUST >>> ")

    repeat
        local mass = ship.getMass()
        local vel = ship.getVelocity()
        local speed = math.sqrt(vel.x^2+vel.z^2)
            if speed < 0.6 then
                ship.applyRotDependentForce(10 * mass, 0, 0)
                os.sleep(0)
            end
    until false

end

------------------------------------------------------------
function manual()  -- holding process
    sleep(1)
    tCol(colors.yellow)
    bCol(colors.orange)
    pos(29,11)
    write(" HOLD ")
    repeat
        sleep(0.5)
    until redstone.getInput("top") == false
end

------------------------------------------------------------
function engage()
    beginAutopilotRun()
end

------------------------------------------------------------
-- Function to move to the village
function moveToVillage()
    local villageX = -144
    local villageZ = -520
    print("Navigating to Village at coordinates (" .. villageX .. ", " .. villageZ .. ")...")
    moveShip(villageX, villageZ, "Village")  -- Call the moveShip function with village coordinates
    print("Arrived at Village!")
end

------------------------------------------------------------
-- Function to move to BAZA
function moveToBaza()
    local bazaX = 1930
    local bazaZ = -2482
    print("Navigating to BAZA at coordinates (" .. bazaX .. ", " .. bazaZ .. ")...")
    moveShip(bazaX, bazaZ, "BAZA")  -- Call the moveShip function with BAZA coordinates
    print("Arrived at BAZA!")
end

------------------------------------------------------------
-- Function to move to HIŠA
function moveToHisa()
    local hisaX = 4120
    local hisaZ = -2811
    print("Navigating to HIŠA at coordinates (" .. hisaX .. ", " .. hisaZ .. ")...")
    moveShip(hisaX, hisaZ, "HIŠA")  -- Call the moveShip function with HIŠA coordinates
    print("Arrived at HIŠA!")
end

------------------------------------------------------------
-- Function to show saved waypoints
function showSaved()
    cls()
    pos(1, 1)
    print("SAVED Waypoints")
    print("1. Village")
    print("2. BAZA")
    print("3. HIŠA")
    print("Select an option:")

    local selection = read()

    if selection == "1" then
        moveToVillage()  -- Navigate to the village
    elseif selection == "2" then
        moveToBaza()  -- Navigate to BAZA
    elseif selection == "3" then
        moveToHisa()  -- Navigate to HIŠA
    else
        print("Invalid option. Please try again.")
    end

    sleep(2)  -- Wait before returning to the main menu
end

------------------------------------------------------------
function drawOuterFrame(borderColor)
    line(1,1,x,1,borderColor)
    line(1,y,x,y,borderColor)
    line(1,1,1,y,borderColor)
    line(x,1,x,y,borderColor)
end

local controlState = {left=false, right=false, up=false, down=false}
local doorsActive = false
local doorsFlashOn = false
local weaponSend = nil
local autopilotRun = {
    active = false,
    waypointIndex = 1,
    targetSpeed = 7,
    targetAltitude = nil,
    reached = false,
}


function anyControlActive()
    return controlState.left or controlState.right or controlState.up or controlState.down
end

function setWeaponSend(sendX, sendY)
    weaponSend = {x=sendX, y=sendY, expiresAt=os.clock() + 2.5}
end

function drawWeaponSend()
    if weaponSend ~= nil and os.clock() < weaponSend.expiresAt then
        tCol(colors.green)
        bCol(colors.gray)
        pos(weaponSend.x, weaponSend.y)
        write("SEND")
    elseif weaponSend ~= nil and os.clock() >= weaponSend.expiresAt then
        weaponSend = nil
    end
end

function applyControlThrust()
    local mass = ship.getMass()
    local vel = ship.getVelocity()
    local lateralSpeed = math.abs(vel.x)
    local forwardSpeed = math.abs(vel.z)

    -- Match old trust logic for side movement: gentle side push with speed cap
    if controlState.left and lateralSpeed < 0.6 then
        ship.applyRotDependentForce(-10 * mass, 0, 0)
    end
    if controlState.right and lateralSpeed < 0.6 then
        ship.applyRotDependentForce(10 * mass, 0, 0)
    end

    -- Top/bottom arrows are ship forward/backward movement
    if controlState.up and forwardSpeed < 7 then
        ship.applyRotDependentForce(0, 0, -70 * mass)
    end
    if controlState.down and forwardSpeed < 7 then
        ship.applyRotDependentForce(0, 0, 70 * mass)
    end
end

------------------------------------------------------------
function getShipAltitude()
    local posWs = ship.getWorldspacePosition()
    return posWs.y or 0
end

------------------------------------------------------------
function formatRtt(distance, speed)
    local time = distance / (30 * math.max(speed, 0.1))
    local days = math.floor(time/24)
    local hours = math.floor(time % 24)
    local minutes = math.floor((time % 1) * 60)
    return days .. "d " .. hours .. "h " .. minutes .. "m"
end

------------------------------------------------------------
function rotateShipStep(destX, destZ)
    local idealYaw = getIdealYaw(destX, destZ)
    local shipYaw = getYaw()

    if math.abs(shipYaw - idealYaw) < 0.1 then
        return true
    end

    local sCalc = shipYaw + math.pi
    local iCalc = idealYaw + math.pi
    local dCalc = math.abs(sCalc - iCalc)

    if (dCalc > math.pi) == (sCalc < iCalc) then
        ship.applyRotDependentTorque(0, -1000 * ship.getMass(), 0)
    else
        ship.applyRotDependentTorque(0, 1000 * ship.getMass(), 0)
    end

    return false
end

------------------------------------------------------------
function beginAutopilotRun()
    if waypoints == nil or #waypoints == 0 then
        box(1,1,x,y,colors.lightBlue)
        box(12,6,40,13,colors.gray)
        line(12,6,40,6,colors.lightGray)
        tCol(colors.red)
        bCol(colors.gray)
        pos(16,9)
        print("No waypoints entered!")
        displayState.mode = currentMenu
        displayState.nav = "ERROR"
        displayState.target = "NO WAYPOINTS"
        displayState.distance = 0
        displayState.rtt = "-"
        sendDisplayTelemetry()
        sleep(2)
        return false
    end

    autopilotRun.active = true
    autopilotRun.reached = false
    autopilotRun.waypointIndex = 1
    autopilotRun.targetSpeed = autopilotRun.targetSpeed or 7
    if autopilotRun.targetAltitude == nil then
        autopilotRun.targetAltitude = math.floor(getShipAltitude() + 0.5)
    end

    displayState.nav = "ENGAGED"
    currentMenu = "engaged"
    return true
end

------------------------------------------------------------
function abortAutopilotRun()
    autopilotRun.active = false
    autopilotRun.reached = false
    autopilotRun.waypointIndex = 1
    displayState.nav = "ABORTED"
    displayState.target = "-"
    displayState.distance = 0
    displayState.rtt = "-"
    currentMenu = "main"
end

------------------------------------------------------------
function autopilotTick()
    if not autopilotRun.active then
        return
    end

    if waypoints == nil or autopilotRun.waypointIndex > #waypoints then
        autopilotRun.active = false
        autopilotRun.reached = true
        displayState.nav = "DISENGAGED"
        displayState.target = "ARRIVED"
        displayState.distance = 0
        displayState.rtt = "-"
        return
    end

    local wp = waypoints[autopilotRun.waypointIndex]
    local destX, destZ = wp.x, wp.z

    rotateShipStep(destX, destZ)

    local mass = ship.getMass()
    local vel = ship.getVelocity()
    local speed = math.sqrt(vel.x^2 + vel.z^2)
    local altitude = getShipAltitude()

    if speed < (autopilotRun.targetSpeed or 7) then
        ship.applyRotDependentForce(0, 0, -70 * mass)
    end

    local altError = (autopilotRun.targetAltitude or altitude) - altitude
    if altError > 1.5 then
        ship.applyInvariantForce(0, 25 * mass, 0)
    elseif altError < -1.5 then
        ship.applyInvariantForce(0, -25 * mass, 0)
    end

    local distance = getDistance(destX, destZ)
    if distance < 25 then
        autopilotRun.waypointIndex = autopilotRun.waypointIndex + 1
        if autopilotRun.waypointIndex > #waypoints then
            autopilotRun.active = false
            autopilotRun.reached = true
            displayState.nav = "DISENGAGED"
            displayState.target = "ARRIVED"
            displayState.distance = 0
            displayState.rtt = "-"
            return
        end
        wp = waypoints[autopilotRun.waypointIndex]
        distance = getDistance(wp.x, wp.z)
    end

    displayState.nav = "ENGAGED"
    displayState.target = "WP " .. tostring(autopilotRun.waypointIndex)
    displayState.distance = distance
    displayState.rtt = formatRtt(distance, speed)
end

------------------------------------------------------------
function drawEngagedMenu()
    cls()
    box(1,1,x,y,colors.lightBlue)
    box(8,5,44,16,colors.gray)
    line(8,5,44,5,colors.lightGray)
    line(42,5,44,5,colors.red)

    local speed = math.floor(getShipSpeed() + 0.5)
    local altitude = math.floor(getShipAltitude() + 0.5)

    tCol(colors.black)
    bCol(colors.lightBlue)
    pos(15,3)
    write(" AUTOPILOT ENGAGED ")

    tCol(colors.black)
    bCol(colors.red)
    pos(43,5)
    write("X")

    tCol(colors.white)
    bCol(colors.gray)
    pos(10,7)
    write("NAV        : " .. tostring(displayState.nav))
    pos(10,8)
    write("WAYPOINT   : " .. tostring(displayState.target))
    pos(10,9)
    write("DISTANCE   : " .. tostring(math.floor((displayState.distance or 0) + 0.5)))
    pos(10,10)
    write("ETA        : " .. tostring(displayState.rtt))
    pos(10,11)
    write("CUR SPEED  : " .. tostring(speed))
    pos(10,12)
    write("SET SPEED  : " .. tostring(math.floor((autopilotRun.targetSpeed or 7) + 0.5)))
    pos(10,13)
    write("CUR ALT    : " .. tostring(altitude))
    pos(10,14)
    write("SET ALT    : " .. tostring(math.floor((autopilotRun.targetAltitude or altitude) + 0.5)))

    tCol(colors.black)
    bCol(colors.cyan)
    pos(10,16)
    write(" SET SPEED ")
    pos(23,16)
    write(" SET ALT ")

    tCol(colors.white)
    bCol(colors.red)
    pos(34,16)
    write(" ABORT ")
end


------------------------------------------------------------
function promptNumberInput(label, currentValue)
    local boxTop = math.max(2, y - 3)
    local boxBottom = y
    box(1, boxTop, x, boxBottom, colors.gray)
    line(1, boxTop, x, boxTop, colors.lightGray)
    tCol(colors.black)
    bCol(colors.gray)
    pos(2, boxTop + 1)
    write(label .. " (current " .. tostring(currentValue) .. "): ")
    local value = tonumber(read())
    return value
end

------------------------------------------------------------
function drawMainMenu()
    cls()
    pos(1,1)
    box(1,1,x,y,colors.lightBlue) --Background
    box(12,6,40,14,colors.gray) -- Center Folder Window
    line(12,6,40,6,colors.lightGray) -- Top Bar
    line(38,6,40,6,colors.red) -- Exit

    tCol(colors.black)
    bCol(colors.lightBlue)
    pos(13,3)
    write(" SHIP AUTO-NAVIGATOR MENU ")

    tCol(colors.black)
    bCol(colors.red)
    pos(39,6)
    write("X")

    tCol(colors.yellow)
    bCol(colors.blue)
    pos(18,9)
    write(" AUTOPILOT FOLDER ")
    pos(23,11)
    write(" STATUS ")

    tCol(colors.black)
    bCol(colors.purple)
    pos(22,13)
    write(" WEAPONS ")
end

------------------------------------------------------------
function drawAutopilotMenu()
    cls()
    pos(1,1)
    box(1,1,x,y,colors.lightBlue) --Background
    box(12,6,40,14,colors.gray) --Autopilot Folder
    line(12,6,40,6,colors.lightGray) -- Top Bar
    line(38,6,40,6,colors.red) --Exit

    tCol(colors.black)
    bCol(colors.lightBlue)
    pos(15,3)
    write(" AUTOPILOT FOLDER ")

    tCol(colors.black)
    bCol(colors.red)
    pos(39,6)
    write("X")

    tCol(colors.yellow)
    bCol(colors.blue)
    pos(20,9)
    write(" SAVED ")
    pos(16,11)
    write(" MAKE A WAYPOINT ")
    pos(22,13)
    write(" ENGAGE ")

    tCol(colors.black)
    bCol(colors.orange)
    pos(20,16)
    write(" < BACK ")
end

------------------------------------------------------------
function drawStatusMenu()
    cls()
    pos(1,1)
    box(1,1,x,y,colors.lightBlue) --Background
    box(8,5,44,15,colors.gray) --Status Window
    line(8,5,44,5,colors.lightGray) -- Top Bar
    line(42,5,44,5,colors.red) --Exit

    local speed = math.floor(getShipSpeed() + 0.5)
    local posWs = ship.getWorldspacePosition()
    local heading = math.floor((math.deg(getYaw()) % 360 + 360) % 360 + 0.5)

    tCol(colors.black)
    bCol(colors.lightBlue)
    pos(17,3)
    write(" STATUS FOLDER ")

    tCol(colors.black)
    bCol(colors.red)
    pos(43,5)
    write("X")

    tCol(colors.white)
    bCol(colors.gray)
    pos(10,7)
    write("NAV     : " .. tostring(displayState.nav))
    pos(10,8)
    write("TARGET  : " .. tostring(displayState.target))
    pos(10,9)
    write("DIST    : " .. tostring(math.floor((displayState.distance or 0) + 0.5)))
    pos(10,10)
    write("ETA     : " .. tostring(displayState.rtt))
    pos(10,11)
    write("SPEED   : " .. tostring(speed))
    pos(10,12)
    write("ALTITUDE: " .. tostring(math.floor((posWs.y or 0) + 0.5)))
    pos(10,13)
    write("HEADING : " .. tostring(heading))

    tCol(colors.black)
    bCol(colors.cyan)
    pos(11,15)
    write(" CONTROLS ")

    tCol(colors.black)
    bCol(colors.orange)
    pos(32,15)
    write(" BACK ")
end

------------------------------------------------------------
function drawControlsMenu()
    cls()
    pos(1,1)
    box(1,1,x,y,colors.lightBlue) -- Background

    local borderColor = colors.lightGray
    if doorsActive and doorsFlashOn then
        borderColor = colors.red
    end
    drawOuterFrame(borderColor)

    box(8,5,44,14,colors.gray) -- Window
    line(8,5,44,5,colors.lightGray) -- Top bar
    line(42,5,44,5,colors.red) -- Exit

    tCol(colors.black)
    bCol(colors.lightBlue)
    pos(15,3)
    write(" CONTROLS FOLDER ")

    tCol(colors.black)
    bCol(colors.red)
    pos(43,5)
    write("X")

    -- Outward arrow controls (toggle on/off)
    bCol(controlState.left and colors.green or colors.blue)
    tCol(colors.yellow)
    pos(12,10)
    write("  <  ")

    bCol(controlState.right and colors.green or colors.blue)
    pos(38,10)
    write("  >  ")

    bCol(controlState.up and colors.green or colors.blue)
    pos(25,8)
    write("  ^  ")

    bCol(controlState.down and colors.green or colors.blue)
    pos(25,12)
    write("  v  ")

    -- Doors toggle button
    bCol(doorsActive and colors.red or colors.lightGray)
    tCol(colors.black)
    pos(18,14)
    write("      DOORS      ")

    tCol(colors.black)
    bCol(colors.orange)
    pos(20,16)
    write(" < BACK ")
end

------------------------------------------------------------
function drawWeaponsMenu()
    cls()
    pos(1,1)
    box(1,1,x,y,colors.lightBlue) -- Background
    box(8,5,44,14,colors.gray) -- Window
    line(8,5,44,5,colors.lightGray) -- Top bar
    line(42,5,44,5,colors.red) -- Exit

    tCol(colors.black)
    bCol(colors.lightBlue)
    pos(16,3)
    write(" WEAPONS ")

    tCol(colors.black)
    bCol(colors.red)
    pos(43,5)
    write("X")

    tCol(colors.black)
    bCol(colors.lightGray)

    -- centered top row
    pos(18,8)
    write("MSL")
    pos(23,8)
    write(" CANNON ")
    pos(33,8)
    write("MSL")

    -- centered second row
    pos(10,10)
    write(" BOMBS ")
    pos(18,10)
    write(" BOMBS ")
    pos(28,10)
    write(" BOMBS ")
    pos(36,10)
    write(" BOMBS ")

    bCol(colors.red)
    pos(23,12)
    write(" FLARES ")

    drawWeaponSend()

    tCol(colors.white)
    bCol(colors.gray)
    pos(20,16)
    write(" BACK ")
end

------------------------------------------------------------
function main()
    while true do
        if currentMenu == "main" then
            drawMainMenu()
        elseif currentMenu == "autopilot" then
            drawAutopilotMenu()
        elseif currentMenu == "status" then
            drawStatusMenu()
        elseif currentMenu == "controls" then
            drawControlsMenu()
        elseif currentMenu == "weapons" then
            drawWeaponsMenu()
        elseif currentMenu == "engaged" then
            drawEngagedMenu()
        end

        local timerId = nil
        if currentMenu == "controls" and (doorsActive or anyControlActive()) then
            timerId = os.startTimer(0.05)
        elseif currentMenu == "status" then
            timerId = os.startTimer(0.2)
        elseif currentMenu == "weapons" and weaponSend ~= nil then
            timerId = os.startTimer(0.05)
        elseif currentMenu == "engaged" then
            timerId = os.startTimer(0.2)
        else
            timerId = os.startTimer(0.5)
        end

        local event, p1, p2, p3 = os.pullEvent()

        if event == "timer" and p1 == timerId then
            if currentMenu == "controls" then
                if doorsActive then
                    doorsFlashOn = not doorsFlashOn
                else
                    doorsFlashOn = false
                end

                if anyControlActive() then
                    applyControlThrust()
                end
            elseif currentMenu == "engaged" then
                autopilotTick()
            end

            displayState.mode = currentMenu
            if currentMenu ~= "weapons" then
                displayState.target = displayState.target or "-"
            end
            sendDisplayTelemetry()

        elseif event == "mouse_click" then
            local button, mx, my = p1, p2, p3
            if currentMenu == "main" then
                if mx >= 18 and mx <= 34 and my == 9 and button == 1 then
                    currentMenu = "autopilot"

                elseif mx >= 23 and mx <= 30 and my == 11 and button == 1 then
                    currentMenu = "status"

                elseif mx >= 22 and mx <= 30 and my == 13 and button == 1 then
                    currentMenu = "weapons"

                elseif mx >= 38 and mx <= 40 and my == 6 and button == 1 then
                    local monitor = peripheral.find("monitor")
                    if monitor ~= nil then
                        monitor.clear()
                    end
                    os.reboot()
                end

            elseif currentMenu == "autopilot" then
                if mx >= 20 and mx <= 30 and my == 9 and button == 1 then
                    showSaved()

                elseif mx >= 16 and mx <= 34 and my == 11 and button == 1 then
                    enterWaypoints()

                elseif mx >= 22 and mx <= 30 and my == 13 and button == 1 then
                    engage()

                elseif mx >= 20 and mx <= 27 and my == 16 and button == 1 then
                    currentMenu = "main"

                elseif mx >= 38 and mx <= 40 and my == 6 and button == 1 then
                    currentMenu = "main"
                end

            elseif currentMenu == "status" then
                if mx >= 11 and mx <= 20 and my == 15 and button == 1 then
                    currentMenu = "controls"

                elseif mx >= 32 and mx <= 37 and my == 15 and button == 1 then
                    currentMenu = "main"

                elseif mx >= 42 and mx <= 44 and my == 5 and button == 1 then
                    currentMenu = "main"
                end

            elseif currentMenu == "controls" then
                if mx >= 12 and mx <= 16 and my == 10 and button == 1 then
                    controlState.left = not controlState.left

                elseif mx >= 38 and mx <= 42 and my == 10 and button == 1 then
                    controlState.right = not controlState.right

                elseif mx >= 25 and mx <= 29 and my == 8 and button == 1 then
                    controlState.up = not controlState.up

                elseif mx >= 25 and mx <= 29 and my == 12 and button == 1 then
                    controlState.down = not controlState.down

                elseif mx >= 18 and mx <= 34 and my == 14 and button == 1 then
                    doorsActive = not doorsActive
                    if doorsActive then
                        sendSlaveCommand("AIRSTAIR_DOOR_ON")
                        sendDisplayEvent("DOORS ON")
                    else
                        doorsFlashOn = false
                        sendSlaveCommand("AIRSTAIR_DOOR_OFF")
                        sendDisplayEvent("DOORS OFF")
                    end

                elseif mx >= 20 and mx <= 27 and my == 16 and button == 1 then
                    currentMenu = "status"

                elseif mx >= 42 and mx <= 44 and my == 5 and button == 1 then
                    currentMenu = "status"
                end


            elseif currentMenu == "engaged" then
                if mx >= 10 and mx <= 20 and my == 16 and button == 1 then
                    local v = promptNumberInput("Set speed", math.floor((autopilotRun.targetSpeed or 7) + 0.5))
                    if v ~= nil and v > 0 then
                        autopilotRun.targetSpeed = v
                    end

                elseif mx >= 23 and mx <= 31 and my == 16 and button == 1 then
                    local currAlt = math.floor((autopilotRun.targetAltitude or getShipAltitude()) + 0.5)
                    local v = promptNumberInput("Set altitude", currAlt)
                    if v ~= nil then
                        autopilotRun.targetAltitude = v
                    end

                elseif mx >= 34 and mx <= 40 and my == 16 and button == 1 then
                    abortAutopilotRun()

                elseif mx >= 42 and mx <= 44 and my == 5 and button == 1 then
                    abortAutopilotRun()
                end

            elseif currentMenu == "weapons" then
                if mx >= 20 and mx <= 25 and my == 16 and button == 1 then
                    currentMenu = "main"

                elseif mx >= 42 and mx <= 44 and my == 5 and button == 1 then
                    currentMenu = "main"

                elseif mx >= 18 and mx <= 20 and my == 8 and button == 1 then
                    sendSlaveCommand("MSL_LEFT")
                    sendDisplayEvent("MSL LEFT")
                    setWeaponSend(18, 9)

                elseif mx >= 23 and mx <= 30 and my == 8 and button == 1 then
                    sendSlaveCommand("CANNON")
                    sendDisplayEvent("CANNON")
                    setWeaponSend(25, 9)

                elseif mx >= 33 and mx <= 35 and my == 8 and button == 1 then
                    sendSlaveCommand("MSL_RIGHT")
                    sendDisplayEvent("MSL RIGHT")
                    setWeaponSend(33, 9)

                elseif mx >= 10 and mx <= 16 and my == 10 and button == 1 then
                    sendSlaveCommand("BOMBS_1")
                    sendDisplayEvent("BOMBS 1")
                    setWeaponSend(11, 11)

                elseif mx >= 18 and mx <= 24 and my == 10 and button == 1 then
                    sendSlaveCommand("BOMBS_2")
                    sendDisplayEvent("BOMBS 2")
                    setWeaponSend(19, 11)

                elseif mx >= 28 and mx <= 34 and my == 10 and button == 1 then
                    sendSlaveCommand("BOMBS_3")
                    sendDisplayEvent("BOMBS 3")
                    setWeaponSend(29, 11)

                elseif mx >= 36 and mx <= 42 and my == 10 and button == 1 then
                    sendSlaveCommand("BOMBS_4")
                    sendDisplayEvent("BOMBS 4")
                    setWeaponSend(37, 11)

                elseif mx >= 23 and mx <= 30 and my == 12 and button == 1 then
                    sendSlaveCommand("FLARES")
                    sendDisplayEvent("FLARES")
                    setWeaponSend(25, 13)
                end
            end
        end
    end
end

--------------------------------------------------------------
main()
