# Lever v1: build guide

One throttle lever for roadmap M3. Gate: it shows up as a game controller, and throttle jitter at rest is at most ±2 counts (serial command `j`).

## Print first

`cad/stl/coupon_608.stl`. Press a 608ZZ in. It should need firm thumb pressure and stay put when shaken. Too tight: lower `brg_od` in `cad/params.scad` by 0.05. Too loose: raise it. Rebuild with `python cad/build.py`.

## Print list (PETG, 4 walls, 35% gyroid, 0.2 mm layers)

| File | Qty | Orientation in the STL | Notes |
|---|---|---|---|
| `cheek_R.stl`, `cheek_L.stl` | 1 each | Inner face down | Bearing pocket faces the bed. No supports. |
| `hub.stl` | 1 | Side face down | The M4 nut trap opens on the bed side. |
| `block.stl` | 1 | Rear face down | |
| `shoe.stl` | 1 | Flat end down | Glue a 10 mm felt dot to the curved face. |
| `post_sleeve.stl` | 2 | Upright | |
| `magnet_cap.stl` | 1 | Bore down | |
| `bracket.stl` | 1 | Back face down | |
| `grip.stl` | 1 | Socket down | Tallest part, 150 mm. |

## Hardware

| Part | Qty | For |
|---|---|---|
| 608ZZ bearing | 2 | Pivot |
| 8 mm D-shaft, stainless or aluminium, cut to 64 mm | 1 | Pivot. Steel near the magnet skews the reading. |
| 16 mm OD aluminium tube, cut to 189 mm | 1 | Arm. Wires run inside it. A 5/8" dowel works but then wires run outside. |
| M5 × 60 bolt + nut + 2 washers | 2 | Bumper posts (the posts are also the hard stops) |
| M5 × 25 bolt or thumbscrew + M5 nut | 1 | Friction adjust, through the rear block |
| M4 heat-set insert | 6 | Block ×4, hub socket ×1, grip ×1 |
| M4 × 10 bolt | 4 | Cheeks to block |
| M4 × 6 grub screw | 2 | Tube clamps (hub, grip) |
| M4 × 20 grub screw + M4 nut | 1 | Hub to shaft, onto the D flat |
| M3 heat-set insert + M3 × 25 screw | 2 each | Sensor bracket to the right cheek |
| AS5600 breakout + 6 × 2.5 mm diametric magnet | 1 | Throttle angle |
| Raspberry Pi Pico | 1 | Controller (one Pico runs both levers later) |
| 12 mm momentary button | 1 | Left thumb: reignite, and half of the calibration combo |
| Rubber grommet, 6 mm | 1 | Where the wires leave the tube |
| Wood screws for the feet | 4 | Mount to the plywood base |

## Assembly

1. Press the bearings into both cheeks from the inner face.
2. Hub: drop the M4 nut into the trap, thread the M20 grub in from the rim, and press the M4 insert into the socket face.
3. Slide the shaft through the right cheek's bearing, the hub (with an M8 washer either side), and the left bearing. Leave 8 mm proud on the right. Tighten the grub onto the D flat.
4. Bolt the block between the cheeks (4 × M4). Bolt the two posts through with their sleeves.
5. Shoe into the block bore, felt toward the hub. Thumbscrew in from behind. Tighten until the lever holds position under the grip's weight.
6. Glue the magnet into the cap (either pole up), and press the cap onto the shaft end.
7. Measure your AS5600 board and set `board_w`, `board_h`, `chip_stack` and `chip_off` in `params.scad` before printing the bracket. Fix the board in the bracket pocket with zip ties. Tie DIR to GND. Bolt the bracket on.
8. Drill a 6 mm hole in the tube 60 mm above the hub socket and fit the grommet. Run the button wires down the tube and out of it. Fit the tube to the hub and the grip, then set both clamp grubs.

## Wiring (lever 1 = left throttle)

| AS5600 | Pico |
|---|---|
| VCC | 3V3 (pin 36) |
| GND | GND |
| SDA | GP4 |
| SCL | GP5 |
| DIR | GND |

The thumb button goes from GP10 to GND. The other seven buttons (GP11–GP17) can stay unconnected for now. GP17 is the right thumb, and calibration needs both thumbs, so wire a temporary button on GP17 too, or bridge it with a jumper.

## Flash and test

1. Hold BOOTSEL, plug the Pico in, and copy `firmware/build/phaethon_levers.ino.uf2` onto the RPI-RP2 drive.
2. Windows → "Set up USB game controllers" → the Pico appears. Moving the lever moves the X axis.
3. Calibrate: lever at idle, hold both thumb buttons 3 s (the LED blinks fast), sweep the lever to full, tap both thumbs.
4. Open a serial monitor at 115200, leave the lever alone, and send `j`. It must print `PASS` (±2 counts or better).
5. Open the feel lab locally (`web/`, served on localhost). The left lever should now drive the left engine.
