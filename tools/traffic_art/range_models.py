"""Ground traffic and a twin-engine civil airliner for the 100-mile test range."""

import math
import numpy as np


def wheels(m, width, z_positions, radius, rail=False):
    spokes = 12 if m.detailed else 7
    for z in z_positions:
        for s in (-1, 1):
            a = (s * (width - 0.32 * radius), radius, z)
            b = (s * width, radius, z)
            m.barrel(
                a,
                b,
                [
                    (0, radius * 0.91),
                    (0.18, radius),
                    (0.84, radius),
                    (1, radius * 0.88),
                ],
                "graphite" if rail else "rubber",
                spokes,
                cap="alloy" if rail else "rubber",
            )
            if m.detailed:
                m.barrel(
                    b,
                    (s * (width + radius * 0.045), radius, z),
                    [(0, radius * 0.62), (1, radius * 0.57)],
                    "alloy",
                    spokes,
                    cap="hub",
                )


def mirror(m, s, x, y, z):
    m.bar((s * x, y - 0.18, z + 0.18), (s * (x + 0.26), y, z), 0.04, "alloy", 5)
    m.box((s * (x + 0.29), y + 0.06, z), (0.14, 0.33, 0.12), "graphite")


def truck(m):
    if not m.detailed:
        m.box((0, 2.53, 1.83), (2.56, 3.34, 13.40), "ivory")
        m.hull(
            [
                (-9.27, 2.12, 0.62, 1.72, 0.89),
                (-8.09, 2.41, 0.60, 2.03, 0.9),
                (-7.55, 2.44, 0.60, 3.30, 0.87),
                (-5.93, 2.44, 0.63, 3.56, 0.9),
            ],
            "rail",
        )
        for s in (-1, 1):
            m.side(s, 1.286, 1.83, 1.05, 13.29, 2.94, "band")
        for z, l in [(-8.13, 1.04), (-4.65, 2.27), (6.50, 2.32)]:
            m.box((0, 0.52, z), (2.38, 1.0, l), "rubber")
        return
    m.box((0, 0.73, 0.0), (1.82, 0.37, 17.14), "graphite")
    m.hull(
        [
            (-9.27, 1.83, 0.65, 1.47, 0.91),
            (-8.88, 2.37, 0.57, 2.12, 0.89),
            (-8.08, 2.44, 0.58, 2.28, 0.93),
            (-7.72, 2.48, 0.58, 3.30, 0.87),
            (-6.65, 2.49, 0.61, 3.42, 0.9),
            (-5.93, 2.44, 0.67, 3.47, 0.92),
        ],
        "rail",
    )
    # Glazing follows the raked front and sides of the actual cab shell.
    for s in (-1, 1):
        m.fin(
            [
                (s * 0.045, 2.24, -8.105),
                (s * 0.99, 2.24, -8.105),
                (s * 0.902, 3.19, -7.79),
                (s * 0.044, 3.19, -7.79),
            ],
            (0, 0.016, -0.025),
            "glass",
        )
        m.fin(
            [
                (s * 1.224, 2.26, -7.94),
                (s * 1.235, 2.26, -6.72),
                (s * 1.110, 3.13, -6.72),
                (s * 1.102, 3.13, -7.67),
            ],
            (s * 0.052, 0, 0),
            "glass",
        )
        m.bar((s * 0.78, 2.29, -8.125), (s * 0.31, 2.38, -8.100), 0.024, "graphite")
        m.side(s, 1.253, -6.75, 2.0, 0.27, 0.066, "alloy")
        m.box((s * 1.16, 2.86, -6.06), (0.18, 0.12, 0.32), "amber")
        m.barrel(
            (s * 1.14, 1.06, -5.89),
            (s * 1.14, 3.88, -5.89),
            [(0, 0.10), (0.71, 0.14), (0.80, 0.10), (1, 0.10)],
            "hot",
            10,
            cap="graphite",
        )
    m.box((0, 1.22, -8.983), (2.43, 0.24, 0.12), "alloy")
    m.end(False, -9.285, 0, 1.0, 1.16, 0.42, "vents")
    m.box((0, 2.53, 1.83), (2.56, 3.34, 13.40), "ivory")
    for s in (-1, 1):
        m.side(s, 1.287, 1.82, 1.05, 13.29, 2.94, "band")
        m.box((s * 1.28, 4.21, 1.83), (0.07, 0.10, 13.46), "alloy")
        m.end(False, -9.28, s * 0.70, 0.99, 0.44, 0.19, "white_lens")
        if m.detailed:
            for z in (-4.59, -2.01, 0.58, 3.14, 5.76, 8.34):
                m.box((s * 1.29, 2.57, z), (0.031, 3.08, 0.042), "alloy")
                m.side(s, 1.311, z, 1.02, 0.13, 0.071, "amber")
            m.barrel(
                (s * 1.03, 0.67, -5.98),
                (s * 1.03, 0.67, -4.76),
                [(0, 0.22), (0.08, 0.28), (0.92, 0.28), (1, 0.22)],
                "alloy",
                9,
            )
            m.box((s * 1.16, 0.67, -7.25), (0.29, 0.22, 1.3), "vents")
            mirror(m, s, 1.14, 2.63, -7.68)
    wheels(m, 1.22, [-8.26, -5.33, -4.07, 5.87, 7.14], 0.51)
    m.end(False, -9.28, 0, 0.88, 0.91, 0.53, "grille")
    m.box((0, 0.67, -9.18), (2.34, 0.27, 0.32), "alloy")
    m.end(True, 8.542, 0, 1.03, 2.39, 3.00, "hatch")
    for s in (-1, 1):
        m.end(True, 8.58, s * 0.99, 0.79, 0.35, 0.13, "red_lens")
        if m.detailed:
            m.bar((s * 0.65, 1.05, 8.57), (s * 0.65, 4.04, 8.57), 0.037, "alloy")
            m.end(True, 8.61, s * 0.84, 1.14, 0.43, 0.18, "hazard")
    if m.detailed:
        m.hull(
            [
                (-7.29, 1.90, 3.21, 3.37, 0.84),
                (-6.46, 2.12, 3.28, 4.06, 0.82),
                (-5.98, 2.3, 3.29, 4.09, 0.9),
            ],
            "rail",
        )


