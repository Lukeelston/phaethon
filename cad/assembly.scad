// Lever v1 assembly. -D lever_angle=N, -D mode=0 (full) | 1 (clash: moving AND fixed)
include <lever_parts.scad>
lever_angle = 0;
mode = 0;

module moving(a) { hub(a); tube(a); grip_placed(a); magnet_cap(); }
module fixed() { cheek_R(); cheek_L(); posts(); block(); bracket(); }

if (mode == 0) {
  color("silver") fixed();
  color("darkorange") moving(lever_angle);
  color("dimgray") shoe();
}
if (mode == 1) intersection() { moving(lever_angle); fixed(); }
