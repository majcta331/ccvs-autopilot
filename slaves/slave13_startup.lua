-- startup.lua for SLAVE #13
-- Role: Weapons receiver
-- Modem side: bottom
-- Available output sides: left/right/back/top

local MODEM_SIDE = "bottom"
local PROTOCOL = "ccvs-autopilot"

local SIDES = {
    MSL_LEFT = "left",
    MSL_RIGHT = "right",
    BOMBS_3 = "back",
    BOMBS_4 = "top",
}

local DEFAULT_PULSE_SECONDS = 0.5
local MISSILE_PULSE_SECONDS = 3.0

if os.getComputerID() ~= 13 then
    print("Warning: this file is intended for computer #13")
end

if peripheral.getType(MODEM_SIDE) ~= "modem" then
    error("No modem on side: " .. MODEM_SIDE)
end

rednet.open(MODEM_SIDE)

for _, side in pairs(SIDES) do
    redstone.setOutput(side, false)
end

local function pulse(side, label, seconds)
    local pulseSeconds = seconds or DEFAULT_PULSE_SECONDS
    redstone.setOutput(side, true)
    sleep(pulseSeconds)
    redstone.setOutput(side, false)
    print(label)
end

print("Slave #13 ONLINE")
print("Modem:", MODEM_SIDE)

while true do
    local senderId, message = rednet.receive(PROTOCOL)

    if message == "MSL_LEFT" then
        pulse(SIDES.MSL_LEFT, "MSL_LEFT", MISSILE_PULSE_SECONDS)

    elseif message == "MSL_RIGHT" then
        pulse(SIDES.MSL_RIGHT, "MSL_RIGHT", MISSILE_PULSE_SECONDS)

    elseif message == "BOMBS_3" then
        pulse(SIDES.BOMBS_3, "BOMBS_3")

    elseif message == "BOMBS_4" then
        pulse(SIDES.BOMBS_4, "BOMBS_4")

    else
        print("Ignored from", senderId, ":", tostring(message))
    end
end
