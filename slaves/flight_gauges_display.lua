-- flight_gauges_display.lua
-- Green multi-gauge avionics panel for speed, altitude, heading and engine-style metrics.

local MONITOR_SIDE = "back"
local MODEM_SIDE = "bottom"
local PROTOCOL = "ccvs-autopilot"

local monitor = peripheral.wrap(MONITOR_SIDE)
if not monitor then
    error("No monitor on side: " .. MONITOR_SIDE)
end
monitor.setTextScale(0.5)

if peripheral.getType(MODEM_SIDE) == "modem" then
    rednet.open(MODEM_SIDE)
end

local data = {
    speed = 0,        -- blocks/s
    altitude = 64,    -- Y
    heading = 0,      -- degrees
    climb = 0,        -- vertical speed
    n1 = 0,           -- synthetic/telemetry if provided
    oil = 0,
    source = "idle"
}

local function normHeading(v)
    v = v % 360
    if v < 0 then v = v + 360 end
    return v
end

local function clamp(v, mn, mx)
    if v < mn then return mn end
    if v > mx then return mx end
    return v
end

local function pixel(x, y, bg)
    local w, h = monitor.getSize()
    if x < 1 or y < 1 or x > w or y > h then return end
    monitor.setCursorPos(x, y)
    monitor.setBackgroundColor(bg)
    monitor.write(" ")
end

local function line(x1, y1, x2, y2, bg)
    local dx = math.abs(x2 - x1)
    local sx = (x1 < x2) and 1 or -1
    local dy = -math.abs(y2 - y1)
    local sy = (y1 < y2) and 1 or -1
    local err = dx + dy

    while true do
        pixel(x1, y1, bg)
        if x1 == x2 and y1 == y2 then break end
        local e2 = 2 * err
        if e2 >= dy then
            err = err + dy
            x1 = x1 + sx
        end
        if e2 <= dx then
            err = err + dx
            y1 = y1 + sy
        end
    end
end

local function ring(cx, cy, r, step, color)
    local px, py
    for deg = -140, 140, step do
        local th = math.rad(deg - 90)
        local x = cx + math.floor(math.cos(th) * r + 0.5)
        local y = cy + math.floor(math.sin(th) * r + 0.5)
        if px then line(px, py, x, y, color) end
        px, py = x, y
    end
end