def sedan(m):
    if not m.detailed:
        m.hull(
            [
                (-2.24, 1.44, 0.38, 0.75, 0.85),
                (-1.64, 1.89, 0.27, 0.96, 0.86),
                (1.39, 1.91, 0.27, 0.99, 0.86),
                (2.16, 1.52, 0.40, 0.82, 0.88),
            ],
            "paint",
        )
        m.hull(
            [
                (-1.05, 1.59, 0.95, 1.0, 0.91),
                (-0.34, 1.55, 0.96, 1.49, 0.84),
                (0.62, 1.55, 0.96, 1.49, 0.84),
                (1.35, 1.54, 0.95, 1.0, 0.93),
            ],
            "glass",
        )
        for z in (-1.34, 1.34):
            m.barrel(
                (-0.973, 0.335, z),
                (0.973, 0.335, z),
                [(0, 0.335), (1, 0.335)],
                "rubber",
                8,
            )
        for side in (-1, 1):
            m.end(True, 2.168, side * 0.55, 0.61, 0.39, 0.12, "red_lens")
            m.end(False, -2.246, side * 0.56, 0.61, 0.33, 0.11, "white_lens")
        return
    # The rocker rises over each tire, leaving real wheel wells in the outer panels.
    stations = [
        (-2.24, 0.72, 0.45, 0.75),
        (-1.95, 0.88, 0.30, 0.87),
        (-1.74, 0.94, 0.29, 0.91),
    ]
    for center in (-1.34, 1.34):
        if center > 0:
            stations.extend(
                [
                    (-0.79, 0.975, 0.25, 1.00),
                    (0.0, 0.984, 0.25, 1.04),
                    (0.79, 0.975, 0.25, 1.0),
                ]
            )
        for angle in np.linspace(-math.pi / 2, math.pi / 2, 9 if m.detailed else 5):
            stations.append(
                (
                    center + 0.384 * math.sin(angle),
                    0.968,
                    0.32 + 0.384 * math.cos(angle),
                    0.97,
                )
            )
    stations.extend([(1.84, 0.91, 0.31, 0.89), (2.16, 0.76, 0.42, 0.82)])
    rings = []
    for z, w, arch, top in stations:
        ring = [
            (-w, arch),
            (-w * 0.70, 0.29),
            (w * 0.70, 0.29),
            (w, arch),
            (w, top - 0.14),
            (w * 0.84, top),
            (0, top + 0.026),
            (-w * 0.84, top),
            (-w, top - 0.14),
        ]
        rings.append([(x, y, z) for x, y in ring])
    m.skin(rings, "paint")
    # Glazed four-door greenhouse, with a sloping rear screen and short trunk deck.
    roof = [
        (-1.05, 0.776, 0.982),
        (-0.34, 0.676, 1.465),
        (-0.03, 0.69, 1.51),
        (0.62, 0.681, 1.49),
        (1.35, 0.768, 0.983),
    ]
    upper = [[(-w, y, z), (w, y, z), (0.0, y + 0.045, z)] for z, w, y in roof]
    for i in range(len(roof) - 1):
        for j in (0, 1):
            ix = [0, 2, 1]
            m.fin(
                [
                    upper[i][ix[j]],
                    upper[i + 1][ix[j]],
                    upper[i + 1][ix[j + 1]],
                    upper[i][ix[j + 1]],
                ],
                (0, 0.014, 0),
                "glass" if i in (0, 3) else "paint",
            )
    for side in (-1, 1):
        sx = side
        for za, zb, wa, wb, ha, hb in [
            (a[0], b[0], a[1], b[1], a[2], b[2]) for a, b in zip(roof, roof[1:])
        ]:
            pts = [
                (sx * 0.851, 0.961, za),
                (sx * 0.851, 0.961, zb),
                (sx * wb, hb, zb),
                (sx * wa, ha, za),
            ]
            m.fin(pts, (sx * 0.008, 0, 0), "glass")
        if m.detailed:
            m.bar(
                (sx * 0.855, 0.975, 0.19),
                (sx * 0.685, 1.509, 0.095),
                0.036,
                "graphite",
                6,
            )
            for z, w, h in (roof[0], roof[-1]):
                top = roof[1] if z < 0 else roof[-2]
                m.bar(
                    (sx * 0.845, 0.969, z),
                    (sx * top[1], top[2], top[0]),
                    0.042,
                    "paint",
                    8,
                )
            m.bar(
                (sx * 0.857, 0.972, -1.06), (sx * 0.857, 0.972, 1.35), 0.019, "alloy", 6
            )
            for z in (-0.18, 0.80):
                m.box((sx * 0.966, 0.855, z), (0.037, 0.047, 0.15), "alloy")
            for z in (0.16, -0.88, 0.94):
                m.bar(
                    (sx * 0.978, 0.39, z),
                    (sx * 0.977, 0.814, z + 0.035),
                    0.009,
                    "graphite",
                    5,
                )
            m.bar(
                (sx * 0.806, 1.055, -0.72),
                (sx * 0.972, 1.088, -0.67),
                0.034,
                "graphite",
                6,
            )
            m.hull(
                [
                    (-0.80, 0.065, 1.078, 1.121, 0.8),
                    (-0.70, 0.17, 1.068, 1.172, 0.87),
                    (-0.59, 0.125, 1.071, 1.145, 0.9),
                ],
                "paint",
                sx * 0.994,
            )
        m.fin(
            [
                (sx * 0.59, 0.65, -2.26),
                (sx * 0.75, 0.64, -2.23),
                (sx * 0.88, 0.69, -1.99),
                (sx * 0.89, 0.80, -1.92),
                (sx * 0.67, 0.77, -2.23),
            ],
            (0, 0.018, -0.012),
            "white_lens",
        )
        m.end(True, 2.168, sx * 0.55, 0.61, 0.39, 0.12, "red_lens")
    wheels(m, 0.973, [-1.34, 1.34], 0.335)
    m.end(False, -2.249, 0, 0.45, 0.93, 0.17, "grille")
    if m.detailed:
        m.end(True, 2.169, 0, 0.47, 0.36, 0.13, "plate")


