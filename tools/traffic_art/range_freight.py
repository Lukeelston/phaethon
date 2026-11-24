"""A liquid-bulk road tanker and an empty three-pocket aggregate hopper.

Model in metres, nose toward -Z like the Range tractor and boxcar. Both tiers
use the shared vehicle atlas and the same wheel and coupling datum.
"""

import math

import numpy as np
from range_models import bogie, mirror, wheels


def _face(m, points, outward, finish):
    a, b, c = np.asarray(points[:3])
    normal = np.cross(b - a, c - a)
    m.face(points if np.dot(normal, outward) > 0 else points[::-1], finish)


def _tank_shell(m):
    # Elliptical cross-section lowers the centre of gravity; dished heads close
    # each end. The livery is part of the shell rather than offset decal sheets.
    slices = 20 if m.detailed else 8
    profile = [
        (-4.93, 0.28),
        (-4.82, 0.63),
        (-4.59, 0.90),
        (-4.28, 1.0),
        (7.83, 1.0),
        (8.14, 0.90),
        (8.37, 0.63),
        (8.48, 0.28),
    ]
    if not m.detailed:
        profile = [(-4.93, 0.52), (-4.52, 1.0), (8.07, 1.0), (8.48, 0.52)]
    rings = [
        [
            (
                1.29 * r * math.cos(i * math.tau / slices),
                2.49 + 1.17 * r * math.sin(i * math.tau / slices),
                z,
            )
            for i in range(slices)
        ]
        for z, r in profile
    ]
    finishes = []
    for i in range(slices):
        height = math.sin((i + 0.5) * math.tau / slices)
        finishes.append("rail" if -0.72 < height < -0.10 else "alloy")
    m.skin(rings, finishes, smooth=True)


