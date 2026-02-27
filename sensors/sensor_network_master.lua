-- sensor_network_master.lua
-- Sensor network master: watches heartbeat from sensor computers and emits redstone
-- when sensors on a side (left/right/front/back) are missing.

local MODEM_SIDE = "top"
local PROTOCOL = "sensor-network-v1"

-- Heartbeat and timeout tuning
local TIMEOUT_SECONDS = 2.0
local CHECK_INTERVAL = 0.2

-- Debounce so brief packet loss does not flash outputs
local MISS_CYCLES_TO_ALARM = 3
local GOOD_CYCLES_TO_CLEAR = 2

-- Monitoring mode:
-- "count"  : alarm if active sensors on a side drop below REQUIRED_COUNT[side]
-- "strict" : alarm if any expected ID in EXPECTED[side] is missing
local MONITOR_MODE = "count"

-- Count-mode thresholds (recommended default)
local REQUIRED_COUNT = {
    left = 8,
    right = 8,
    front = 8,
    back = 8,
}

-- Strict-mode expected IDs (optional, only used if MONITOR_MODE = "strict")
local EXPECTED = {
    left =  {101, 102, 103, 104, 105, 106, 107, 108},
    right = {29, 30, 31, 32, 41, 33, 43, 42},
    front = {121, 122, 123, 124, 125, 126, 127, 128},
    back =  {131, 132, 133, 134, 135, 136, 137, 138},
}


-- Optional fixed ID-to-side mapping.
-- If an ID is listed here, it overrides msg.side so misconfigured nodes are still counted correctly.
local SENSOR_SIDE_BY_ID = {
    [29] = "right", [30] = "right", [31] = "right", [32] = "right",
    [33] = "right", [41] = "right", [42] = "right", [43] = "right",
}

-- Redstone output sides to trigger alarms for each direction.
local OUTPUT_SIDE = {
    left = "left",
    right = "right",
    front = "front",
    back = "back",
}

if peripheral.getType(MODEM_SIDE) ~= "modem" then
    error("No modem on side: " .. MODEM_SIDE)
end
rednet.open(MODEM_SIDE)

-- lastSeen[side][id] = timestamp
local lastSeen = {
    left = {},
    right = {},
    front = {},
    back = {},
}

-- per-side debounce counters/state
local missCycles = {left = 0, right = 0, front = 0, back = 0}
local goodCycles = {left = 0, right = 0, front = 0, back = 0}
local alarmState = {left = false, right = false, front = false, back = false}

local function now()
    return os.clock()
end

local function markSeen(side, id)
    if lastSeen[side] then
        lastSeen[side][id] = now()
    end
end

local function activeCount(side)
    local t = now()
    local n = 0
    for _, seen in pairs(lastSeen[side]) do
        if (t - seen) <= TIMEOUT_SECONDS then
            n = n + 1
        end
    end
    return n
end

local function evaluateSideRaw(side)
    if MONITOR_MODE == "strict" then
        local ids = EXPECTED[side] or {}
        local t = now()
        for _, id in ipairs(ids) do
            local seen = lastSeen[side][id] or 0
            if (t - seen) > TIMEOUT_SECONDS then
                return true, "missing id " .. tostring(id)
            end
        end
        return false, "ok"
    end

    -- count mode
    local count = activeCount(side)
    local needed = REQUIRED_COUNT[side] or 1
    if count < needed then
        return true, "active " .. count .. "/" .. needed
    end
    return false, "active " .. count .. "/" .. needed
end

local function updateSideAlarm(side)
    local missing, reason = evaluateSideRaw(side)

    if missing then
        missCycles[side] = missCycles[side] + 1
        goodCycles[side] = 0
        if missCycles[side] >= MISS_CYCLES_TO_ALARM then
            alarmState[side] = true
        end
    else
        goodCycles[side] = goodCycles[side] + 1
        missCycles[side] = 0
        if goodCycles[side] >= GOOD_CYCLES_TO_CLEAR then
            alarmState[side] = false
        end
    end

    return missing, reason
end

local function applyAlarmOutputs()
    for side, outputSide in pairs(OUTPUT_SIDE) do
        -- Hold output ON only for sides currently in alarm.
        -- Other sides stay OFF.
        redstone.setOutput(outputSide, alarmState[side])
    end
end

local function printStatus(statusLines)
    term.clear()
    term.setCursorPos(1, 1)
    print("SENSOR NETWORK MASTER")
    print("Protocol: " .. PROTOCOL)
    print("Mode    : " .. MONITOR_MODE)
    print("Timeout : " .. TIMEOUT_SECONDS .. "s")
    print("")

    for _, side in ipairs({"left", "right", "front", "back"}) do
        local line = statusLines[side] or "-"
        local alarmTxt = alarmState[side] and "ALARM" or "OK"
        print(string.upper(side) .. ": " .. alarmTxt .. " | " .. line)
    end
end

-- Initialize outputs off
for _, out in pairs(OUTPUT_SIDE) do
    redstone.setOutput(out, false)
end

print("Sensor master online")

local checkTimer = os.startTimer(CHECK_INTERVAL)
while true do
    local event, p1, p2, p3 = os.pullEvent()

    if event == "rednet_message" and p3 == PROTOCOL then
        local senderId = p1
        local msg = p2

        if type(msg) == "table" and msg.kind == "heartbeat" then
            local side = SENSOR_SIDE_BY_ID[senderId]

            if side == nil and type(msg.side) == "string" then
                side = string.lower(msg.side)
            end

            if side and lastSeen[side] then
                markSeen(side, senderId)
            end
        end

    elseif event == "timer" and p1 == checkTimer then
        local statusLines = {}
        for _, side in ipairs({"left", "right", "front", "back"}) do
            local _, reason = updateSideAlarm(side)
            statusLines[side] = reason
        end
        applyAlarmOutputs()
        printStatus(statusLines)
        checkTimer = os.startTimer(CHECK_INTERVAL)
    end
end
