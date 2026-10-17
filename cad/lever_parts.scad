// Phaethon lever v1: part modules, all in assembly coordinates.
include <params.scad>

// cylinder along +Y from y0 to y1
module yhole(x, z, d, y0, y1) { translate([x, y0, z]) rotate([-90, 0, 0]) cylinder(d = d, h = y1 - y0); }
// cylinder along +X from x0 to x1
module xhole(y, z, d, x0, x1) { translate([x0, y, z]) rotate([0, 90, 0]) cylinder(d = d, h = x1 - x0); }

// ---------- quadrant cheeks ----------
module cheek_profile() {
  hull() {
    translate([0, pivot_h]) circle(r = 28);
    translate(front_post) circle(r = 9);
    translate(rear_post) circle(r = 9);
    translate([-cheek_x, 0]) square([2 * cheek_x, 1]);
  }
}

module cheek_R() {   // the +Y cheek, inner face at y = inner
  difference() {
    union() {
      translate([0, outer, 0]) rotate([90, 0, 0]) linear_extrude(cheek_t) cheek_profile();
      translate([-cheek_x, outer, 0]) cube([2 * cheek_x, foot_w, foot_t]);
    }
    yhole(0, pivot_h, brg_od, inner - 1, inner + brg_w);                  // bearing pocket
    yhole(0, pivot_h, lip_d, inner - 1, outer + 1);                       // shaft clearance
    for (p = [front_post, rear_post]) yhole(p[0], p[1], m5, inner - 1, outer + 1);
    for (b = blk_bolts) yhole(b[0], b[1], m4, inner - 1, outer + 1);
    for (s = [-1, 1]) yhole(s * brk_dx, pivot_h, m3_insert, outer - 6, outer + 1);   // bracket inserts
    for (s = [-1, 1]) translate([s * (cheek_x - 12), outer + foot_w / 2, -1]) cylinder(d = m5, h = foot_t + 2);
  }
}
module cheek_L() { mirror([0, 1, 0]) cheek_R(); }

module posts() { for (p = [front_post, rear_post]) difference() {
  yhole(p[0], p[1], post_d, -inner, inner);
  yhole(p[0], p[1], m5, -inner - 1, inner + 1);
} }

// ---------- hub: rim disc plus radial tube socket, built along local +Z ----------
module hub_local() {
  difference() {
    union() {
      rotate([90, 0, 0]) cylinder(r = rim_r, h = hub_w, center = true);
      intersection() {
        translate([0, 0, sock_r0]) cylinder(d = boss_d, h = sock_r1 - sock_r0);
        translate([-boss_d, -boss_flat, 0]) cube([2 * boss_d, 2 * boss_flat, sock_r1 + 1]);
      }
    }
    rotate([90, 0, 0]) cylinder(d = bore_d, h = hub_w + 2, center = true);
    translate([0, 0, sock_bottom]) cylinder(d = tube_d, h = sock_r1);
    // grub screw toward local +X (always the front, far from the rear shoe), M4 nut trap open to -Y
    rotate([0, 90, 0]) cylinder(d = m4, h = rim_r + 1);
    translate([9, -hub_w / 2 - 1, -(m4_nut_af + 0.4) / 2]) cube([m4_nut_t + 0.3, hub_w / 2 + 5.2, m4_nut_af + 0.4]);
    // tube clamp: M4 insert in the front of the socket
    translate([0, 0, 42]) rotate([0, 90, 0]) cylinder(d = m4_insert, h = boss_d);
  }
}
module at_lever(a) { translate([0, 0, pivot_h]) rotate([0, phi(a), 0]) children(); }
module hub(a) { at_lever(a) hub_local(); }
module tube(a) { at_lever(a) translate([0, 0, sock_bottom]) cylinder(d = 16, h = tube_top - sock_bottom); }

