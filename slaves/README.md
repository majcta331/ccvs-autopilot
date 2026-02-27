# Slave computer startup files

These startup files are for the current `autopilot.lua` rednet command map.

## Modem side
- Master computer modem: `bottom`
- Slave computer modem: `bottom`

## IDs used
- First slave: `#12`
- Next: `#13`
- Next: `#14`
- (`#15` currently not needed for the mapped functions)

## Command routing used by `autopilot.lua`
- Slave `#12`: `CANNON`, `BOMBS_1`, `BOMBS_2`, `AIRSTAIR_DOOR_ON`, `AIRSTAIR_DOOR_OFF`
- Slave `#13`: `MSL_LEFT`, `MSL_RIGHT`, `BOMBS_3`, `BOMBS_4`
- Slave `#14`: `FLARES`

## Door pulse behavior
- `AIRSTAIR_DOOR_ON` -> long pulse (`2.0s` by default)
- `AIRSTAIR_DOOR_OFF` -> short pulse (`0.25s` by default)

## Deploy
1. Copy the matching file to each computer as `startup.lua`.
2. Adjust side mappings inside each file if your wiring differs.
3. Reboot each slave computer.


## Display slaves (monitor only, no redstone output)
- Slave `#19`: telemetry display monitor on `back` (speed + autopilot status).
- Slave `#20`: event display monitor on `back` (button/event log).

Use:
- `slaves/display_slave19_startup.lua` on computer `#19`.
- `slaves/display_slave20_startup.lua` on computer `#20`.
