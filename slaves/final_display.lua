-- final_display.lua
-- Combined display:
--   Left side : 4 gauges (speed, altitude, heading, vertical speed)
--   Right side: plane silhouette from display_slave20 with same alert coloring logic

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

local state = {
    speed = 0,
    altitude = 64,
    heading = 0,
    vspeed = 0,
    source = "idle",
    pulseTicks = 0,
}

local function clamp(v, mn, mx)
    if v < mn then return mn end
    if v > mx then return mx end
    return v
end

local function normHeading(v)
    v = v % 360
    if v < 0 then v = v + 360 end
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

local function headingFromShip()
    if not ship then return false end

    local okPos, pos = pcall(ship.getWorldspacePosition)
    local okVel, vel = pcall(ship.getVelocity)
    local okQuat, quat = pcall(ship.getQuaternion)

    if okPos and pos and pos.y then
        state.altitude = pos.y
    end

    if okVel and vel then
        local vx = vel.x or 0
        local vy = vel.y or 0
        local vz = vel.z or 0
        state.speed = math.sqrt(vx * vx + vz * vz)
        state.vspeed = vy
    end

    if okQuat and quat then
        local yaw = math.atan2(2 * quat.y * quat.w - 2 * quat.x * quat.z, 1 - 2 * quat.y * quat.y - 2 * quat.z * quat.z)
        state.heading = normHeading(math.deg(yaw))
    end

    state.source = "ship"
    return okPos or okVel or okQuat
end

local function updateFromTelemetry(msg)
    if type(msg) ~= "table" then return end
    if type(msg.speed) == "number" then state.speed = msg.speed end
    if type(msg.altitude) == "number" then state.altitude = msg.altitude end
    if type(msg.y) == "number" then state.altitude = msg.y end
    if type(msg.heading_deg) == "number" then state.heading = normHeading(msg.heading_deg) end
    if type(msg.heading) == "number" then state.heading = normHeading(msg.heading) end
    if type(msg.vspeed) == "number" then state.vspeed = msg.vspeed end
    state.source = "rednet"
end

local function ring(cx, cy, r, step, color, minX, maxX)
    local px, py
    for deg = -140, 140, step do
        local th = math.rad(deg - 90)
        local x = cx + math.floor(math.cos(th) * r + 0.5)
        local y = cy + math.floor(math.sin(th) * r + 0.5)
        if x >= minX and x <= maxX then
            if px and px >= minX and px <= maxX then
                line(px, py, x, y, color)
            else
                pixel(x, y, color)
            end
        end
        px, py = x, y
    end
end