// ---------- rear friction block and shoe ----------
module block() {
  difference() {
    translate([blk_x[0], -inner, blk_z[0]]) cube([blk_x[1] - blk_x[0], gap, blk_z[1] - blk_z[0]]);
    xhole(0, pivot_h, shoe_d + 0.4, -40, blk_x[1] + 1);                  // shoe bore
    xhole(0, pivot_h, m5, blk_x[0] - 1, -39);                            // thumbscrew
    translate([-44.6, -(m5_nut_af + 0.4) / 2, pivot_h - 5])              // M5 nut slot, open on top
      cube([m5_nut_t + 0.3, m5_nut_af + 0.4, blk_z[1] - pivot_h + 6]);
    for (b = blk_bolts) for (s = [-1, 1])
      translate([b[0], s * (inner + 1), b[1]]) rotate([s > 0 ? 90 : -90, 0, 0]) cylinder(d = m4_insert, h = 9);
  }
}
module shoe() {
  difference() {
    xhole(0, pivot_h, shoe_d, -(rim_r + shoe_gap + shoe_len), -(rim_r + shoe_gap));
    translate([0, 0, pivot_h]) rotate([90, 0, 0]) cylinder(r = rim_r + shoe_gap, h = 20, center = true);
  }
}

// ---------- magnet cap (shaft end) and AS5600 bracket ----------
module magnet_cap_local() {   // bore down, magnet pocket on top
  difference() {
    cylinder(d = cap_d, h = cap_len);
    translate([0, 0, -1]) cylinder(d = shaft_d + 0.1, h = cap_shaft + 1);
    translate([0, 0, cap_len - mag_t]) cylinder(d = mag_d + 0.15, h = mag_t + 1);
  }
}
module magnet_cap() { translate([0, cap_y0, pivot_h]) rotate([-90, 0, 0]) magnet_cap_local(); }

module bracket() {
  difference() {
    union() {
      translate([-brk_dx - 6, plate_y, pivot_h - 16]) cube([2 * brk_dx + 12, 3, 32]);
      for (s = [-1, 1]) translate([s * brk_dx - 4.5, outer, pivot_h - 4.5]) cube([9, plate_y - outer + 0.01, 9]);
    }
    // board pocket on the magnet side, centred so the chip sits on the shaft axis
    translate([-board_w / 2 - 0.2 - chip_off[0], plate_y - 0.01, pivot_h - board_h / 2 - 0.2 - chip_off[1]])
      cube([board_w + 0.4, pocket, board_h + 0.4]);
    for (s = [-1, 1]) yhole(s * brk_dx, pivot_h, m3, outer - 1, plate_y + 4);              // screws to the cheek
    for (s = [-1, 1]) translate([s * (board_w / 2 + 1.5) - 1, plate_y - 1, pivot_h - 13]) cube([2, 5, 4]);   // zip-tie slots
  }
}

// ---------- grip v0 (built upright, socket at the bottom) ----------
module grip() {
  difference() {
    union() {
      cylinder(d = boss_d, h = grip_sock - 6);
      translate([0, 0, grip_sock - 6]) cylinder(d1 = boss_d, d2 = grip_d, h = 6);
      translate([0, 0, grip_sock]) cylinder(d = grip_d, h = grip_len - 10);
      translate([0, 0, grip_sock + grip_len - 10]) scale([1, 1, 0.6]) sphere(d = grip_d);
    }
    translate([0, 0, -1]) cylinder(d = tube_d, h = grip_sock + 1);
    cylinder(d = 8, h = grip_sock + grip_len);                                   // wire channel
    translate([0, 0, grip_sock + grip_len - 14]) cylinder(d = 12.2, h = 30);       // 12 mm thumb button
    translate([0, 0, grip_sock / 2]) rotate([0, 90, 0]) cylinder(d = m4_insert, h = boss_d);   // tube clamp
  }
}
module grip_placed(a) { at_lever(a) translate([0, 0, tube_top - grip_sock]) grip(); }

// ---------- 608 fit coupon: print this first ----------
module coupon() {
  difference() {
    translate([-15, -15, 0]) cube([30, 30, brg_w + 2]);
    translate([0, 0, 2]) cylinder(d = brg_od, h = brg_w + 1);
    translate([0, 0, -1]) cylinder(d = lip_d, h = 5);
  }
}
