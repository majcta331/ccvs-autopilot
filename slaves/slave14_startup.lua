-- startup.lua for SLAVE #14
-- Role: Weapons receiver (flares)
-- Modem side: bottom
-- Available output sides: left/right/back/top

local MODEM_SIDE = "bottom"
local PROTOCOL = "ccvs-autopilot"
local FLARES_SIDE = "left"
local PULSE_SECONDS = 0.5

if os.getComputerID() ~= 14 then
    print("Warning: this file is intended for computer #14")
end

if peripheral.getType(MODEM_SIDE) ~= "modem" then
    error("No modem on side: " .. MODEM_SIDE)
end

rednet.open(MODEM_SIDE)
redstone.setOutput(FLARES_SIDE, false)

print("Slave #14 ONLINE")
print("Modem:", MODEM_SIDE)

while true do
    local senderId, message = rednet.receive(PROTOCOL)

    if message == "FLARES" then
        redstone.setOutput(FLARES_SIDE, true)
        sleep(PULSE_SECONDS)
        redstone.setOutput(FLARES_SIDE, false)
        print("FLARES")
    else
        print("Ignored from", senderId, ":", tostring(message))
    end
end
