-- Dedicated side node: left
-- sensor_network_node.lua
-- Generic sensor node code for one side of the plane.
-- Deploy this same file to each sensor computer and set SENSOR_SIDE.

local MODEM_SIDE = "back"
local PROTOCOL = "sensor-network-v1"

-- Set this to one of: "left", "right", "front", "back"
local SENSOR_SIDE = "left"

-- Optional readable name for this sensor node
local SENSOR_NAME = "LEFT-SENSOR"

local HEARTBEAT_INTERVAL = 0.5

if peripheral.getType(MODEM_SIDE) ~= "modem" then
    error("No modem on side: " .. MODEM_SIDE)
end

rednet.open(MODEM_SIDE)

print("Sensor node online")
print("ID      :", os.getComputerID())
print("Side    :", SENSOR_SIDE)
print("Name    :", SENSOR_NAME)
print("Protocol:", PROTOCOL)

while true do
    rednet.broadcast({
        kind = "heartbeat",
        side = SENSOR_SIDE,
        name = SENSOR_NAME,
        id = os.getComputerID(),
    }, PROTOCOL)

    sleep(HEARTBEAT_INTERVAL)
end