def bogie(m, z):
    if not m.detailed:
        m.box((0, 0.55, z), (2.65, 0.79, 3.42), "graphite")
        return
    m.box((0, 0.60, z), (2.39, 0.50, 3.40), "graphite")
    wheels(m, 1.39, [z - 1.02, z + 1.02], 0.46, True)
    if m.detailed:
        for s in (-1, 1):
            m.box((s * 1.35, 0.72, z), (0.18, 0.33, 2.84), "hot")
            for t in (-0.72, 0.72):
                m.barrel(
                    (s * 1.36, 0.39, z + t),
                    (s * 1.36, 0.77, z + t),
                    [(0, 0.19), (0.25, 0.23), (0.80, 0.22), (1, 0.18)],
                    "graphite",
                    7,
                )


def locomotive(m):
    m.box((0, 1.39, 0), (3.11, 0.62, 20.48), "graphite")
    m.box((0, 1.76, 0), (3.19, 0.19, 20.62), "alloy")
    for z in (-6.45, 6.45):
        bogie(m, z)
    m.hull(
        [
            (-9.74, 2.04, 1.81, 2.94, 0.74),
            (-8.93, 2.47, 1.81, 3.13, 0.80),
            (-6.35, 2.48, 1.81, 3.14, 0.87),
        ],
        "oxide",
    )
    m.hull(
        [
            (-7.47, 2.13, 2.15, 3.77, 0.72),
            (-6.74, 2.99, 1.86, 4.65, 0.78),
            (-4.63, 2.99, 1.86, 4.62, 0.80),
        ],
        "rail",
    )
    m.end(False, -7.48, 0, 3.11, 1.87, 0.55, "cabin")
    m.hull(
        [
            (-4.72, 2.42, 1.86, 3.84, 0.85),
            (-3.91, 2.51, 1.86, 4.17, 0.81),
            (8.20, 2.47, 1.86, 4.12, 0.78),
            (9.42, 2.13, 1.86, 3.56, 0.82),
        ],
        "rail",
    )
    for s in (-1, 1):
        m.side(s, 1.503, -5.64, 3.35, 1.69, 0.64, "glass")
        m.side(s, 1.266, 2.12, 2.43, 11.28, 1.25, "vents")
        m.end(False, -9.751, s * 0.62, 2.63, 0.32, 0.21, "white_lens")
        if m.detailed:
            for z in (-9.41, -7.83, -4.11, -1.22, 1.61, 4.45, 7.38, 9.50):
                m.bar((s * 1.54, 1.83, z), (s * 1.54, 2.67, z), 0.041, "oxide", 5)
            m.bar((s * 1.54, 2.67, -9.41), (s * 1.54, 2.67, 9.50), 0.045, "oxide", 6)
            for z in (-8.56, 8.63):
                m.box((s * 1.45, 1.21, z), (0.23, 0.13, 1.17), "hazard")
            m.side(s, 1.507, -5.60, 2.3, 1.45, 0.69, "plate")
    if m.detailed:
        for side in (-1, 1):
            for z in (0.2, 3.1, 6.1):
                m.side(side, 1.278, z, 2.9, 2.34, 0.93, "vents")
                m.box((side * 1.28, 2.39, z), (0.045, 0.075, 2.41), "oxide")
            m.box((side * 1.59, 1.37, -1.12), (0.04, 0.115, 15.3), "oxide")
        for z in (-0.21, 2.5, 5.31):
            m.barrel(
                (0, 4.12, z),
                (0, 4.27, z),
                [(0, 1.01), (1, 0.97)],
                "alloy",
                14,
                cap="grille",
            )
        m.box((0, 4.13, -2.65), (0.69, 0.73, 0.68), "hot")
        m.box((0, 1.02, -10.23), (2.82, 0.67, 0.41), "hazard")
        m.box((0, 0.83, 0), (1.84, 0.81, 5.35), "graphite")


