# The ramjet's voice

Baked by `tools/ramjet_bake.py` (run `python -I tools/ramjet_bake.py`) from two recordings of real rocket engines, kept in
`tools/audio_src/ramjet` so the bake can be run again. Fetched 2026-11-22; the licence of each was read from its own page
that day.

| Source | By | Terms | Used for |
|---|---|---|---|
| Freesound [220127](https://freesound.org/s/220127/), "shuttlelaunch.wav" (the site's high-quality preview, 132 s) | klangfabrik: by its own page, a re-edit of NASA's public-domain recordings of Space Shuttle launches, the commentary cut out | Creative Commons 0 (https://creativecommons.org/publicdomain/zero/1.0/): no attribution is required, and it is given here anyway | the low roar's loop (24 s to 34 s of it), the light-up's thump and low swell (its first three seconds), the weight under the shut-down (30 s to 31 s) |
| NASA Image and Video Library, [SSC_2025-11-12_RS-25_Engine_Test](https://images.nasa.gov/details/SSC_2025-11-12_RS-25_Engine_Test), "RS-25 Engine Test 2025-11-12" | NASA Stennis Space Center: RS-25 engine no. 20002 run for 500 s, to 111% power, on the Fred Haise Test Stand | NASA's own film: "generally ... not subject to copyright in the United States" (https://www.nasa.gov/nasa-brand-center/images-and-media/). NASA asks that its material not be used to suggest it endorses anything: it does not endorse this game | the scream's loop (133 s to 141 s of the film), the engine catching in the light-up (11 s to 13 s), its cut-off in the shut-down (510 s to 511 s, and 516 s to 517 s) |

The NASA film's sound was taken from the library's "medium" copy (AAC, 48 kHz, 160 kb/s; the two channels are the same) in
three stretches, with `ffmpeg -ss START -i URL -t SECONDS -vn -c:a copy` (4 s + 44 s, 128 s + 50 s, 498 s + 30 s), and
those are kept as mono Vorbis (`ffmpeg -ac 1 -c:a libvorbis -q:a 7`). No picture was kept.

Nothing here is synthesised. What was done to the recordings: cut, filtered (the roar to 110 Hz - 1.5 kHz with its weight
lifted 5 dB at 420 Hz, the scream to 0.5 - 8 kHz with one resonance lifted 6 dB at 2.3 kHz so that it has a note), their
slow swells levelled, their ends folded into their beginnings so they loop, their tallest crackle held under full scale;
the shut-down is slowed as a tape runs down (to 0.6 of its speed in 0.8 s), and the right engine's light-up and shut-down
are the left's played 3.5% slower. The game then plays the loops faster with speed (the roar x0.92 to x1.08, the scream
x0.85 to x1.25) and sets every level (`audio/engine_audio.gd`, the `ram_*` lines of `TUNE`).

Lengths, seams, levels and loudness are measured (the bake prints them and fails on a seam that shows;
`tools/engine_audio_check.py` measures the voice in recordings of the game). None of it had been judged by ear when this
was written.

## How its levels were set (2026-11-22)

Not by ear. The game's own mix was recorded with the engine's movie writer (`tests/record_ramjet.gd`: the cockpit on the
range, flown as the headset's trigger scheme flies it, fourth gear, both triggers in) with the craft's speed pinned, once
with this voice and once with the engine audio as it was before it (commit `e0a2e7b`). K-weighted loudness (ITU-R BS.1770's
weighting, ungated) of seven seconds on the ramjet, and the change in the mix's bands:

| Speed | Before | With the voice | Change | 120-400 Hz | 0.5-1.4 kHz | 1.5-5 kHz | over 5 kHz |
|---|---|---|---|---|---|---|---|
| 3,000 mph | -9.5 LUFS | -9.3 LUFS | +0.2 LU | +0.3 dB | +0.5 dB | +6.3 dB | +5.5 dB |
| 5,000 mph | -10.8 LUFS | -9.1 LUFS | +1.6 LU | +0.9 dB | +2.9 dB | +2.5 dB | +3.3 dB |
| 7,000 mph | -10.4 LUFS | -8.8 LUFS | +1.7 LU | +1.0 dB | +3.0 dB | +2.4 dB | +4.7 dB |

The same stretches where nothing of the voice sounds (the burner before the ramjet is armed, and after it is disarmed)
differ from run to run by up to 0.8 LU: twin engines a third of a percent apart swing the mix's low end every few seconds.
At 3,000 mph the V8 is at its loudest and leads everything under 1.4 kHz, so there the voice is its scream and its
light-up; its low roar shows from about 4,500 mph, where the pistons give way to the turbines.

With the boost held the mix is 0.0 to 0.3 LU louder again (it is at its limiters) and brighter: 1.5-5 kHz +0.7 to +3.4 dB,
over 5 kHz +3.4 to +5.6 dB. The light-up's first 0.6 s stands 1.4 LU (3,000 mph), 2.5 LU (5,000) and 2.2 LU (7,000) over
the same moment without the voice. The recorded mix peaks at -0.3 dBFS with and without it (the Master bus's limiter):
nothing clips. The strongest steady tone the mix has between 1.5 and 7 kHz still stands 18 to 22 dB over the mix round it
(30 to 35 dB without the voice).

The aim was a voice that is plainly there when the ramjet lights and that, held for minutes, is about as loud as what
the game already plays at its loudest (the burner and the V8 at 3,000 mph: -9.2 to -9.5 LUFS; the ramjet with its voice
at 7,000 mph: -8.8).