def tanker(m):
    detail = m.detailed
    # A short forward-control cab gives the safety walkway and separate tank
    # tractor neck a different silhouette from the Range box truck.
    m.hull(
        [
            (-8.89, 2.12, 0.96, 1.94, 0.91),
            (-8.66, 2.39, 0.91, 2.34, 0.94),
            (-6.40, 2.40, 0.92, 2.34, 0.94),
            (-6.13, 2.24, 1.00, 2.06, 0.91),
        ],
        "oxide",
    )

    # The glass is a surface of the cab. Opaque bands around its panes form
    # the mullions, door stiles and painted waist, with no floating decals.
    def glazing(base, roof, out, posts):
        if not detail:
            _face(m, [base[0], base[1], roof[1], roof[0]], out, "glass")
            return
        for y0, y1 in zip([0, 0.08, 0.88], [0.08, 0.88, 1]):
            for u0, u1, glass in posts:
                panel = []
                for u, y in [(u0, y0), (u1, y0), (u1, y1), (u0, y1)]:
                    a = (1 - u) * np.asarray(base[0]) + u * np.asarray(base[1])
                    b = (1 - u) * np.asarray(roof[0]) + u * np.asarray(roof[1])
                    panel.append((1 - y) * a + y * b)
                _face(m, panel, out, "glass" if glass and y0 == 0.08 else "oxide")

    base_z, top_z = (-8.73, -6.31), (-8.38, -6.42)
    glazing(
        [(-1.125, 2.28, base_z[0]), (1.125, 2.28, base_z[0])],
        [(-1.057, 3.28, top_z[0]), (1.057, 3.28, top_z[0])],
        (0, 0, -1),
        [
            (0, 0.045, False),
            (0.045, 0.491, True),
            (0.491, 0.509, False),
            (0.509, 0.955, True),
            (0.955, 1, False),
        ],
    )
    for side in (-1, 1):
        glazing(
            [(side * 1.125, 2.28, z) for z in base_z],
            [(side * 1.057, 3.28, z) for z in top_z],
            (side, 0, 0),
            [
                (0, 0.075, False),
                (0.075, 0.68, True),
                (0.68, 0.715, False),
                (0.715, 0.86, True),
                (0.86, 1, False),
            ],
        )
        m.end(False, -8.892, side * 0.80, 1.20, 0.38, 0.17, "white_lens")
    _face(
        m,
        [
            (-1.125, 2.28, base_z[1]),
            (1.125, 2.28, base_z[1]),
            (1.057, 3.28, top_z[1]),
            (-1.057, 3.28, top_z[1]),
        ],
        (0, 0, 1),
        "oxide",
    )
    m.box((0, 3.305, -7.40), (2.17, 0.07, 2.07), "ivory")
    if detail:
        m.box((0, 1.00, -8.84), (2.31, 0.26, 0.22), "graphite")
    m.end(False, -8.892, 0, 1.48, 1.68, 0.43, "grille")
    if detail:
        m.box((0, 0.84, -5.25), (1.53, 0.28, 6.98), "graphite")
    m.box((0, 1.07, 1.69), (1.64, 0.20, 13.41), "graphite")
    _tank_shell(m)
    for z in (-3.66, 1.82, 6.52) if detail else ():
        m.hull(
            [(z - 0.13, 1.73, 1.12, 1.54, 0.96), (z + 0.13, 1.73, 1.12, 1.54, 0.96)],
            "hot",
        )
    for s in (-1, 1):
        m.end(True, 8.466, s * 0.865, 0.85, 0.26, 0.15, "red_lens")
    m.box((0, 0.90, 8.38), (2.34, 0.26, 0.17), "graphite")
    if not detail:
        for z, span in [(-7.59, 0.99), (-4.74, 2.23), (6.67, 2.31)]:
            m.box((0, 0.50, z), (2.40, 1.0, span), "rubber")
        m.box((0, 3.70, 1.7), (0.50, 0.10, 8.60), "roof")
        return
    wheels(m, 1.22, [-7.59, -5.36, -4.12, 6.04, 7.30], 0.51)
    # The catwalk's grating is carried by the tank crown. Three valve hatches
    # on raised necks can be read from a descending aircraft.
    m.box((-0.32, 3.66, 1.74), (0.31, 0.11, 10.65), "vents")
    for z in (-2.60, 1.70, 6.0):
        m.barrel(
            (0.07, 3.61, z),
            (0.07, 3.81, z),
            [(0, 0.32), (0.62, 0.31), (0.71, 0.37), (1, 0.35)],
            "hot",
            12,
            cap="hatch",
        )
    for s in (-1, 1):
        mirror(m, s, 1.10, 2.53, -8.20)
        m.box((s * 1.06, 0.82, -6.89), (0.32, 0.18, 1.05), "vents")
        m.box((s * 1.15, 2.08, -6.82), (0.038, 0.045, 0.24), "alloy")
        for z in (-3.80, -0.1, 3.62, 7.30):
            m.side(s, 1.111, z, 1.035, 0.15, 0.08, "amber")
        m.box((s * 1.075, 1.07, 2.32), (0.07, 0.14, 11.92), "rail")
        m.end(True, 8.466, s * 0.53, 0.846, 0.37, 0.13, "hazard")
    # Discharge manifold beside the walkway, clear of the trailer tyres.
    m.bar((1.07, 1.29, -2.86), (1.07, 1.29, 3.85), 0.075, "alloy", 8)
    for z in (-0.8, 1.3, 3.25):
        m.bar((1.04, 1.29, z), (1.22, 1.29, z), 0.08, "hot", 8)
    # Rear access ladder follows the dished end, with its top curled over the cap.
    for x in (-0.25, 0.25):
        m.bar((x, 1.18, 8.56), (x, 2.91, 8.56), 0.035, "alloy")
        m.bar((x, 2.91, 8.56), (x, 3.62, 7.99), 0.035, "alloy")
    for y, z in [
        (1.36, 8.56),
        (1.69, 8.56),
        (2.02, 8.56),
        (2.35, 8.56),
        (2.68, 8.56),
        (3.05, 8.45),
        (3.35, 8.21),
    ]:
        m.bar((-0.25, y, z), (0.25, y, z), 0.027, "alloy")


