"""Express parcel pod and Network highway-service tender, in unscaled metres."""

from network import canopy, running_gear


def _shell(m, stations, finish):
    """Folded shell with flat flanks for doors and diagonal rolled shoulders.

    Each station is (z, half width, floor, roof, corner radius).
    """
    rings = []
    for z, w, floor, roof, r in stations:
        rings.append(
            [
                (x, y, z)
                for x, y in (
                    (-w + r, floor),
                    (w - r, floor),
                    (w, floor + r),
                    (w, roof - r),
                    (w - r, roof),
                    (-w + r, roof),
                    (-w, roof - r),
                    (-w, floor + r),
                )
            ]
        )
    m.skin(rings, finish)


def _lamps(m, x, front, rear, tail):
    # Billboard pairs sit just beyond these physical lenses, centered at y=1.2.
    for side in (-1, 1):
        for aft, z, finish in ((False, front, "white_lens"), (True, rear, tail)):
            m.end(aft, z, side * x, 1.10, 0.51, 0.20, finish)


def courier(m):
    """Single driver ahead of a removable parcel cassette, slung between skids."""
    stations = [
        (-5.86, 1.76, 0.68, 1.36, 0.15),
        (-4.34, 1.92, 0.34, 1.48, 0.25),
        (-2.15, 1.99, 0.28, 1.49, 0.28),
        (3.78, 1.99, 0.29, 1.39, 0.24),
        (5.84, 1.78, 0.55, 1.38, 0.17),
    ]
    _shell(m, stations if m.detailed else stations[::2], "paint")
    canopy(m, -0.10, -2.78, 2.38, 4.62, 1.36, 1.05)

    # The lift-out cassette has a low loading lip and vertical side faces. Its
    # top and aft roll over into the door, giving it a tall square cargo tail.
    pod = [
        (-0.91, 1.47, 1.30, 2.23, 0.20),
        (-0.42, 1.65, 1.29, 2.56, 0.15),
        (4.54, 1.65, 1.29, 2.56, 0.15),
        (5.48, 1.52, 1.27, 2.32, 0.16),
    ]
    _shell(m, pod, "ivory")
    m.end(True, 5.49, 0, 1.40, 2.62, 0.74, "graphite")
    m.end(True, 5.50, 0, 1.45, 2.47, 0.63, "cargo")
    _lamps(m, 1.50, -5.872, 5.852, "red_lens")
    for side in (-1, 1):
        if m.detailed:
            running_gear(m, side, 1.72, 2.33, 5.54, 0.80)
        else:
            m.box((side * 1.72, 0.47, 2.33), (0.55, 0.53, 5.35), "graphite")
        # Recessed side loader, protruding handles and a raised express arrow.
        flank = 1.651
        m.side(side, flank, 2.05, 1.50, 4.68, 0.79, "band")
        for z in (0.66, 1.06):
            arrow = [
                (side * (flank + 0.009), y, z + shift)
                for y, shift in (
                    (1.56, 0.46),
                    (1.56, 0.21),
                    (1.90, -0.29),
                    (2.20, 0.16),
                    (2.20, 0.39),
                    (1.90, -0.04),
                )
            ]
            # The two swept halves meet on the middle seam, avoiding a concave cap.
            for indices in ((0, 1, 2, 5), (2, 3, 4, 5)):
                corners = [arrow[i] for i in indices]
                m.fin(corners, (side * 0.010, 0, 0), "oxide")
        if m.detailed:
            m.side(side, flank + 0.005, 3.07, 1.61, 1.19, 0.35, "freight_id")
            for z in (-0.30, 4.36):
                m.box((side * 1.68, 1.53, z), (0.08, 0.46, 0.16), "graphite")
                m.box((side * 1.728, 1.52, z), (0.025, 0.24, 0.10), "alloy")
    if m.detailed:
        for x in (-0.74, 0.74):
            m.box((x, 2.561, 2.04), (0.074, 0.065, 4.94), "service")
        m.end(True, 5.517, 0, 1.69, 0.68, 0.19, "plate")
        m.end(False, -5.875, 0, 0.84, 1.45, 0.26, "grille")


