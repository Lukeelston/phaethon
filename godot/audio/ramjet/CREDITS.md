# The ramjet's voice

Baked by `tools/ramjet_bake.py` (run `python -I tools/ramjet_bake.py`) from two recordings of real rocket engines, kept in
`tools/audio_src/ramjet` so the bake can be run again. Fetched 2026-11-22; the licence of each was read from its own page
that day.

| Source | By | Terms | Used for |
|---|---|---|---|
| Freesound [220127](https://freesound.org/s/220127/), "shuttlelaunch.wav" (the site's high-quality preview, 132 s) | klangfabrik: by its own page, a re-edit of NASA's public-domain recordings of Space Shuttle launches, the commentary cut out | Creative Commons 0 (https://creativecommons.org/publicdomain/zero/1.0/): no attribution is required, and it is given here anyway | the roar's loop (35 s to 43 s of it), the light-up's thump and low swell (its first three seconds), the weight under the shut-down (36 s to 37 s) |
| NASA Image and Video Library, [SSC_2025-11-12_RS-25_Engine_Test](https://images.nasa.gov/details/SSC_2025-11-12_RS-25_Engine_Test), "RS-25 Engine Test 2025-11-12" | NASA Stennis Space Center: RS-25 engine no. 20002 run for 500 s, to 111% power, on the Fred Haise Test Stand | NASA's own film: "generally ... not subject to copyright in the United States" (https://www.nasa.gov/nasa-brand-center/images-and-media/). NASA asks that its material not be used to suggest it endorses anything: it does not endorse this game | the tear's loop (three quarters of a second of the film, from 163 s), the engine's crackle in the light-up (under half a second, from 11.6 s) and in the shut-down (a third of a second, from 515.7 s, and its thump at 510 s) |

The NASA film's sound was taken from the library's "medium" copy (AAC, 48 kHz, 160 kb/s; the two channels are the same) in
three stretches, with `ffmpeg -ss START -i URL -t SECONDS -vn -c:a copy` (4 s + 44 s, 128 s + 50 s, 498 s + 30 s), and
those are kept as mono Vorbis (`ffmpeg -ac 1 -c:a libvorbis -q:a 7`). No picture was kept.

Nothing here is synthesised. What is done to the recordings: they are cut, and run slower as a tape is run slower, pitch
and pace together (the roar 1.3 times, the tear 11 times: three and a half octaves down; the test engine in the light-up
and the shut-down 4 times; the ignition thump 1.3 times); the roar loses what lies under 40 Hz and the tear is the test
engine's 0.5 to 14 kHz; the loops' slow swells are levelled and their ends folded into their beginnings; the tear's tallest
peaks are held 13 dB over its rms, as the roar's own are; the shut-down is slowed further as it falls (to 0.6 of its speed
in 0.8 s); the right engine's light-up and shut-down are the left's played 3.5% slower. The game then plays the loops
faster with speed (the roar x0.92 to x1.08, the tear x0.85 to x1.2) and sets every level (`audio/engine_audio.gd`, the
`ram_*` lines of `TUNE`).

Lengths, seams, levels and loudness are measured (the bake prints them and fails on a seam that shows;
`tools/engine_audio_check.py` measures the voice in recordings of the game). None of it had been judged by ear when this
was written.

## Its pitch (2026-11-22, second cut)

Its first cut (commit `b9fdb91`) kept the test engine's crackle where it was recorded, 0.5 to 8 kHz, over a roar at 110 Hz
to 1.5 kHz. Luke flew it: "I like the ramjet sound, but I feel like it's a few octaves too high. It's correct on the
ripping/shredding sound", and pointed at the raw sound of a launch for what he meant. That recording is someone else's and
none of it is here; it was measured, and this cut was made toward the measurements:

| | half the energy under | centroid | 90% under | hard peaks a second | the loudness flutters at |
|---|---|---|---|---|---|
| the launch he pointed at | 70 Hz | 137 Hz | 284 Hz | 16 | 50 Hz |
| the first cut, alone | 387 Hz | 1,040 Hz | 2,924 Hz | 64 | 212 Hz |
| this cut, alone | 123 Hz | 202 Hz | 434 Hz | 16 | 98 Hz |

(each voice over 18 s to 24 s of `tests/record_ramjet.gd`'s run, 6,600 to 7,600 mph). That is 1.7 octaves down by where
half the energy lies, 2.4 by the centroid and 2.8 by the 90% point, and 0.6 to 0.8 of an octave over the launch: the launch
has half its energy under 70 Hz, and a headset's own speakers give little under 90, so the tear is kept at 90 to 500 Hz
for them to play (68% of this cut's energy lies between 88 and 707 Hz). The tear itself is kept: the skewness of the
wave's rate of change is -0.40 with both engines summed (-0.32 for the first cut), -0.5 in each ear. The launch's is
-1.36: it tears harder than these recordings do (-0.7 to -0.9 a loop, before two engines' are mixed).

## How its levels were set (2026-11-22)

Not by ear. The game's own mix was recorded with the engine's movie writer (`tests/record_ramjet.gd`: the cockpit on the
range, flown as the headset's trigger scheme flies it, fourth gear, both triggers in) with the craft's speed pinned, for
the engine audio before the ramjet had a voice (`e0a2e7b`), for the first cut and for this one. Seven seconds on the
ramjet; LUFS is ITU-R BS.1770's K-weighting, ungated; "over 90 Hz" is the same with everything under 90 Hz taken off, as
a headset's speakers give it:

| Speed | The mix: no voice | first cut | this cut | this cut's mix over 90 Hz (first cut's) | The voice alone, rms: whole | over 90 Hz (first cut's) |
|---|---|---|---|---|---|---|
| 3,000 mph | -9.5 LUFS | -9.2 | -9.8 | -11.4 (-10.3) | -13.0 dB | -15.7 dB (-17.8) |
| 5,000 mph | -10.8 LUFS | -9.1 | -9.9 | -11.1 (-9.5) | -12.5 dB | -14.7 dB (-16.9) |
| 7,000 mph | -10.4 LUFS | -8.8 | -9.6 | -10.5 (-9.2) | -12.3 dB | -14.0 dB (-15.0) |

The mix's plain rms is where the first cut left it (-10.6 / -11.1 / -11.0 dB against -10.5 / -11.0 / -11.3) and it peaks at
-0.3 dBFS as before (the Master bus's limiter): nothing clips. K-weighted it reads 0.6 to 0.8 LU under the first cut, and
over 90 Hz 1.1 to 1.6 LU under it: the first cut's hiss sat where the ear, and that weighting, are keenest. Two runs of
one build differ by up to 0.8 LU where nothing changed.

Room is made for it (`TUNE.ram_duck`): under a lit ramjet the V8 plays at 0.75 of its level (-2.5 dB), the second engine
at 0.5 (-6 dB), the turbines' roar at 0.5 (-6 dB) and the burner's rumble at 0.3 (-10.5 dB; it was 0.4). Those are the
layers in its band: measured alone on the ramjet, the second engine put -17 dB into 90-180 Hz at 5,000 mph and the V8
-18 dB into every octave from 45 to 700 Hz at 3,000. With them stepped back, the voice is 80 to 100% of what the mix has
in each octave from 90 to 710 Hz at 5,000 and 7,000 mph, and 40 to 70% at 3,000 mph, where the V8 still leads. The
turbines' whine and the V12 sit over 700 Hz and are left alone. Whether the limiters pump them under the voice's crackle
was looked for in the band they are in (1.4 to 5.6 kHz): its level wanders 1.0 to 1.1 dB from one fiftieth of a second to
the next with the ramjet lit (0.9 to 1.1 dB with the first cut, 0.8 to 0.9 on the burner), and never moves against the
low band's, which is what a limiter ducking it under each peak would show as.
