-- startup.lua for DISPLAY SLAVE #19
-- Role: event + digital autopilot info monitor
-- Modem side: bottom
-- Monitor side: back

local MODEM_SIDE = "bottom"
local MONITOR_SIDE = "back"
local PROTOCOL = "ccvs-autopilot"

if os.getComputerID() ~= 19 then
    print("Warning: this file is intended for computer #19")
end

if peripheral.getType(MODEM_SIDE) ~= "modem" then
    error("No modem on side: " .. MODEM_SIDE)
end

local monitor = peripheral.wrap(MONITOR_SIDE)
if monitor == nil then
    error("No monitor on side: " .. MONITOR_SIDE)
end

rednet.open(MODEM_SIDE)
monitor.setTextScale(0.5)

local state = {
    -- left side: last function pressed from master
    lastFunction = "NONE",
    lastFunctionAt = "-",

    -- right side: autopilot digital info
    mode = "IDLE",
    nav = "DISENGAGED",
    destination = "-",
    speed = 0,
    altitude = 0,
    distance = 0,
    eta = "-",
    updated = "-",
}

local function nowText()
    return textutils.formatTime(os.time(), true)
end

local function draw()
    local w, h = monitor.getSize()
    local split = math.max(18, math.floor(w * 0.38))

    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
    monitor.clear()

    -- vertical divider
    paintutils.drawLine(split, 1, split, h, colors.gray)

    -- LEFT: function pressed UI
    monitor.setCursorPos(1, 1)
    monitor.setTextColor(colors.lightGray)
    monitor.write("MASTER INPUT")

    monitor.setCursorPos(1, 3)
    monitor.setTextColor(colors.red)
    local fn = tostring(state.lastFunction)
    if #fn > split - 2 then
        fn = string.sub(fn, 1, split - 2)
    end
    monitor.write(fn)

    monitor.setCursorPos(1, 5)
    monitor.setTextColor(colors.lightGray)
    local stamp = "AT " .. tostring(state.lastFunctionAt)
    if #stamp > split - 2 then
        stamp = string.sub(stamp, 1, split - 2)
    end
    monitor.write(stamp)

    -- RIGHT: autopilot digital info (no gauges)
    local x = split + 2
    monitor.setTextColor(colors.lime)
    monitor.setCursorPos(x, 1)
    monitor.write("AUTOPILOT INFO")

    monitor.setTextColor(colors.white)
    monitor.setCursorPos(x, 3)
    monitor.write("Mode : " .. tostring(state.mode))

    monitor.setCursorPos(x, 4)
    monitor.write("Nav  : " .. tostring(state.nav))

    monitor.setCursorPos(x, 5)
    monitor.write("Dest : " .. tostring(state.destination))

    monitor.setCursorPos(x, 6)
    monitor.write("Speed: " .. tostring(state.speed))

    monitor.setCursorPos(x, 7)
    monitor.write("Hgt  : " .. tostring(state.altitude))

    monitor.setCursorPos(x, 8)
    monitor.write("Dist : " .. tostring(state.distance))

    monitor.setCursorPos(x, 9)
    monitor.write("ETA  : " .. tostring(state.eta))

    monitor.setCursorPos(x, 11)
    monitor.setTextColor(colors.lightGray)
    monitor.write("Updated: " .. tostring(state.updated))
end

local function applyTelemetry(msg)
    -- supports current and likely field variants
    state.mode = msg.mode or state.mode
    state.nav = msg.nav or state.nav
    state.destination = msg.destination or msg.target or state.destination
    state.speed = msg.speed or state.speed
    state.altitude = msg.altitude or msg.height or msg.y or state.altitude
    state.distance = msg.distance or state.distance
    state.eta = msg.eta or msg.rtt or state.eta
    state.updated = nowText()
end

local function applyEvent(msg)
    local ev = msg.event or msg.name or msg.action or msg.command or "EVENT"
    state.lastFunction = string.upper(tostring(ev))
    state.lastFunctionAt = nowText()
    state.updated = state.lastFunctionAt
end

draw()
print("Display slave #19 ONLINE")

while true do
    local _, message = rednet.receive(PROTOCOL)

    if type(message) == "table" then
        if message.kind == "telemetry" then
            applyTelemetry(message)
            draw()
        elseif message.kind == "event" then
            applyEvent(message)
            draw()
        end
    elseif type(message) == "string" then
        -- fallback: plain string command treated as pressed function
        state.lastFunction = string.upper(message)
        state.lastFunctionAt = nowText()
        state.updated = state.lastFunctionAt
        draw()
    end
end