def boxcar(m):
    m.box((0, 1.01, 0), (2.88, 0.45, 17.73), "graphite")
    m.hull(
        [
            (-8.61, 2.91, 1.19, 4.43, 0.88),
            (-8.35, 3.05, 1.19, 4.55, 0.87),
            (8.35, 3.05, 1.19, 4.55, 0.87),
            (8.61, 2.91, 1.19, 4.43, 0.88),
        ],
        "cargo",
    )
    for z in (-6.29, 6.29):
        bogie(m, z)
    for s in (-1, 1):
        m.side(s, 1.53, 0, 1.34, 16.58, 2.70, "cargo")
        m.box((s * 1.546, 2.67, 0), (0.08, 2.72, 3.58), "hatch")
        if m.detailed:
            m.box((s * 1.59, 4.07, 0), (0.12, 0.093, 5.31), "alloy")
            for z in (-8.14, -5.24, -2.24, 2.24, 5.24, 8.14):
                m.box((s * 1.54, 2.72, z), (0.13, 2.98, 0.11), "hot")
            m.side(s, 1.55, -4.08, 2.55, 1.66, 0.71, "freight_id")
            for z in (-8.10, -7.47):
                m.bar((s * 1.60, 1.07, z), (s * 1.60, 4.12, z), 0.034, "alloy", 5)
            for h in np.arange(1.34, 4.11, 0.4):
                m.bar((s * 1.61, h, -8.10), (s * 1.61, h, -7.47), 0.029, "alloy", 5)
    for z in (-8.89, 8.89):
        m.box((0, 0.97, z), (0.56, 0.31, 0.64), "hot")


