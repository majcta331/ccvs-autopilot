-- heading_display.lua
-- Green avionics-style 360-degree heading gyro.
-- Uses ship quaternion heading when available; otherwise accepts rednet heading updates.

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

local headingDeg = 0
local lastSource = "idle"

local function normalizeHeading(deg)
    deg = deg % 360
    if deg < 0 then deg = deg + 360 end
    return deg
end

local function shipHeading()
    if not ship or type(ship.getQuaternion) ~= "function" then
        return nil
    end

    local q = ship.getQuaternion()
    if not q then return nil end

    local yaw = math.atan2(2 * q.y * q.w - 2 * q.x * q.z, 1 - 2 * q.y * q.y - 2 * q.z * q.z)
    return normalizeHeading(math.deg(yaw))
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

local function ring(cx, cy, r, stepDeg, bg)
    local prevX, prevY
    for deg = 0, 360, stepDeg do
        local th = math.rad(deg - 90)
        local x = cx + math.floor(math.cos(th) * r + 0.5)
        local y = cy + math.floor(math.sin(th) * r + 0.5)
        if prevX then
            line(prevX, prevY, x, y, bg)
        end
        prevX, prevY = x, y
    end
end

local function headingPoint(cx, cy, r, deg)
    local th = math.rad(deg - 90)
    local x = cx + math.floor(math.cos(th) * r + 0.5)
    local y = cy + math.floor(math.sin(th) * r + 0.5)
    return x, y
end

local function drawTicks(cx, cy, r)
    for deg = 0, 350, 10 do
        local outerX, outerY = headingPoint(cx, cy, r, deg)
        local innerLen = (deg % 30 == 0) and 3 or 1
        local innerX, innerY = headingPoint(cx, cy, r - innerLen, deg)
        local c = (deg % 30 == 0) and colors.lime or colors.green
        line(innerX, innerY, outerX, outerY, c)
    end
end

local function drawCardinals(cx, cy, r)
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.lime)

    monitor.setCursorPos(cx, math.max(1, cy - r - 1))
    monitor.write("N")

    local w = monitor.getSize()
    monitor.setCursorPos(math.min(cx + r + 1, w), cy)
    monitor.write("E")

    monitor.setCursorPos(cx, cy + r + 1)
    monitor.write("S")

    monitor.setCursorPos(math.max(1, cx - r - 1), cy)
    monitor.write("W")
end

local function drawHeadingText(cx, y)
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.lime)
    monitor.setCursorPos(math.max(1, cx - 4), y)
    monitor.write(string.format("HDG %03d", math.floor(headingDeg + 0.5) % 360))

    monitor.setTextColor(colors.green)
    monitor.setCursorPos(math.max(1, cx - 4), y + 1)
    monitor.write("SRC " .. lastSource)
end

local function draw()
    local w, h = monitor.getSize()
    local cx = math.floor(w * 0.5)
    local cy = math.floor(h * 0.46)
    local r = math.max(5, math.min(math.floor(w * 0.28), math.floor(h * 0.34)))

    monitor.setBackgroundColor(colors.black)
    monitor.clear()

    -- Cleaner gyro look: sampled ring + inner dashed ring.
    ring(cx, cy, r, 3, colors.lime)
    ring(cx, cy, math.max(3, r - 4), 8, colors.green)

    drawTicks(cx, cy, r)
    drawCardinals(cx, cy, r)

    -- Heading needle (green avionics style).
    local nx, ny = headingPoint(cx, cy, r - 1, headingDeg)
    local tx, ty = headingPoint(cx, cy, math.floor(r * 0.45), headingDeg + 180)

    line(tx, ty, nx, ny, colors.lime)
    pixel(cx, cy, colors.lime)

    -- Subtle fixed aircraft reference at top-center.
    local refX1, refY1 = headingPoint(cx, cy, r + 1, 0)
    local refX2, refY2 = headingPoint(cx, cy, r - 2, 0)
    line(refX1, refY1, refX2, refY2, colors.green)

    drawHeadingText(cx, math.min(h - 1, cy + r + 2))
end

local function maybeUpdateFromShip()
    local deg = shipHeading()
    if deg then
        headingDeg = deg
        lastSource = "ship"
        return true
    end
    return false
end

draw()

local timer = os.startTimer(0.1)
while true do
    local event, p1, p2, p3 = os.pullEvent()

    if event == "timer" and p1 == timer then
        maybeUpdateFromShip()
        draw()
        timer = os.startTimer(0.1)

    elseif event == "rednet_message" and p3 == PROTOCOL then
        if type(p2) == "table" then
            if type(p2.heading_deg) == "number" then
                headingDeg = normalizeHeading(p2.heading_deg)
                lastSource = "rednet"
            elseif type(p2.heading) == "number" then
                headingDeg = normalizeHeading(p2.heading)
                lastSource = "rednet"
            end
        elseif type(p2) == "number" then
            headingDeg = normalizeHeading(p2)
            lastSource = "rednet"
        end
        draw()

    elseif event == "monitor_resize" then
        draw()
    end
end
