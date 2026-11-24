"""Armoured Network raider, authored in the traffic fleet's pre-scale coordinates."""


def plate(m, sections, finish):
    """Loft an armoured casting with chamfered sills and a narrower upper face.

    Each station is z, x centre, half-width, sill height, crown height.
    """
    rings = []
    for z, x, w, bottom, top in sections:
        h = top - bottom
        profile = [
            (-0.82 * w, bottom),
            (0.82 * w, bottom),
            (w, bottom + 0.23 * h),
            (0.94 * w, bottom + 0.72 * h),
            (0.68 * w, top),
            (-0.68 * w, top),
            (-0.94 * w, bottom + 0.72 * h),
            (-w, bottom + 0.23 * h),
        ]
        if not m.detailed:
            profile = [profile[i] for i in (0, 1, 2, 4, 5, 7)]
        rings.append([(x + px, y, z) for px, y in profile])
    if not m.detailed and isinstance(finish, list):
        finish = [finish[i] for i in (0, 1, 2, 4, 6, 7)]
    m.skin(rings, finish)


def flank_tiles(m, side):
    # The outside of each plate follows the sweep of the cheek. Cut corners
    # and a narrow joint expose the bronze carrier between graphite tiles.
    spans = [
        (-5.41, -4.27, 1.67, 2.045), (-4.05, -2.87, 2.105, 2.301),
        (-2.68, -1.31, 2.333, 2.558), (-1.12, 0.11, 2.58, 2.58),
        (0.30, 1.45, 2.58, 2.58),
    ]
    for index, (start, end, x0, x1) in enumerate(spans):
        def point(t, y, lift=0):
            return (side * (x0 + (x1 - x0) * t + lift), y, start + (end - start) * t)

        outline = [
            point(0, 0.71), point(0.16, 0.54), point(0.91, 0.57),
            point(1, 0.72), point(0.90, 1.11), point(0.16, 1.14),
        ]
        m.fin(outline, (side * 0.085, 0, 0), "graphite")
        for t in (0.22, 0.83):
            m.bar(point(t, 0.71, 0.030), point(t, 0.71, 0.067), 0.046, "alloy", 6)
        if index in (1, 2, 3):
            # Three inset red louvers remain identifiable in a broadside pass.
            m.fin([
                point(0.35, 0.86, 0.051), point(0.51, 0.83, 0.051),
                point(0.72, 1.04, 0.051), point(0.55, 1.06, 0.051),
            ], (side * 0.015, 0, 0), "red_lens")


def raider(m):
    # The rear bridge and two long prow cheeks leave an open bite in the nose.
    plate(m, [
        (-4.45, 0, 1.13, 0.38, 0.86),
        (-2.1, 0, 1.94, 0.22, 1.22),
        (2.4, 0, 2.06, 0.20, 1.39),
        (5.86, 0, 1.52, 0.40, 1.31),
    ], "graphite")

    # An uninterrupted armoured brow shades the narrow inset pilot visor.
    plate(m, [
        (-1.89, 0, 0.73, 1.04, 1.26),
        (-0.42, 0, 1.02, 1.16, 2.05),
        (1.31, 0, 0.98, 1.18, 2.09),
        (2.28, 0, 0.68, 1.19, 1.66),
    ], "glass")
    plate(m, [
        (-1.35, 0, 0.65, 1.61, 1.72),
        (-0.45, 0, 1.09, 1.97, 2.18),
        (1.39, 0, 1.08, 2.00, 2.21),
        (2.61, 0, 0.66, 1.44, 1.74),
    ], "graphite")

    for side in (-1, 1):
        # Wear faces are a warmer cast metal. The outer ends hook away from the
        # inset pilot instead of reading as the rounded drive pods on a demon.
        plate(m, [
            (-6.40, side * 0.99, 0.35, 0.56, 1.35),
            (-4.18, side * 1.42, 0.66, 0.27, 1.52),
            (-1.15, side * 1.79, 0.79, 0.18, 1.67),
            (1.72, side * 1.86, 0.72, 0.18, 1.45),
        ], ["graphite", "graphite", "hot", "graphite",
            "graphite", "graphite", "hot", "graphite"])
        plate(m, [
            (1.56, side * 1.80, 0.64, 0.25, 1.32),
            (3.38, side * 1.87, 0.67, 0.20, 1.58),
            (6.36, side * 1.14, 0.57, 0.42, 1.49),
        ], "graphite")

        # Both tiers keep the bedded crimson lenses and the forked rear crest.
        # Light centres at x=1.0 and y=1.20 match the traffic shader's pair.
        m.end(False, -6.408, side * 0.99, 1.08, 0.43, 0.23, "red_lens")
        m.end(True, 6.368, side * 1.05, 1.07, 0.49, 0.25, "red_lens")
        m.fin([
            (side * 1.56, 1.44, 2.88), (side * 1.82, 2.04, 4.53),
            (side * 2.16, 2.87, 6.13), (side * 2.16, 2.87, 6.38),
            (side * 1.54, 1.42, 5.85),
        ], (0.16, 0, 0), "hot")
        if m.detailed:
            flank_tiles(m, side)
            # Independent cheek shields with clipped leading corners and a dark
            # seam above the rub rail. A broad slash crosses each shield.
            for z, x, length, crown in [
                (-3.58, 1.56, 1.55, 1.64),
                (-1.61, 1.76, 1.86, 1.82),
                (0.49, 1.86, 2.00, 1.71),
            ]:
                plate(m, [
                    (z - length / 2, side * (x - 0.09), 0.45, crown - 0.40, crown - 0.16),
                    (z - length * 0.20, side * x, 0.67, crown - 0.33, crown),
                    (z + length / 2, side * (x + 0.04), 0.62, crown - 0.29, crown - 0.05),
                ], "graphite")
            m.fin([
                (side * 1.17, 1.021, -6.404), (side * 1.25, 1.185, -6.404),
                (side * 1.66, 1.334, -5.38), (side * 1.57, 1.157, -5.38),
            ], (side * 0.023, 0, 0), "red_lens")
            # Side-gill cassettes carry a patterned grille under three thick,
            # individually shaded louvres. Their rear taper follows the hull.
            plate(m, [
                (2.46, side * 1.80, 0.46, 1.14, 1.62),
                (3.38, side * 1.87, 0.54, 1.31, 1.74),
                (4.78, side * 1.62, 0.44, 1.28, 1.65),
            ], "vents")
            for z in (3.02, 3.53, 4.04):
                x = 1.81 - max(0, z - 3.38) * 0.16
                m.fin([
                    (side * (x - 0.40), 1.76, z - 0.15),
                    (side * (x + 0.37), 1.76, z - 0.07),
                    (side * (x + 0.34), 1.73, z + 0.10),
                    (side * (x - 0.35), 1.73, z + 0.04),
                ], (0, 0.07, 0), "hot")

    if m.detailed:
        plate(m, [
            (2.43, 0, 0.69, 1.29, 1.52),
            (3.15, 0, 1.04, 1.34, 1.71),
            (5.44, 0, 0.87, 1.26, 1.63),
        ], "vents")
        for z in (3.23, 3.72, 4.21, 4.70):
            y = 1.715 - (z - 3.15) * 0.035
            m.box((0, y, z), (1.26, 0.072, 0.12), "graphite")
        m.end(False, -4.458, 0, 0.49, 1.41, 0.28, "grille")
        m.end(True, 5.867, 0, 0.64, 1.73, 0.42, "vents")
