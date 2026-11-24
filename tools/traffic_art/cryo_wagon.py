"""Network vacuum-jacketed cryogenic freight wagon. Forward is -Z."""

import math

from mesh import unit


TANK_Y = 2.60
RADIUS_X = 2.06
RADIUS_Y = 1.68
SHOULDER = 5.45
HEAD_DEPTH = 1.28


def jacket(m):
    # A spun elliptical head at either end of a cylindrical insulation jacket.
    # The slope at the shoulder is zero, so its normal matches the long barrel.
    sides = 20 if m.detailed else 10
    phis = (0.0, 0.48, 0.92, 1.31) if m.detailed else (0.0, 1.03)
    rows = []

    def head_rows(end):
        angles = reversed(phis) if end < 0 else phis
        for phi in angles:
            rows.append((
                end * (SHOULDER + HEAD_DEPTH * math.sin(phi)),
                math.cos(phi), end * math.sin(phi) / HEAD_DEPTH, "ivory",
            ))

    head_rows(-1)
    # Service identifier and the gold edge stripe are bands in the jacket finish.
    stripe = [(-3.43, "rail")]
    if m.detailed:
        stripe.append((-2.37, "oxide"))
    for z, finish in stripe + [(-2.20, "ivory")]:
        rows.append((z, 1.0, 0.0, finish))
    head_rows(1)

    rings = []
    for z, scale, nz, _ in rows:
        ring = []
        for i in range(sides):
            theta = i * math.tau / sides
            c, s = math.cos(theta), math.sin(theta)
            p = (scale * RADIUS_X * c, TANK_Y + scale * RADIUS_Y * s, z)
            n = unit((scale * c / RADIUS_X, scale * s / RADIUS_Y, nz))
            ring.append((p, n))
        rings.append(ring)
    for row, (lower, upper) in enumerate(zip(rings, rings[1:])):
        for i in range(sides):
            j = (i + 1) % sides
            corners = [lower[i], lower[j], upper[j], upper[i]]
            left, right = i / sides, (i + 1) / sides
            uv = [(left, 1), (right, 1), (right, 0), (left, 0)]
            m.face([p for p, _ in corners], rows[row][3], uv, [n for _, n in corners])
    for sign, ring in [(-1, rings[0]), (1, rings[-1])]:
        tip = (0.0, TANK_Y, sign * (SHOULDER + HEAD_DEPTH))
        for i in range(sides):
            j = (i + 1) % sides
            a, b = (i, j) if sign > 0 else (j, i)
            m.face([ring[a][0], ring[b][0], tip], "ivory",
                   normals=[ring[a][1], ring[b][1], (0, 0, sign)])


def saddle(m, z):
    # The seat follows the tank's lower quadrant. Its relieved side webs leave
    # a strip of daylight over the runners at each side.
    for sign in (-1, 1):
        x = sign * 2.17
        m.fin([
            (sign * 0.12, 0.67, z), (x, 0.67, z), (x, 1.54, z),
            (sign * 1.69, 1.68, z), (sign * 1.17, 1.20, z),
            (sign * 0.51, 0.96, z),
        ], (0, 0, 0.56), "rail")
        m.side(sign, 2.176, z, 1.06, 0.38, 0.22, "alloy")


def far_frame(m, sign):
    z = sign * 8.12
    m.box((0, 0.91, z), (5.15, .75, .42), "graphite")
    m.box((0, .51, sign * 8.47), (1.18, .44, .58), "graphite")
    # At range the front and rear faces carry this slim guard. A broad side
    # silhouette reads through the spaces between the vessel and end deck.
    for face in (-1, 1):
        face_z = z + face * .082
        for x in (-2.35, 2.35):
            m.end(face > 0, face_z, x, 1.20, .17, 2.49, "alloy")
        m.end(face > 0, face_z, 0, 3.69, 4.87, .17, "alloy")
    for side in (-1, 1):
        m.side(side, 2.435, z, 1.20, .164, 2.66, "alloy")
        m.end(sign > 0, sign * 8.339, 2.10 * side, 1.075, .60, .23,
              "amber" if sign > 0 else "white_lens")


