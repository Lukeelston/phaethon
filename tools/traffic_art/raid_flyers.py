"""Bake the two Network raid flyers. Coordinates are in metres, nose toward -Z.

Run python tools/traffic_art/raid_flyers.py. Both use the existing traffic atlas.
The gunship body, turret yoke and cradle are separate single-surface rigid parts.
"""
from math import cos, sin, tau
from pathlib import Path

from mesh import Model, write_glb

DEST = Path(__file__).resolve().parents[2] / "godot/art/traffic"
GUNSHIP_NODES = [
    {"name": "Body", "mesh": 0},
    {"name": "TurretPivot", "mesh": 1, "translation": [0, -1.54, -3.14], "children": [2]},
    {"name": "Cradle", "mesh": 2, "translation": [0, -0.74, 0], "children": [3]},
    {"name": "Muzzle", "translation": [0, -0.06, -2.95]},
]


def shell(m, sections, finish):
    """Loft a faceted casting through (Z, center X, center Y, half-width, half-height)."""
    rings = []
    for z, x, y, w, h in sections:
        ring = [(-0.72, -1), (0.72, -1), (1, -0.45), (1, 0.29),
                (0.70, 0.96), (0, 1.13), (-0.70, 0.96), (-1, 0.29), (-1, -0.45)]
        rings.append([(x + a * w, y + b * h, z) for a, b in ring])
    m.skin(rings, finish)


def mirror_sections(sections, side):
    return [(z, side * x, y, w, h) for z, x, y, w, h in sections]


def roundel(m, center, tip, radius, bezel, glass, n=14):
    # A recessed luminous optic with a distinct metal bezel and black gasket.
    m.barrel(center, tip, [(0, radius * 0.85), (0.20, radius), (0.53, radius),
                           (0.63, radius * 0.83), (0.68, radius * 0.70), (1, radius * 0.63)],
             [bezel, bezel, "alloy", "graphite", glass], n, glass)


def drone(m):
    # A needle-shaped suspended sensor body. Forward-swept pincers enclose
    # negative space around its cyclopean eye, even head-on or from underneath.
    shell(m, [(-1.31, 0, -0.02, 0.49, 0.36), (-0.81, 0, 0.02, 0.76, 0.51),
              (0.25, 0, 0.10, 0.81, 0.58), (0.96, 0, 0.12, 0.60, 0.42),
              (1.87, 0, 0.08, 0.18, 0.17)], "graphite")
    shell(m, [(-1.16, 0, 0.30, 0.39, 0.10), (-0.62, 0, 0.44, 0.65, 0.12),
              (0.24, 0, 0.57, 0.62, 0.13), (1.34, 0, 0.26, 0.21, 0.08)], "rail")
    roundel(m, (0, -0.03, -1.16), (0, -0.17, -1.76), 0.45, "hot", "red_lens")
    # Suspended pupil: the larger red lens now reads as a ring around the
    # darker iris, with a smaller luminous aperture at its center.
    m.barrel((0, -0.166, -1.725), (0, -0.187, -1.81),
             [(0, 0.19), (0.38, 0.19), (0.72, 0.155), (1, 0.109)],
             ["hot", "graphite", "glass"], 12, "red_lens")
    # Each blade is a shell with a narrowed, rolled leading point and an
    # exposed bronze knuckle. Two small red facets remain visible from behind.
    blade = [(-2.31, 1.95, -0.30, 0.05, 0.045), (-1.10, 2.52, -0.03, 0.28, 0.17),
             (-0.35, 2.63, 0.13, 0.34, 0.19), (0.38, 2.32, 0.32, 0.40, 0.20),
             (1.00, 1.51, 0.43, 0.30, 0.16), (1.54, 0.52, 0.22, 0.18, 0.10)]
    for side in (-1, 1):
        shell(m, mirror_sections(blade, side), "rail")
        # Light catches the lower cutting edge where the shell tapers into
        # its point. These two faces follow the stations rather than float.
        m.fin([(side * 1.95, -0.335, -2.25), (side * 2.45, -0.20, -1.13),
               (side * 2.66, -0.13, -0.70), (side * 2.31, -0.20, -1.14)],
              (0, 0.021, 0), "alloy")
        shell(m, mirror_sections([(-0.78, 2.62, 0.035, 0.265, 0.20),
                                  (-0.58, 2.66, 0.09, 0.30, 0.218)], side), "hot")
        m.fin([(0.43 * side, 0.08, 0.0), (1.55 * side, 0.27, 0.38),
               (2.0 * side, 0.32, 0.53), (1.36 * side, 0.22, 0.96),
               (0.40 * side, 0.05, 0.59)], (0, 0.17, 0), "hot")
        shell(m, mirror_sections([(0.25, 0.58, -0.19, 0.18, 0.14),
                                  (0.85, 0.77, -0.14, 0.22, 0.18),
                                  (1.64, 0.95, -0.11, 0.15, 0.12)], side), "graphite")
        m.end(True, 1.643, side * 0.95, -0.168, 0.21, 0.11, "red_lens")


