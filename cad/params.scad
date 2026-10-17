// Phaethon lever v1: shared parameters (mm, degrees).
// Frame: X forward, Y along the shaft, Z up. Pivot at [0, 0, pivot_h].
// Lever angle a: 0 = idle (pulled back), throw = full forward.
$fn = 72;

pivot_h     = 70;
throw       = 60;
stop_margin = 2;       // hard stops at -2 and throw + 2

// quadrant cheeks
gap     = 31;          // between cheek inner faces
cheek_t = 12;
cheek_x = 50;          // half-length of the cheek base
foot_w  = 22;
foot_t  = 6;

// 608ZZ: 22 OD / 8 ID / 7 W. Print the coupon first and adjust brg_od.
brg_od  = 22.15;
brg_w   = 7;
lip_d   = 16;          // hole behind the bearing; clears the inner race
shaft_d = 8;           // 8 mm D-shaft, A2 stainless or aluminium near the magnet
bore_d  = 8.2;

// hub and tube socket
hub_w       = 28;
rim_r       = 22;      // friction rim now, detent cam in M4
tube_d      = 16.3;    // 16 mm aluminium tube (or 5/8" dowel)
boss_d      = 30;
boss_flat   = 14;      // boss flattened to |y| <= this, so it prints flat
sock_r0     = 14;
sock_r1     = 50;
sock_bottom = 16;
tube_top    = 205;     // tube runs sock_bottom..tube_top from the pivot

// grip v0
grip_sock = 40;
grip_d    = 34;
grip_len  = 110;       // grip centre lands about 260 mm from the pivot

// bumper posts (also the cheek spacers): M5 bolt in a printed sleeve
post_r = 38;
post_d = 10;

// rear friction block, shoe, thumbscrew
blk_x     = [-46, -27];
blk_z     = [50, 80];
blk_bolts = [[-42, 57], [-31, 57]];
shoe_d    = 10;
shoe_len  = 14;
shoe_gap  = 1;         // felt pad thickness

// magnet cap and AS5600 bracket
cap_d      = 14;
cap_shaft  = 8;        // depth the shaft goes into the cap
cap_stand  = 4;        // keeps the magnet clear of the steel shaft end
mag_d      = 6;
mag_t      = 2.5;
air_gap    = 1.5;      // magnet face to chip face
chip_stack = 3.1;      // chip height + PCB thickness: MEASURE YOUR BOARD
board_w    = 23;       // AS5600 breakout outline: MEASURE YOUR BOARD
board_h    = 23;
chip_off   = [0, 0];   // chip centre relative to board centre: MEASURE
brk_dx     = 20;       // bracket legs at x = +-brk_dx
pocket     = 1.0;

// hardware holes
m3 = 3.4; m4 = 4.4; m5 = 5.4;
m3_insert = 4.0; m4_insert = 5.6;
m4_nut_af = 7; m4_nut_t = 3.2;
m5_nut_af = 8; m5_nut_t = 4;

// derived
inner   = gap / 2;
outer   = inner + cheek_t;
cap_len = cap_shaft + cap_stand + mag_t;
cap_y0  = outer + 1;                         // cap starts 1 mm off the cheek
cap_end = cap_y0 + cap_len;
plate_y = cap_end + air_gap + chip_stack - pocket;
function phi(a) = a - throw / 2;             // arm angle from vertical
// posts sit where the socket boss touches them at the hard stops
post_psi   = (throw / 2 + stop_margin) + asin((boss_d / 2 + post_d / 2) / post_r);
front_post = [post_r * sin(post_psi), pivot_h + post_r * cos(post_psi)];
rear_post  = [-front_post[0], front_post[1]];