def end_frame(m, sign):
    z = sign * 8.12
    # Bolsters carry the traction sockets. Lamp lenses face away from
    # the train; their spacing matches the separate distant lamp pair.
    m.box((0, 0.86, z), (5.15, 0.64, 0.42), "graphite")
    m.box((0, 0.51, sign * 8.47), (1.18, 0.44, 0.58), "graphite")
    for side in (-1, 1):
        x = 2.10 * side
        m.box((x, 1.17, z), (0.76, 0.38, 0.39), "hot")
        m.end(sign > 0, sign * 8.339, x, 1.075, 0.60, 0.23,
              "amber" if sign > 0 else "white_lens")
    # The chamfered corners on the portal keep the curved heads visible.
    pts = [(-2.38, 1.12), (-2.38, 3.29), (-1.91, 3.86),
           (1.91, 3.86), (2.38, 3.29), (2.38, 1.12)]
    # A single folded section, with the same four corners at each bend.
    rows = []
    for i, (x, y) in enumerate(pts):
        x1, y1 = pts[max(i-1, 0)]
        x2, y2 = pts[min(i+1, len(pts)-1)]
        dx, dy = unit((y2-y1, x1-x2)) * .093
        rows.append([(x-dx, y-dy, z-.085), (x-dx, y-dy, z+.085),
                     (x+dx, y+dy, z+.085), (x+dx, y+dy, z-.085)])
    m.skin(rows, "alloy")


def valve_cabinet(m):
    # Forward of the rear bolster, a transverse cabinet opens on the tail.
    # Its recessed low-pressure manifold is operable beside the closed access door.
    m.box((0.00, 0.94, 7.37), (3.67, 0.25, 1.53), "graphite")
    m.box((0.00, 1.90, 6.97), (3.53, 1.80, 0.66), "rail")
    m.box((-0.80, 1.90, 7.46), (1.93, 1.80, 0.38), "oxide")
    m.box((0.00, 2.84, 7.22), (3.67, 0.14, 1.24), "rail")
    m.end(True, 7.658, -0.80, 1.15, 1.62, 1.46, "service")
    m.box((1.72, 1.92, 7.44), (0.13, 1.74, 0.38), "rail")
    m.bar((0.31, 1.62, 7.46), (1.58, 1.62, 7.46), 0.12, "alloy", 6)
    for x in (0.58, 1.36):
        m.bar((x, 1.63, 7.46), (x, 2.26, 7.46), 0.089, "alloy", 6)
        m.box((x, 2.23, 7.46), (.38, .085, .11), "oxide")
        m.barrel((x, 1.63, 7.46), (x, 1.63, 7.76),
                 [(0, .12), (.60, .19), (1, .19)],
                 ["hot", "alloy"], 8, cap="hub")
    for x in (.46, 1.48):
        m.bar((x, 1.55, 7.45), (x, 1.02, 7.45), 0.10, "hot", 6)


def cryotank(m):
    jacket(m)
    if not m.detailed:
        for sign in (-1, 1):
            far_frame(m, sign)
            m.box((sign * 2.12, .59, 0), (.85, .49, 16.20), "paint")
            m.box((0, .99, sign * 3.92), (4.36, .78, .78), "rail")
        m.box((0, 1.92, 7.25), (3.67, 1.89, 1.24), "rail")
        m.end(True, 7.877, -.80, 1.08, 1.81, 1.67, "oxide")
        return

    # Two pressure-relief heads on the insulated cold-service bonnet.
    m.barrel((0, 4.18, -1.12), (0, 4.37, -1.12),
             [(0, .56), (1, .48)], "rail", 12, cap="alloy")
    for x, height in [(-.21, 4.60), (.20, 4.52)]:
        m.barrel((x, 4.36, -1.12), (x, height, -1.12),
                 [(0, .108), (.60, .108), (1, .145)],
                 ["alloy", "oxide"], 7, cap="oxide")
    for side in (-1, 1):
        x = side * 2.12
        m.box((x, 0.62, 0), (0.65, 0.37, 16.20), "paint")
        for z in (-4.71, 4.71):
            m.fin([(x, .42, z-1.77), (x, .24, z-1.33), (x, .24, z+1.29),
                   (x, .42, z+1.75), (x, .72, z+1.55), (x, .81, z+.94),
                   (x, .81, z-1.1), (x, .72, z-1.57)],
                  (1.01, 0, 0), "graphite")
            m.side(side, 2.628, z, .412, 2.22, .14, "grille")
        # The mounting rail and coolant return are fixed to the lower frame.
        m.bar((side * 2.12, 0.94, -4.14), (side * 2.12, 0.94, 4.14), .078, "alloy", 7)
        m.box((side * 2.06, 2.60, 1.88), (.075, .80, 2.00), "rail")
        m.side(side, 2.102, 1.88, 2.22, 1.94, .76, "freight_id")
        for z in (-6.56, 6.56):
            m.side(side, 2.451, z, .54, .72, .16, "hazard")
    for z in (-3.92, 3.92):
        m.box((0, .62, z), (4.43, .34, .72), "graphite")
        saddle(m, z)
    for sign in (-1, 1):
        end_frame(m, sign)
    valve_cabinet(m)