def hopper(m):
    # The transverse lip and side sills never close the top. The visible inside
    # slopes lead into three steel gates, mirrored underneath as discharge bays.
    ymax, shoulder = 4.17, 2.15
    ends, throat = 8.32, 5.55
    for s in (-1, 1):
        outside = [
            (s * 1.30, shoulder, -throat),
            (s * 1.30, shoulder, throat),
            (s * 1.53, ymax, ends),
            (s * 1.53, ymax, -ends),
        ]
        inside = [
            (s * 1.24, shoulder, -throat),
            (s * 1.24, shoulder, throat),
            (s * 1.47, ymax, ends),
            (s * 1.47, ymax, -ends),
        ]
        _face(m, outside, (s, 0, 0), "oxide")
        _face(m, inside, (-s, 0, 0), "hot")
        _face(m, [inside[2], inside[3], outside[3], outside[2]], (0, 1, 0), "alloy")
        m.box((s * 1.52, ymax, 0), (0.13, 0.11, 16.80), "oxide")
        m.box((s * 1.39, 1.24, 0), (0.24, 0.31, 17.32), "rail")
    for e in (-1, 1):
        for inset, mat, normal in [
            (0, "oxide", (0, -0.6, e)),
            (0.064, "hot", (0, 0.6, -e)),
        ]:
            _face(
                m,
                [
                    (-1.30 + inset, shoulder, e * (throat - inset)),
                    (1.30 - inset, shoulder, e * (throat - inset)),
                    (1.53 - inset, ymax, e * (ends - inset)),
                    (-1.53 + inset, ymax, e * (ends - inset)),
                ],
                normal,
                mat,
            )
        m.box((0, ymax, e * ends), (3.10, 0.11, 0.13), "oxide")
        m.box((0, 1.15, e * 7.55), (2.92, 0.27, 2.28), "graphite")
        m.box((0, 0.97, e * 8.89), (0.56, 0.31, 0.64), "hot")
        if m.detailed:
            bogie(m, e * 6.29)
        else:
            m.box((0, 0.46, e * 6.29), (2.65, 0.92, 3.42), "graphite")
    for bay in range(3):
        z = (bay - 1) * 3.70
        bottom = 0.81
        top = [
            (-1.3, shoulder, z - 1.85),
            (1.3, shoulder, z - 1.85),
            (1.3, shoulder, z + 1.85),
            (-1.3, shoulder, z + 1.85),
        ]
        low = [
            (-0.73, bottom, z - 0.50),
            (0.73, bottom, z - 0.50),
            (0.73, bottom, z + 0.50),
            (-0.73, bottom, z + 0.50),
        ]
        for i, direction in enumerate(
            [(0, -1, -1), (1, -1, 0), (0, -1, 1), (-1, -1, 0)]
        ):
            nxt = (i + 1) % 4
            panel = [top[i], top[nxt], low[nxt], low[i]]
            _face(m, panel, direction, "oxide")
            # Draw the inward face separately; a real thickness at the lip
            # and folded pocket edges lets the rim and creases catch light.
            lining = [(x * 0.955, y + 0.04, z + (p - z) * 0.996) for x, y, p in panel]
            _face(m, lining, tuple(-v for v in direction), "hot")
        m.box((0, bottom, z), (1.54, 0.14, 1.09), "graphite")
        if m.detailed:
            m.box((0, bottom - 0.095, z), (1.79, 0.095, 0.19), "alloy")
            m.bar((-0.99, 1.06, z + 0.53), (0.99, 1.06, z + 0.53), 0.055, "hot")
    if not m.detailed:
        return
    for s in (-1, 1):
        # Hat-section posts follow the side taper. Varying their lower ends
        # rides up the raised end slope and exposes the bogies in profile.
        for z in [-7.80, -6.45, -5.10, -3.70, -1.85, 0, 1.85, 3.70, 5.10, 6.45, 7.80]:
            ramp = max(0, (abs(z) - throat) / (ends - throat))
            x = 1.30 + 0.23 * ramp
            y = shoulder + (ymax - shoulder) * ramp
            pts = [
                (s * (x + 0.025), y, z - 0.048),
                (s * (x + 0.025), y, z + 0.048),
                (s * 1.565, ymax, z + 0.048),
                (s * 1.565, ymax, z - 0.048),
            ]
            m.fin(pts, (s * 0.085, 0, 0), "oxide")
        # End ladders and diagonals tie the rim to the underframe.
        for e in (-1, 1):
            m.bar((s * 1.40, 1.36, e * 8.28), (s * 1.46, 3.83, e * 7.94), 0.055, "hot")
            m.bar((s * 1.40, 1.36, e * 7.45), (s * 1.43, 2.69, e * 6.33), 0.063, "rail")
        for z in (-8.18, -7.65):
            m.bar((s * 1.58, 1.29, z), (s * 1.58, 4.18, z), 0.032, "alloy")
        for y in [1.50, 1.90, 2.30, 2.70, 3.10, 3.50, 3.90]:
            m.bar((s * 1.58, y, -8.18), (s * 1.58, y, -7.65), 0.025, "alloy")
    for z in (-1.85, 1.85):
        m.bar(
            (-1.24, shoulder + 0.015, z), (1.24, shoulder + 0.015, z), 0.071, "hot", 6
        )
