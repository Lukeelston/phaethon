// Print-oriented export of one part. Usage: openscad -o out.stl -D part=N parts.scad
include <lever_parts.scad>
part = 0;
//  1 cheek_R   2 cheek_L   3 hub   4 block   5 shoe   6 post sleeve
//  7 magnet cap   8 bracket   9 grip   10 bearing coupon
if (part == 1) translate([0, 0, -inner]) rotate([90, 0, 0]) cheek_R();          // inner face down
if (part == 2) translate([0, 0, -inner]) rotate([-90, 0, 0]) cheek_L();
if (part == 3) translate([0, 0, hub_w / 2]) rotate([90, 0, 0]) hub_local();      // side face down
if (part == 4) translate([0, 0, -blk_x[0]]) rotate([0, -90, 0]) block();         // rear face down
if (part == 5) translate([0, 0, rim_r + shoe_gap + shoe_len]) rotate([0, -90, 0]) translate([0, 0, -pivot_h]) shoe();
if (part == 6) difference() { cylinder(d = post_d, h = gap); translate([0, 0, -1]) cylinder(d = m5, h = gap + 2); }
if (part == 7) magnet_cap_local();
if (part == 8) translate([0, 0, plate_y + 3]) rotate([-90, 0, 0]) translate([0, 0, -pivot_h]) bracket();   // back face down
if (part == 9) grip();
if (part == 10) coupon();