local function drawGauge(cx, cy, r, label, value, minV, maxV, unit)
    ring(cx, cy, r, 4, colors.green)
    ring(cx, cy, math.max(2, r - 2), 8, colors.lime)

    -- ticks
    for i = 0, 10 do
        local deg = -140 + (i / 10) * 280
        local th = math.rad(deg - 90)
        local ox = cx + math.floor(math.cos(th) * r + 0.5)
        local oy = cy + math.floor(math.sin(th) * r + 0.5)
        local ix = cx + math.floor(math.cos(th) * (r - (i % 2 == 0 and 3 or 2)) + 0.5)
        local iy = cy + math.floor(math.sin(th) * (r - (i % 2 == 0 and 3 or 2)) + 0.5)
        line(ix, iy, ox, oy, colors.lime)
    end

    -- pointer
    local t = 0
    if maxV > minV then
        t = clamp((value - minV) / (maxV - minV), 0, 1)
    end
    local pdeg = -140 + t * 280
    local pth = math.rad(pdeg - 90)
    local px = cx + math.floor(math.cos(pth) * (r - 1) + 0.5)
    local py = cy + math.floor(math.sin(pth) * (r - 1) + 0.5)
    line(cx, cy, px, py, colors.red)
    pixel(cx, cy, colors.lime)

    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.lime)
    monitor.setCursorPos(math.max(1, cx - math.floor(#label / 2)), math.max(1, cy - r - 1))
    monitor.write(label)

    local text = string.format("%.1f", value)
    monitor.setCursorPos(math.max(1, cx - math.floor(#text / 2)), math.min(cy + r + 1, ({monitor.getSize()})[2]))
    monitor.write(text)

    if unit and #unit > 0 then
        monitor.setTextColor(colors.green)
        monitor.setCursorPos(math.max(1, cx - math.floor(#unit / 2)), math.min(cy + r + 2, ({monitor.getSize()})[2]))
        monitor.write(unit)
    end
end

local function updateFromShip()
    if not ship then return false end

    local okPos, pos = pcall(ship.getWorldspacePosition)
    local okVel, vel = pcall(ship.getVelocity)
    local okQuat, quat = pcall(ship.getQuaternion)

    if okPos and pos then
        data.altitude = pos.y or data.altitude
    end

    if okVel and vel then
        local vx = vel.x or 0
        local vy = vel.y or 0
        local vz = vel.z or 0
        data.speed = math.sqrt(vx * vx + vz * vz)
        data.climb = vy
    end

    if okQuat and quat then
        local yaw = math.atan2(2 * quat.y * quat.w - 2 * quat.x * quat.z, 1 - 2 * quat.y * quat.y - 2 * quat.z * quat.z)
        data.heading = normHeading(math.deg(yaw))
    end

    data.n1 = clamp((data.speed / 80) * 100, 0, 100)
    data.oil = clamp(40 + data.n1 * 0.4, 0, 100)
    data.source = "ship"
    return true
end

local function updateFromTelemetry(msg)
    if type(msg) ~= "table" then return end
    if type(msg.speed) == "number" then data.speed = msg.speed end
    if type(msg.altitude) == "number" then data.altitude = msg.altitude end
    if type(msg.y) == "number" then data.altitude = msg.y end
    if type(msg.heading_deg) == "number" then data.heading = normHeading(msg.heading_deg) end
    if type(msg.heading) == "number" then data.heading = normHeading(msg.heading) end
    if type(msg.vspeed) == "number" then data.climb = msg.vspeed end
    if type(msg.n1) == "number" then data.n1 = clamp(msg.n1, 0, 100) end
    if type(msg.oil) == "number" then data.oil = clamp(msg.oil, 0, 100) end
    data.source = "rednet"
end

local function drawPanel()
    local w, h = monitor.getSize()
    monitor.setBackgroundColor(colors.black)
    monitor.clear()

    local cols, rows = 3, 2
    local cellW = math.floor(w / cols)
    local cellH = math.floor((h - 1) / rows)
    local r = math.max(3, math.min(math.floor(cellW * 0.28), math.floor(cellH * 0.33)))

    local centers = {}
    for row = 1, rows do
        for col = 1, cols do
            local cx = math.floor((col - 0.5) * cellW)
            local cy = math.floor((row - 0.5) * cellH)
            centers[#centers + 1] = {cx = cx, cy = cy}
        end
    end

    drawGauge(centers[1].cx, centers[1].cy, r, "SPEED", data.speed, 0, 120, "m/s")
    drawGauge(centers[2].cx, centers[2].cy, r, "ALT", data.altitude, 0, 300, "y")
    drawGauge(centers[3].cx, centers[3].cy, r, "HDG", data.heading, 0, 360, "deg")
    drawGauge(centers[4].cx, centers[4].cy, r, "CLIMB", data.climb, -20, 20, "m/s")
    drawGauge(centers[5].cx, centers[5].cy, r, "N1", data.n1, 0, 100, "%")
    drawGauge(centers[6].cx, centers[6].cy, r, "OIL", data.oil, 0, 100, "%")

    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.green)
    monitor.setCursorPos(1, h)
    monitor.write("SRC:" .. data.source)
end

updateFromShip()
drawPanel()

local timer = os.startTimer(0.12)
while true do
    local event, p1, p2, p3 = os.pullEvent()

    if event == "timer" and p1 == timer then
        updateFromShip()
        drawPanel()
        timer = os.startTimer(0.12)

    elseif event == "rednet_message" and p3 == PROTOCOL then
        updateFromTelemetry(p2)
        drawPanel()

    elseif event == "monitor_resize" then
        drawPanel()
    end
end