def lift_ring(m, x, z):
    # Oval annular lift ducts. The underside has a real lip, recessed vanes
    # and a luminous inner annulus; between the vanes one can see the sky.
    count = 24
    profile = [(-0.32, 0.90), (-0.08, 1.00), (1.26, 1.00), (1.52, 0.92),
               (1.52, 0.74), (1.20, 0.68), (0.16, 0.68), (-0.14, 0.73), (-0.32, 0.80)]
    bands = ["hot", "rail", "alloy", "graphite", "hot", "vents", "drive", "alloy", "hot"]
    # Positive angle heads from +X to -Z; this transitions from the outside
    # bottom to outside top, over the lip and back down the inside.
    def point(radius, theta, height):
        return (x + 2.28 * radius * cos(theta), height, z - 3.38 * radius * sin(theta))

    for i, (y, radius) in enumerate(profile):
        y2, next_radius = profile[(i + 1) % len(profile)]
        for k in range(count):
            a, b = tau * k / count, tau * (k + 1) / count
            finish = bands[i]
            if i == 1 and k % 6 == 0:
                finish = "hot"
            elif i == 1 and k % 6 == 5:
                finish = "vents"
            m.face([point(radius, a, y), point(radius, b, y),
                    point(next_radius, b, y2), point(next_radius, a, y2)], finish)
    # Four divided exhaust shutters cast a dark rhythm across the mouth.
    # Their return over the outer casing gives each lift drive a fastener band.
    for k in range(4):
        a = (k + 0.35) * tau / 4
        corner = [point(0.72, a - 0.10, -0.15), point(0.935, a - 0.07, -0.255),
                  point(0.935, a + 0.05, -0.255), point(0.72, a + 0.08, -0.15)]
        m.fin(corner, (0, 0.15, 0), "graphite")
        m.face([point(1.008, a - 0.04, 0.01), point(1.008, a + 0.04, 0.01),
                point(1.008, a + 0.04, 0.87), point(1.008, a - 0.04, 0.87)], "alloy")
    # Three radial vanes are broad enough to read in the lower opening.
    for k in range(3):
        a = tau * k / 3 + 0.17
        points = [point(0.19, a - 0.28, 0.18), point(0.68, a + 0.05, 0.44),
                  point(0.68, a + 0.35, 0.48), point(0.19, a + 0.30, 0.20)]
        m.fin(points, (0, 0.13, 0), "graphite")
    m.barrel((x, -0.10, z), (x, 0.73, z), [(0, 0.38), (0.33, 0.61), (1, 0.36)], "hot", 10)