def _boom(m):
    # Looking from the side, the two links form a folded hairpin. The lower
    # arm tapers into its pivot; the upper link carries the telescoping tool.
    links = [
        (
            0.68,
            [(2.96, -1.64), (2.84, -1.27), (1.66, 3.32), (1.70, 3.78), (2.16, 3.56), (3.16, -1.56)],
            "oxide",
        ),
        (0.45, [(2.89, -1.62), (3.15, -1.65), (3.53, 2.87), (3.42, 3.03)], "hazard"),
    ]
    # First link's offset beam has a six-sided section in silhouette.
    for width, yz, finish in links:
        m.fin([(0, y, z) for y, z in yz], (width, 0, 0), finish)
    if m.detailed:
        for y, z, r in ((1.88, 3.50, 0.33), (3.02, -1.54, 0.24), (3.46, 2.91, 0.15)):
            m.barrel((-0.40, y, z), (0.40, y, z), [(0, r * 0.92), (0.10, r), (1, r)], "graphite", 10, cap="hub")
        # Piston rod is coaxial with its barrel. Both clevises meet the links.
        a, b = (-0.39, 2.03, 3.35), (-0.39, 2.78, -0.10)
        joint = tuple(x + (y - x) * 0.58 for x, y in zip(a, b))
        m.bar(a, joint, 0.085, "graphite", 8)
        m.bar(joint, b, 0.047, "alloy", 8)
        m.box((0, 3.42, 3.22), (0.43, 0.18, 0.68), "service")


def tender(m):
    """Forward control cab, side-access workshop and a folded lift below roof height."""
    deck = [
        (-6.89, 2.25, 0.54, 1.40, 0.14),
        (-5.51, 2.42, 0.29, 1.48, 0.22),
        (4.95, 2.42, 0.28, 1.43, 0.20),
        (6.84, 2.25, 0.46, 1.39, 0.16),
    ]
    if not m.detailed:
        # A single side extrusion carries the cab, steep windscreen and the
        # lower locker bank. The orange knuckle-boom stays above its roofline.
        profile = [
            (0.33, -6.89),
            (0.33, 6.84),
            (2.12, 6.84),
            (2.12, -2.46),
            (3.09, -2.46),
            (3.09, -4.84),
            (2.44, -6.89),
        ]
        # The cab/deck step is concave; split the extrusion at the cab bulkhead.
        m.box((0, 1.225, 2.19), (4.50, 1.79, 9.30), "paint")
        m.fin([(0, y, z) for y, z in (profile[0], (0.33, -2.46), *profile[4:])], (4.50, 0, 0), "paint")
    else:
        _shell(m, deck, "graphite")
        _shell(
            m,
            [(-6.88, 2.24, 1.33, 2.46, 0.12), (-5.0, 2.34, 1.33, 3.12, 0.17), (-2.50, 2.34, 1.31, 3.12, 0.17)],
            "paint",
        )
        for side in (-1, 1):
            # Boxes flank an open channel so the boom foot and piston read separately.
            m.hull(
                [(-2.42, 1.0, 1.35, 2.10, 0.92), (5.97, 1.0, 1.35, 2.10, 0.92), (6.60, 0.96, 1.33, 1.96, 0.92)],
                "service",
                side * 1.78,
            )
            # Two sled shoes share each long drive rail; most of each shoe is
            # hidden under the chassis, so only its wedge and sole need facets.
            for z in (-3.96, 4.55):
                m.fin(
                    [
                        (side * 2.03, y, z + dz)
                        for y, dz in (
                            (0.34, -1.75),
                            (0.12, -1.29),
                            (0.12, 1.36),
                            (0.30, 1.74),
                            (0.53, 1.64),
                            (0.54, -1.48),
                        )
                    ],
                    (0.56, 0, 0),
                    "graphite",
                )
    # Panoramic windscreen wraps from its front face into both cab doors.
    m.end(False, -6.903, 0, 1.65, 4.05, 0.65, "glass")
    for side in (-1, 1):
        side_x = 2.346 if m.detailed else 2.255
        m.side(side, side_x, -3.83, 1.89, 2.14, 0.82, "glass")
        if m.detailed:
            for z in (-1.69, -0.11, 1.47, 3.05, 4.63):
                # Locker panels project from a shallow undercut plinth.
                m.box((side * 2.281, 1.70, z), (0.047, 0.62, 1.50), "hatch")
                m.box((side * 2.311, 1.88, z + 0.41), (0.027, 0.07, 0.29), "graphite")
            m.side(side, 2.427, 0.74, 0.76, 5.62, 0.16, "hazard")
        else:
            m.side(side, side_x, 1.81, 1.52, 7.84, 0.30, "service")
    _lamps(m, 1.90, -6.906, 6.851, "amber")
    if m.detailed:
        m.barrel(
            (0, 1.37, 3.50), (0, 1.81, 3.50), [(0, 0.74), (0.21, 0.76), (1, 0.57)], ["graphite", "service"], 12
        )
    _boom(m)
    if m.detailed:
        m.box((0, 2.84, -1.54), (0.82, 0.29, 0.49), "graphite")
        for x in (-0.28, 0.28):
            m.box((x, 2.07, -1.54), (0.13, 1.31, 0.34), "service")
        m.end(True, 6.852, 0, 1.00, 2.37, 0.27, "hazard")
        m.end(False, -6.906, 0, 1.03, 1.71, 0.31, "grille")