local function drawGauge(cx, cy, r, label, value, minV, maxV, unit, minX, maxX)
    ring(cx, cy, r, 4, colors.green, minX, maxX)
    ring(cx, cy, math.max(2, r - 2), 8, colors.lime, minX, maxX)

    for i = 0, 10 do
        local deg = -140 + (i / 10) * 280
        local th = math.rad(deg - 90)
        local ox = cx + math.floor(math.cos(th) * r + 0.5)
        local oy = cy + math.floor(math.sin(th) * r + 0.5)
        local il = (i % 2 == 0) and 3 or 2
        local ix = cx + math.floor(math.cos(th) * (r - il) + 0.5)
        local iy = cy + math.floor(math.sin(th) * (r - il) + 0.5)
        if ox >= minX and ox <= maxX and ix >= minX and ix <= maxX then
            line(ix, iy, ox, oy, colors.lime)
        end
    end

    local t = 0
    if maxV > minV then
        t = clamp((value - minV) / (maxV - minV), 0, 1)
    end
    local pdeg = -140 + t * 280
    local pth = math.rad(pdeg - 90)
    local px = cx + math.floor(math.cos(pth) * (r - 1) + 0.5)
    local py = cy + math.floor(math.sin(pth) * (r - 1) + 0.5)
    if px >= minX and px <= maxX then
        line(cx, cy, px, py, colors.red)
    end
    pixel(cx, cy, colors.lime)

    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.lime)
    local lx = math.max(minX, cx - math.floor(#label / 2))
    monitor.setCursorPos(lx, math.max(1, cy - r - 1))
    monitor.write(label)

    local valueText = string.format("%.1f", value)
    local vx = math.max(minX, cx - math.floor(#valueText / 2))
    monitor.setCursorPos(vx, cy + r + 1)
    monitor.write(valueText)

    monitor.setTextColor(colors.green)
    local ux = math.max(minX, cx - math.floor(#unit / 2))
    monitor.setCursorPos(ux, cy + r + 2)
    monitor.write(unit)
end

-- Plane silhouette section (kept same shape/alerts as display_slave20)
local function drawOneSideLine(cx, side, x1, y1, x2, y2, color)
    local sign = (side == "left") and -1 or 1
    line(cx + sign * x1, y1, cx + sign * x2, y2, color)
end

local function drawSymmetricLine(cx, x1, y1, x2, y2, color)
    line(cx + x1, y1, cx + x2, y2, color)
    if x1 ~= 0 or x2 ~= 0 then
        line(cx - x1, y1, cx - x2, y2, color)
    end
end

local function drawPlane(rightMinX, rightMaxX)
    local _, h = monitor.getSize()

    local planeHeight = math.min(h - 3, 34)
    local topY = math.max(1, math.floor((h - planeHeight) / 2))

    local cx = math.floor((rightMinX + rightMaxX) * 0.5)
    local desiredHalf = 22
    local availableHalf = math.max(6, math.floor((rightMaxX - rightMinX - 3) / 2))
    local sx = math.min(1, availableHalf / desiredHalf)

    local function X(v)
        return math.floor(v * sx + 0.5)
    end

    local half = {
        {0, 0},
        {1, 1}, {2, 3}, {2, 7},
        {5, 10}, {9, 13}, {13, 16},
        {17, 19}, {20, 21},
        {20, 23}, {16, 23}, {12, 22},
        {5, 20},

        {3, 20}, {3, 26},
        {6, 29}, {9, 31},
        {11, 32}, {6, 34}, {2, 35},
        {0, 36}
    }

    local maxHalf = 0
    for i = 1, #half do
        local xv = X(half[i][1])
        if xv > maxHalf then maxHalf = xv end
    end
    cx = math.max(rightMinX + maxHalf + 1, math.min(rightMaxX - maxHalf - 1, cx))

    local srcYMax = half[#half][2]
    local function Y(v)
        return topY + math.floor((v / srcYMax) * math.max(1, planeHeight - 1) + 0.5)
    end

    for i = 1, #half - 1 do
        local x1, y1 = X(half[i][1]), Y(half[i][2])
        local x2, y2 = X(half[i + 1][1]), Y(half[i + 1][2])
        drawSymmetricLine(cx, x1, y1, x2, y2, colors.white)
    end

    for i = 1, #half - 1 do
        local x1, y1 = math.max(0, X(half[i][1]) - 1), Y(half[i][2])
        local x2, y2 = math.max(0, X(half[i + 1][1]) - 1), Y(half[i + 1][2])
        drawSymmetricLine(cx, x1, y1, x2, y2, colors.lightGray)
    end

    -- Same alert functions as display_slave20
    if redstone.getInput("right") then
        for i = 5, 12 do
            local x1, y1 = X(half[i][1]), Y(half[i][2])
            local x2, y2 = X(half[i + 1][1]), Y(half[i + 1][2])
            drawOneSideLine(cx, "right", x1, y1, x2, y2, colors.red)
        end
    end

    if redstone.getInput("left") then
        for i = 5, 12 do
            local x1, y1 = X(half[i][1]), Y(half[i][2])
            local x2, y2 = X(half[i + 1][1]), Y(half[i + 1][2])
            drawOneSideLine(cx, "left", x1, y1, x2, y2, colors.red)
        end
    end

    if redstone.getInput("front") then
        for i = 1, 5 do
            local x1, y1 = X(half[i][1]), Y(half[i][2])
            local x2, y2 = X(half[i + 1][1]), Y(half[i + 1][2])
            drawSymmetricLine(cx, x1, y1, x2, y2, colors.red)
        end
        line(cx, Y(0), cx, Y(2), colors.red)
    end

    if redstone.getInput("top") then
        local tailStart = math.max(1, #half - 7)
        for i = tailStart, #half - 1 do
            local x1, y1 = X(half[i][1]), Y(half[i][2])
            local x2, y2 = X(half[i + 1][1]), Y(half[i + 1][2])
            drawSymmetricLine(cx, x1, y1, x2, y2, colors.red)
        end
    end
end

local function draw()
    local w, h = monitor.getSize()
    monitor.setBackgroundColor(colors.black)
    monitor.clear()

    local splitX = math.max(20, math.floor(w * 0.50))

    -- divider
    for y = 1, h do
        pixel(splitX, y, colors.green)
    end

    -- Left: 2x2 gauges
    local leftMinX, leftMaxX = 1, splitX - 1
    local leftW = math.max(10, leftMaxX - leftMinX + 1)
    local cols, rows = 2, 2
    local cellW = math.floor(leftW / cols)
    local cellH = math.floor(h / rows)
    local r = math.max(3, math.min(math.floor(cellW * 0.28), math.floor(cellH * 0.30)))

    local c = {}
    for row = 1, rows do
        for col = 1, cols do
            local cx = leftMinX + math.floor((col - 0.5) * cellW)
            local cy = math.floor((row - 0.5) * cellH)
            c[#c + 1] = {cx = cx, cy = cy}
        end
    end

    drawGauge(c[1].cx, c[1].cy, r, "SPEED", state.speed, 0, 120, "m/s", leftMinX, leftMaxX)
    drawGauge(c[2].cx, c[2].cy, r, "ALT", state.altitude, 0, 300, "y", leftMinX, leftMaxX)
    drawGauge(c[3].cx, c[3].cy, r, "HDG", state.heading, 0, 360, "deg", leftMinX, leftMaxX)
    drawGauge(c[4].cx, c[4].cy, r, "V/S", state.vspeed, -20, 20, "m/s", leftMinX, leftMaxX)

    -- Right: plane display with same functions as slave20
    drawPlane(splitX + 1, w)

    if state.pulseTicks > 0 then
        line(1, 1, w, 1, colors.gray)
        line(1, h, w, h, colors.gray)
        state.pulseTicks = state.pulseTicks - 1
    end

    monitor.setTextColor(colors.green)
    monitor.setBackgroundColor(colors.black)
    monitor.setCursorPos(1, h)
    monitor.write("SRC:" .. state.source)
end

headingFromShip()
draw()

local timer = os.startTimer(0.12)
while true do
    local event, p1, p2, p3 = os.pullEvent()

    if event == "timer" and p1 == timer then
        headingFromShip()
        draw()
        timer = os.startTimer(0.12)

    elseif event == "rednet_message" and p3 == PROTOCOL then
        if type(p2) == "table" then
            updateFromTelemetry(p2)
            state.pulseTicks = 2
        end
        draw()

    elseif event == "redstone" or event == "monitor_resize" then
        draw()
    end
end
