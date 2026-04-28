-- test.lua
-- Simple bank test UI for VS:CC ships.
-- Click LEFT or RIGHT to bank the ship gently, hold for 10s, then level.

function pos(...) return term.setCursorPos(...) end
function cls(...) return term.clear() end
function tCol(...) return term.setTextColor(...) end
function bCol(...) return term.setBackgroundColor(...) end
function box(...) return paintutils.drawFilledBox(...) end
function line(...) return paintutils.drawLine(...) end

local w, h = term.getSize()

local BANK_DEGREES = 12
local HOLD_SECONDS = 10
local LOOP_DELAY = 0.05

local function getRollRadians()
    local q = ship.getQuaternion()
    -- Roll estimate from quaternion.
    return math.atan2(2 * (q.w * q.x + q.y * q.z), 1 - 2 * (q.x * q.x + q.y * q.y))
end

local function getRollDegrees()
    return math.deg(getRollRadians())
end

local function drawHeader(title)
    box(1, 1, w, h, colors.lightBlue)
    box(8, 4, w - 7, h - 3, colors.gray)
    line(8, 4, w - 7, 4, colors.lightGray)

    tCol(colors.black)
    bCol(colors.lightBlue)
    pos(10, 2)
    write(" BANK TEST ")

    tCol(colors.black)
    bCol(colors.gray)
    pos(10, 5)
    write(title)
end

local function drawMenu()
    drawHeader("Choose a bank direction")

    bCol(colors.blue)
    tCol(colors.white)
    pos(13, 9)
    write("   LEFT   ")

    bCol(colors.blue)
    tCol(colors.white)
    pos(w - 22, 9)
    write("  RIGHT   ")

    bCol(colors.red)
    tCol(colors.white)
    pos(math.floor(w / 2) - 4, h - 4)
    write("  EXIT  ")
end

local function drawStatus(label, targetDeg, remaining)
    drawHeader(label)

    local roll = getRollDegrees()

    bCol(colors.gray)
    tCol(colors.black)
    pos(10, 7)
    write(string.format("Current bank : %6.2f deg   ", roll))
    pos(10, 8)
    write(string.format("Target bank  : %6.2f deg   ", targetDeg))
    pos(10, 9)
    write(string.format("Time left    : %6.2f s     ", math.max(0, remaining)))
end

local function applyBank(targetDeg)
    local mass = ship.getMass()

    local function controlToTarget(seconds, gain)
        local t0 = os.clock()
        while os.clock() - t0 < seconds do
            local roll = getRollDegrees()
            local err = targetDeg - roll

            if math.abs(err) > 0.5 then
                local torque = math.max(-1, math.min(1, err / 10)) * gain * mass
                ship.applyRotDependentTorque(0, 0, torque)
            end

            local remaining = seconds - (os.clock() - t0)
            drawStatus("Banking...", targetDeg, remaining)
            sleep(LOOP_DELAY)
        end
    end

    controlToTarget(1.2, 70)

    local holdStart = os.clock()
    while os.clock() - holdStart < HOLD_SECONDS do
        local roll = getRollDegrees()
        local err = targetDeg - roll

        if math.abs(err) > 0.25 then
            local torque = math.max(-1, math.min(1, err / 8)) * 45 * mass
            ship.applyRotDependentTorque(0, 0, torque)
        end

        local remaining = HOLD_SECONDS - (os.clock() - holdStart)
        drawStatus("Holding bank...", targetDeg, remaining)
        sleep(LOOP_DELAY)
    end

    local recoverStart = os.clock()
    while os.clock() - recoverStart < 4 do
        local roll = getRollDegrees()
        local err = -roll

        if math.abs(err) < 0.6 then
            break
        end

        local torque = math.max(-1, math.min(1, err / 10)) * 65 * mass
        ship.applyRotDependentTorque(0, 0, torque)

        local remaining = 4 - (os.clock() - recoverStart)
        drawStatus("Leveling...", 0, remaining)
        sleep(LOOP_DELAY)
    end

    drawStatus("Complete", 0, 0)
    sleep(0.7)
end

local function main()
    while true do
        drawMenu()
        local event, button, mx, my = os.pullEvent("mouse_click")

        if button == 1 then
            if my == 9 and mx >= 13 and mx <= 22 then
                applyBank(-BANK_DEGREES)
            elseif my == 9 and mx >= w - 22 and mx <= w - 13 then
                applyBank(BANK_DEGREES)
            elseif my == h - 4 and mx >= math.floor(w / 2) - 4 and mx <= math.floor(w / 2) + 3 then
                cls()
                return
            end
        end
    end
end

main()
