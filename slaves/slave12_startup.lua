-- startup.lua for SLAVE #12
-- Role: Weapons + Airstair Door receiver
-- Modem side: bottom
-- Available output sides: left/right/back/top

local MODEM_SIDE = "bottom"
local PROTOCOL = "ccvs-autopilot"

-- Configure outputs for this slave
local SIDES = {
    CANNON = "left",
    BOMBS_1 = "right",
    BOMBS_2 = "back",
    AIRSTAIR_DOOR = "top",
}

local PULSE_SECONDS = 0.5
local DOOR_ON_SECONDS = 2.0      -- longer pulse when DOORS toggled on
local DOOR_OFF_SECONDS = 0.25    -- shorter pulse when DOORS toggled off

if os.getComputerID() ~= 12 then
    print("Warning: this file is intended for computer #12")
end

if peripheral.getType(MODEM_SIDE) ~= "modem" then
    error("No modem on side: " .. MODEM_SIDE)
end

rednet.open(MODEM_SIDE)

redstone.setOutput(SIDES.AIRSTAIR_DOOR, false)
redstone.setOutput(SIDES.CANNON, false)
redstone.setOutput(SIDES.BOMBS_1, false)
redstone.setOutput(SIDES.BOMBS_2, false)

local function pulse(side, seconds, label)
    redstone.setOutput(side, true)
    sleep(seconds)
    redstone.setOutput(side, false)
    print(label)
end

print("Slave #12 ONLINE")
print("Modem:", MODEM_SIDE)

while true do
    local senderId, message = rednet.receive(PROTOCOL)

    if message == "CANNON" then
        pulse(SIDES.CANNON, PULSE_SECONDS, "CANNON")

    elseif message == "BOMBS_1" then
        pulse(SIDES.BOMBS_1, PULSE_SECONDS, "BOMBS_1")

    elseif message == "BOMBS_2" then
        pulse(SIDES.BOMBS_2, PULSE_SECONDS, "BOMBS_2")

    elseif message == "AIRSTAIR_DOOR_ON" then
        pulse(SIDES.AIRSTAIR_DOOR, DOOR_ON_SECONDS, "AIRSTAIR_DOOR_ON")

    elseif message == "AIRSTAIR_DOOR_OFF" then
        pulse(SIDES.AIRSTAIR_DOOR, DOOR_OFF_SECONDS, "AIRSTAIR_DOOR_OFF")

    else
        print("Ignored from", senderId, ":", tostring(message))
    end
end