def airliner(m):
    detail = m.detailed
    # Elliptical fuselage stations: raised cockpit crown, pressure barrel, upswept tailcone.
    sections = [
        (-33, 0.16, 0.17, -0.57),
        (-31.6, 1.12, 0.91, -0.47),
        (-29.3, 1.91, 1.59, -0.12),
        (-26.0, 2.20, 2.08, 0.02),
        (-22.1, 2.27, 2.24, 0.04),
        (16, 2.25, 2.24, 0.04),
        (21.2, 2.09, 2.08, 0.18),
        (27.4, 1.39, 1.43, 0.65),
        (33.6, 0.24, 0.38, 1.29),
    ]
    n = 24 if detail else 12
    rings = [
        [
            (w * math.cos(i * math.tau / n), y + h * math.sin(i * math.tau / n), z)
            for i in range(n)
        ]
        for z, w, h, y in sections
    ]
    m.skin(rings, "ivory", True)
    # Place each livery panel on the elliptical pressure shell, including the curved nose.
    zs, ws, hs, ys = np.array(sections).T

    def surface(z, angle, side, offset=0.025):
        a = math.radians(angle)
        return (
            side * (np.interp(z, zs, ws) + offset) * math.cos(a),
            np.interp(z, zs, ys) + (np.interp(z, zs, hs) + offset) * math.sin(a),
            z,
        )

    def stripe(side, a, b, low, high, finish):
        pts = [
            surface(a, low, side),
            surface(b, low, side),
            surface(b, high, side),
            surface(a, high, side),
        ]
        if side == 1:
            pts = pts[::-1]
        m.face(pts, finish)

    for s in (-1, 1):
        for a, b in zip(zs[:-1], zs[1:]):
            for low, high in [(-89, -62), (-62, -36), (-36, -13)]:
                stripe(s, a, b, low, high, "rail")
            stripe(s, a, b, -13, -9, "oxide")
        for a, b, lo1, hi1, lo2, hi2 in [
            (-31.5, -30.1, 32, 60, 29, 61),
            (-30.0, -28.75, 29, 59, 27, 53),
            (-28.68, -27.32, 27, 51, 25, 40),
        ]:
            pts = [
                surface(a, lo1, s, 0.055),
                surface(b, lo2, s, 0.055),
                surface(b, hi2, s, 0.055),
                surface(a, hi1, s, 0.055),
            ]
            m.face(pts[::-1] if s == 1 else pts, "glass")
        # Windows sit on the fuselage rather than on a shadow-casting second hull.
        for j in range(9 if detail else 4):
            l = 4.56 if detail else 10.24
            a = -21.7 + l * j
            stripe(s, a, a + l, 4, 24, "glassband")
        # Sweep, dihedral and winglets remain visible from underneath at cruise.
        foil = [
            (s * 1.58, -0.65, -8.2),
            (s * 9.7, -0.56, -5.1),
            (s * 29.6, 2.08, 5.45),
            (s * 30.1, 2.20, 7.52),
            (s * 9.1, -0.57, 3.92),
            (s * 1.58, -0.65, 5.23),
        ]
        m.fin(foil, (0, 0.36, 0), "ivory")
        m.fin(
            [
                (s * 29.3, 1.98, 5.32),
                (s * 31.1, 4.62, 6.54),
                (s * 31.4, 4.89, 7.41),
                (s * 29.93, 2.08, 7.62),
            ],
            (s * 0.14, 0, 0),
            "rail",
        )
        m.fin(
            [
                (s * 0.83, 1.02, 22.35),
                (s * 10.56, 2.61, 28.73),
                (s * 10.78, 2.68, 30.23),
                (s * 0.68, 1.26, 28.41),
            ],
            (0, 0.23, 0),
            "rail",
        )
        px = s * 9.2
        m.fin(
            [(px, -0.55, -3), (px, -0.62, 0.92), (px, -2.17, 0.65), (px, -2.34, -4.21)],
            (s * 0.54, 0, 0),
            "alloy",
        )
        m.barrel(
            (px, -2.71, -6.43),
            (px, -2.71, 0.03),
            [(0, 1.30), (0.06, 1.45), (0.31, 1.50), (0.80, 1.27), (1, 0.93)],
            ["alloy", "rail", "rail", "hot"],
            16 if detail else 9,
            cap="grille",
        )
        if detail:
            # Recessed fan face, blades and hub on each nacelle.
            for k in range(12):
                a = k * math.tau / 12

                def pt(r, off):
                    return (
                        px + r * math.cos(a + off),
                        -2.71 + r * math.sin(a + off),
                        -6.45,
                    )

                m.face(
                    [pt(0.30, 0.02), pt(1.09, 0.10), pt(1.16, -0.07), pt(0.45, -0.21)],
                    "alloy",
                )
            m.barrel(
                (px, -2.71, -6.45),
                (px, -2.71, -6.70),
                [(0, 0.32), (1, 0.12)],
                "alloy",
                10,
            )
            for t in (0.36, 0.62, 0.80):
                xw = s * (2 + 26 * t)
                zw = 4.8 + 2.0 * t
                m.hull(
                    [
                        (zw - 1.0, 0.18, -0.28 + 2.2 * t, 0.02 + 2.2 * t, 0.8),
                        (zw + 1.45, 0.39, -0.39 + 2.2 * t, 0.14 + 2.2 * t, 0.8),
                        (zw + 2.20, 0.06, -0.06 + 2.2 * t, 0.04 + 2.2 * t, 0.8),
                    ],
                    "alloy",
                    xw,
                )
            for z in (-22.3, -5.48, 16.86):
                stripe(s, z - 0.47, z + 0.47, -7, 37, "hatch")
        m.end(False, -4.11, s * 11.7, -0.59, 0.43, 0.17, "white_lens")
    m.fin(
        [
            (0, 1.41, 17.73),
            (0, 1.95, 20.07),
            (0, 9.89, 27.01),
            (0, 10.46, 29.40),
            (0, 1.53, 30.62),
        ],
        (0.47, 0, 0),
        "rail",
    )
    if detail:
        for s in (-1, 1):
            m.fin(
                [
                    (s * 0.245, 3.85, 23.7),
                    (s * 0.245, 4.59, 24.14),
                    (s * 0.245, 7.62, 28.4),
                    (s * 0.245, 6.7, 28.58),
                ],
                (s * 0.019, 0, 0),
                "oxide",
            )
