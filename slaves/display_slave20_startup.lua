-- startup.lua for DISPLAY SLAVE #20
-- Role: tactical silhouette monitor (no text overlay)
-- Modem side: bottom
-- Monitor side: back

local MODEM_SIDE = "bottom"
local MONITOR_SIDE = "back"
local PROTOCOL = "ccvs-autopilot"

if os.getComputerID() ~= 20 then
    print("Warning: this file is intended for computer #20")
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

local pulseTicks = 0

local function withMonitorDraw(fn)
    local previous = term.current()
    term.redirect(monitor)
    fn()
    term.redirect(previous)
end

local function drawSymmetricLine(cx, x1, y1, x2, y2, color)
    paintutils.drawLine(cx + x1, y1, cx + x2, y2, color)
    if x1 ~= 0 or x2 ~= 0 then
        paintutils.drawLine(cx - x1, y1, cx - x2, y2, color)
    end
end

local function drawOneSideLine(cx, side, x1, y1, x2, y2, color)
    local sign = (side == "left") and -1 or 1
    paintutils.drawLine(cx + sign * x1, y1, cx + sign * x2, y2, color)
end

local function isRightWingAlertActive()
    return redstone.getInput("right")
end

local function isLeftWingAlertActive()
    return redstone.getInput("left")
end

local function isFrontAlertActive()
    return redstone.getInput("front")
end

local function isBackAlertActive()
    return redstone.getInput("top")
end

local function drawPlaneOutline()
    local w, h = monitor.getSize()

    -- Straight-line minimalist aircraft, not too wide.
    local planeHeight = math.min(h - 3, 34)
    local topY = math.max(1, math.floor((h - planeHeight) / 2))

    -- Keep silhouette on right side as requested.
    local cx = math.floor(w * 0.70)

    -- Slimmer wing span than previous versions.
    local desiredHalf = 22
    local availableHalf = math.max(6, math.floor((w - 3) / 2))
    local sx = math.min(1, availableHalf / desiredHalf)

    local function X(v)
        return math.floor(v * sx + 0.5)
    end

    -- Right-half outline vertices only (all straight segments).
    -- Includes clear 90° wing root corner and 90° rear notch.
    local half = {
        {0, 0},
        {1, 1}, {2, 3}, {2, 7},              -- nose + upper fuselage
        {5, 10}, {9, 13}, {13, 16},          -- leading edge to wing
        {17, 19}, {20, 21},                  -- wing tip
        {20, 23}, {16, 23}, {12, 22},        -- clipped outer wing trailing edge
        {5, 20},                              -- back toward wing root

        {3, 20}, {3, 26},                    -- 90° wing/fuselage corner (vertical drop)
        {6, 29}, {9, 31},                    -- rear fuselage slope
        {11, 32}, {6, 34}, {2, 35},          -- horizontal tail then taper
        {0, 36}                              -- tail center
    }

    local maxHalf = 0
    for i = 1, #half do
        local xv = X(half[i][1])
        if xv > maxHalf then maxHalf = xv end
    end

    -- clamp so it stays on-screen
    cx = math.max(maxHalf + 2, math.min(w - maxHalf - 1, cx))

    local srcYMax = half[#half][2]
    local function Y(v)
        return topY + math.floor((v / srcYMax) * math.max(1, planeHeight - 1) + 0.5)
    end

    -- continuous straight white lines
    for i = 1, #half - 1 do
        local x1, y1 = X(half[i][1]), Y(half[i][2])
        local x2, y2 = X(half[i + 1][1]), Y(half[i + 1][2])
        drawSymmetricLine(cx, x1, y1, x2, y2, colors.white)
    end

    -- subtle inset stroke for readability
    for i = 1, #half - 1 do
        local x1, y1 = math.max(0, X(half[i][1]) - 1), Y(half[i][2])
        local x2, y2 = math.max(0, X(half[i + 1][1]) - 1), Y(half[i + 1][2])
        drawSymmetricLine(cx, x1, y1, x2, y2, colors.lightGray)
    end

    -- Alerts by side input:
    -- right => right wing red, left => left wing red, front => nose/front red.
    if isRightWingAlertActive() then
        for i = 5, 12 do
            local x1, y1 = X(half[i][1]), Y(half[i][2])
            local x2, y2 = X(half[i + 1][1]), Y(half[i + 1][2])
            drawOneSideLine(cx, "right", x1, y1, x2, y2, colors.red)
        end
    end

    if isLeftWingAlertActive() then
        for i = 5, 12 do
            local x1, y1 = X(half[i][1]), Y(half[i][2])
            local x2, y2 = X(half[i + 1][1]), Y(half[i + 1][2])
            drawOneSideLine(cx, "left", x1, y1, x2, y2, colors.red)
        end
    end

    if isFrontAlertActive() then
        for i = 1, 5 do
            local x1, y1 = X(half[i][1]), Y(half[i][2])
            local x2, y2 = X(half[i + 1][1]), Y(half[i + 1][2])
            drawSymmetricLine(cx, x1, y1, x2, y2, colors.red)
        end
        -- emphasize nose center
        paintutils.drawLine(cx, Y(0), cx, Y(2), colors.red)
    end

    -- Back/tail warning on top input (kept from previous behavior).
    if isBackAlertActive() then
        local tailStart = math.max(1, #half - 7)
        for i = tailStart, #half - 1 do
            local x1, y1 = X(half[i][1]), Y(half[i][2])
            local x2, y2 = X(half[i + 1][1]), Y(half[i + 1][2])
            drawSymmetricLine(cx, x1, y1, x2, y2, colors.red)
        end
    end
end

local function draw()
    monitor.setBackgroundColor(colors.black)
    monitor.clear()

    withMonitorDraw(function()
        drawPlaneOutline()

        -- brief visual pulse when messages arrive (no text)
        if pulseTicks > 0 then
            local w, h = monitor.getSize()
            paintutils.drawLine(1, 1, w, 1, colors.gray)
            paintutils.drawLine(1, h, w, h, colors.gray)
            pulseTicks = pulseTicks - 1
        end
    end)
end

draw()
print("Display slave #20 ONLINE")

while true do
    local event, p1, p2, p3 = os.pullEvent()

    if event == "rednet_message" and p3 == PROTOCOL then
        -- p2 is the payload
        if type(p2) == "table" then
            pulseTicks = 2
        end
        draw()
    elseif event == "redstone" then
        -- side/top input changes should immediately update wing/front/back colors
        draw()
    end
end