def gunship_body(m):
    # An armored command spine hangs below a quartet of ring drives. The
    # deep stepped bow, bridge slit and copper deck panels are a separate
    # silhouette from the spindly, open-jawed drones that accompany it.
    shell(m, [(-9.5, 0, -0.04, 0.90, 0.64), (-8.1, 0, 0.22, 2.04, 1.14),
              (-5.0, 0, 0.21, 2.96, 1.47), (1.7, 0, 0.16, 3.08, 1.54),
              (5.1, 0, 0.29, 2.83, 1.35), (8.4, 0, 0.57, 1.64, 1.08),
              (9.05, 0, 0.65, 1.39, 0.74)], "graphite")
    shell(m, [(-8.65, 0, 0.81, 1.29, 0.16), (-5.05, 0, 1.58, 2.51, 0.25),
              (-1.46, 0, 1.69, 2.52, 0.22), (2.8, 0, 1.61, 2.06, 0.19)], "rail")
    shell(m, [(-3.88, 0, 1.85, 1.33, 0.12), (-2.35, 0, 2.12, 1.78, 0.39),
              (0.75, 0, 2.13, 1.61, 0.39), (3.94, 0, 1.69, 0.85, 0.18)], "glass")
    shell(m, [(-2.67, 0, 2.41, 1.58, 0.13), (-1.38, 0, 2.58, 1.77, 0.15),
              (1.17, 0, 2.47, 1.58, 0.22), (3.16, 0, 1.99, 0.96, 0.12)], "hot")
    # Service tunnel beneath the pressure hull; four vent slats are set
    # into the bottom face. The ring bearing interrupts it farther forward.
    shell(m, [(-1.53, 0, -1.28, 0.63, 0.12), (-0.76, 0, -1.39, 0.83, 0.19),
              (3.70, 0, -1.22, 0.80, 0.22), (5.66, 0, -0.94, 0.48, 0.12)], "hot")
    for z in (0.0, 0.84, 1.68, 2.52):
        y = -1.57 + 0.032 * (z + 0.76)
        m.fin([(-0.54, y, z), (0.54, y, z), (0.49, y + 0.013, z + 0.43),
               (-0.49, y + 0.013, z + 0.43)], (0, 0.09, 0), "vents")
    for side in (-1, 1):
        # Three overlapping belly scutes on each cheek, visibly below the
        # pressure hull from the pilot's road-level point of view.
        for z, y, rise in ((-6.8, -1.00, -0.20), (-1.15, -1.34, 0.01), (1.11, -1.35, 0.10)):
            m.fin([(side * 1.12, y, z), (side * 1.81, y + 0.04, z - 0.39),
                   (side * 2.48, y + 0.15 + rise, z + 1.20),
                   (side * 2.13, y + 0.06 + rise, z + 1.69),
                   (side * 1.16, y - 0.04 + rise, z + 1.48)], (0, 0.17, 0), "rail")
        for center_x, center_z in ((5.6, -2.88), (7.38, 4.42)):
            lift_ring(m, side * center_x, center_z)
        # Broad lift-arm box spars heel into the continuous cheek armor.
        for z, x in ((-2.67, 4.09), (4.48, 5.81)):
            m.fin([(side * 1.73, 0.73, z - 1.15), (side * x, 0.52, z - 0.89),
                   (side * (x + 0.84), 0.43, z + 0.98), (side * 2.09, 0.61, z + 1.74)],
                  (0, 0.66, 0), "hot")
        cheek = [(-8.64, 1.81, -0.05, 0.36, 0.43), (-7.45, 2.34, 0.11, 0.75, 0.73),
                 (-4.12, 2.91, 0.24, 0.85, 0.83), (-1.36, 2.96, 0.26, 0.73, 0.77),
                 (0.88, 2.74, 0.25, 0.55, 0.59)]
        shell(m, mirror_sections(cheek, side), "rail")
        # A narrow segmented red cheek lamp survives on the shadowed front.
        m.end(False, -8.646, side * 1.81, -0.198, 0.50, 0.22, "red_lens")
        for z in (-6.65, -5.98, -5.31):
            x = 2.12 + (z + 6.65) * 0.21
            m.fin([(side * x, -0.76, z - 0.15), (side * (x + 0.67), -0.38, z - 0.12),
                   (side * (x + 0.72), -0.33, z + 0.08), (side * x, -0.74, z + 0.09)],
                  (0.04, -0.04, 0), "hot")
        # Split stern and canted dorsal fins identify the heavy from above.
        tail = [(2.24, 2.55, 0.69, 0.64, 0.38), (5.89, 3.29, 0.92, 0.93, 0.79),
                (8.5, 3.69, 1.14, 0.67, 0.63), (10.15, 3.72, 1.28, 0.53, 0.53)]
        shell(m, mirror_sections(tail, side), "rail")
        roundel(m, (side * 3.72, 1.28, 9.89), (side * 3.72, 1.28, 10.36),
                0.46, "hot", "drive")
        m.fin([(side * 3.38, 1.66, 4.81), (side * 4.51, 3.53, 7.04),
               (side * 4.66, 3.64, 8.99), (side * 3.65, 1.69, 9.29)],
              (0.17, 0, 0), "graphite")
    # Fixed turntable belongs to the airframe, concentric with the yoke.
    m.barrel((0, -1.12, -3.14), (0, -1.54, -3.14),
             [(0, 1.20), (0.30, 1.32), (0.67, 1.32), (1, 1.13)], "hot", 16)


def turret_yoke(m):
    m.barrel((0, 0.01, 0), (0, -0.42, 0), [(0, 1.04), (0.40, 1.08), (1, 0.93)], "graphite", 14)
    for side in (-1, 1):
        shell(m, mirror_sections([(-0.85, 0.80, -0.55, 0.18, 0.31),
                                  (-0.30, 0.87, -0.66, 0.21, 0.49),
                                  (0.68, 0.85, -0.52, 0.19, 0.37)], side), "hot")
        m.barrel((side * 0.93, -0.74, 0), (side * 1.11, -0.74, 0),
                 [(0, 0.32), (0.74, 0.32), (1, 0.26)], "alloy", 10)


def turret_cradle(m):
    shell(m, [(-1.08, 0, 0, 0.59, 0.34), (-0.75, 0, 0, 0.72, 0.46),
              (0.52, 0, 0.02, 0.71, 0.42), (0.97, 0, 0.06, 0.49, 0.29)], "rail")
    for side in (-1, 1):
        x = side * 0.337
        m.barrel((x, -0.06, -0.85), (x, -0.06, -2.94),
                 [(0, 0.22), (0.30, 0.22), (0.34, 0.17), (0.70, 0.17),
                  (0.74, 0.22), (0.97, 0.22), (1, 0.18)],
                 ["graphite", "alloy", "hot", "alloy", "graphite", "hot"], 8, "grille")
    roundel(m, (0, 0.16, -1.01), (0, 0.17, -1.23), 0.15, "graphite", "red_lens", 8)


if __name__ == "__main__":
    for name, sections in (("raid_drone", [("Drone", drone)]),
                           ("raid_gunship", [("Body", gunship_body), ("TurretPivot", turret_yoke),
                                            ("Cradle", turret_cradle)])):
        models = []
        for part, builder in sections:
            model = Model(True)
            builder(model)
            models.append((part, model))
        write_glb(DEST / (name + ".glb"), models, False,
                  nodes=GUNSHIP_NODES if name == "raid_gunship" else None)
        print(name, " ".join(f"{part}={len(model.indices) // 3}" for part, model in models))
