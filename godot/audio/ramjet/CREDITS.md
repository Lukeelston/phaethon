# The ramjet's voice

Baked by `tools/ramjet_bake.py` (run `python -I tools/ramjet_bake.py`) from two recordings of real rocket engines, kept in
`tools/audio_src/ramjet` so the bake can be run again. Fetched 2026-11-22; the licence of each was read from its own page
that day.

| Source | By | Terms | Used for |
|---|---|---|---|
| Freesound [220127](https://freesound.org/s/220127/), "shuttlelaunch.wav" (the site's high-quality preview, 132 s) | klangfabrik: by its own page, a re-edit of NASA's public-domain recordings of Space Shuttle launches, the commentary cut out | Creative Commons 0 (https://creativecommons.org/publicdomain/zero/1.0/): no attribution is required, and it is given here anyway | the roar's loop (40 s to 46 s of it), the light-up's thump and low swell (its first three seconds), the weight under the shut-down (36 s to 37 s) |
| NASA Image and Video Library, [SSC_2025-11-12_RS-25_Engine_Test](https://images.nasa.gov/details/SSC_2025-11-12_RS-25_Engine_Test), "RS-25 Engine Test 2025-11-12" | NASA Stennis Space Center: RS-25 engine no. 20002 run for 500 s, to 111% power, on the Fred Haise Test Stand | NASA's own film: "generally ... not subject to copyright in the United States" (https://www.nasa.gov/nasa-brand-center/images-and-media/). NASA asks that its material not be used to suggest it endorses anything: it does not endorse this game | the tear's loop (half a second of the film, from 163.3 s), the engine's crackle in the light-up (under half a second, from 11.6 s) and in the shut-down (a third of a second, from 515.7 s, and its thump at 510 s) |

The NASA film's sound was taken from the library's "medium" copy (AAC, 48 kHz, 160 kb/s; the two channels are the same) in
three stretches, with `ffmpeg -ss START -i URL -t SECONDS -vn -c:a copy` (4 s + 44 s, 128 s + 50 s, 498 s + 30 s), and
those are kept as mono Vorbis (`ffmpeg -ac 1 -c:a libvorbis -q:a 7`). No picture was kept.

Nothing here is synthesised: every sample is one of the two recordings, cut, slowed and treated. What is done to them:

- They are cut, and run slower as a tape is run slower, pitch and pace together: the roar 1.65 times, the tear 17.5 times
  (a little over four octaves down), the test engine in the light-up and the shut-down 5.66 times, the ignition thump 1.8
  times.
- The roar loses what lies under 25 Hz, and the tear is the test engine's 0.5 to 14 kHz.
- **The turn.** Every frequency's phase in each loop is turned by one angle: the roar's by 45 degrees, the tear's by -45.
  The spectrum is not touched (no octave band moves by 0.01 dB), nor is the loudness from moment to moment; what changes
  is the shape of the wave, and with it how hard each crack's edge stands. The angle was found by measure: it is where
  the skewness of the wave's rate of change is greatest.
- **The lean.** Each part of each loop's wave is moved in time in proportion to its own pressure, by 9.5 microseconds for
  each rms of level: 39 microseconds at most in the roar, 61 in the tear (two samples, three). It is what loud sound does
  to itself in air, and how a launch comes to crackle: the wave leans until its fronts stand up. In the roar no octave band
  up to 1 kHz moves by more than 0.02 dB (2 kHz: +0.2 dB, 4 kHz: +0.3 dB).
- The loops' slow swells are levelled and their ends folded into their beginnings; the tear's tallest peaks are held 13 dB
  over its rms, as the roar's own are.
- The shut-down is slowed further as it falls (to 0.6 of its speed in 0.8 s); the right engine's light-up and shut-down
  are the left's played 3.5% slower. The light-up and the shut-down are neither turned nor leaned.

The game then plays the loops faster with speed (the roar x0.92 to x1.08, the tear x0.85 to x1.2) and sets every level
(`audio/engine_audio.gd`, the `ram_*` lines of `TUNE`).

Lengths, seams, levels and loudness are measured (the bake prints them and fails on a seam that shows;
`tools/engine_audio_check.py` measures the voice in recordings of the game). None of it had been judged by ear when this
was written.

## Its pitch (2026-11-22, second cut)

Its first cut (commit `b9fdb91`) kept the test engine's crackle where it was recorded, 0.5 to 8 kHz, over a roar at 110 Hz
to 1.5 kHz. Luke flew it: "I like the ramjet sound, but I feel like it's a few octaves too high. It's correct on the
ripping/shredding sound", and pointed at the raw sound of a launch for what he meant. That recording is someone else's and
none of it is here; it was measured, and the second cut (commit `dfde7db`: the roar 1.3 times slower, the tear 11 times,
level with the roar) was made toward the measurements, holding half its energy over 90 Hz for a headset's own speakers.

## Its pitch (2026-11-23, third cut: this one)

He heard the second cut on headphones: "It sounds better, but it could be deeper still." With headphones the judge there
was no reason left to hold its weight up, so this cut takes it down to the launch's own profile. The roar now carries the
voice (run 1.65 times slower, from the six seconds of the launch that tear hardest) and the tear sits 6 to 8 dB under it
(run 17.5 times slower).

| | a tenth of the energy under | half under | centroid | 90% under | the tear: skewness of the wave's rate of change | hard peaks a second | the loudness flutters at |
|---|---|---|---|---|---|---|---|
| the launch he pointed at | 32 Hz | 70 Hz | 137 Hz | 284 Hz | -1.36 | 16 | 50 Hz |
| the first cut, alone | 114 Hz | 387 Hz | 1,040 Hz | 2,924 Hz | -0.32 | 64 | 212 Hz |
| the second cut, alone | 59 Hz | 123 Hz | 202 Hz | 434 Hz | -0.40 (each ear -0.5) | 16 | 98 Hz |
| this cut, alone | 38 Hz | 64 Hz | 139 Hz | 308 Hz | -1.23 (each ear -1.6) | 14 | 58 Hz |

(each voice over 18 s to 24 s of `tests/record_ramjet.gd`'s run, 6,600 to 7,600 mph, the two ears summed, as the launch's
one microphone is.) Against the launch that is 0.12 of an octave under by where half the energy lies, 0.02 over by the
centroid and 0.12 over by the 90% point. Its note runs with the speed, so at a pinned 3,000 / 5,000 / 7,000 mph the half
point is 53 / 53 / 59 Hz, the centroid 118 / 120 / 128 Hz and the 90% point 255 / 267 / 278 Hz: under the launch at the
low speeds. With the boost held it is 85, 153 and 352 Hz. Each engine's loops start at a place of their own choosing every
time the game is run, and the figures move by a twentieth with that.

Nothing turned to mush on the way down: the roar is the recording under three quarters of an octave lower. It could go
further (run 1.8 times slower it has half its energy under 50 Hz), which would pass under the launch.

**The tear.** The launch tears much harder than these recordings did as they were first cut (-1.36 against -0.40). Three
things closed that. The roar comes from a harder-tearing stretch (-0.96 as cut, against -0.72). Both loops are turned
(the roar to -1.45, the tear from -1.06 to -1.59). Both are leaned (the roar to -2.04). Two engines' loops are different
stretches, so their sum tears less than either: the game's sum measures -1.23, and each ear, which hears mostly its own
engine, -1.6. The turn and the lean change the shape of the wave and nothing else that was measured; that they change
what an ear hears is not known. They are small enough to be taken out (`BODY_TURN`, `TEAR_TURN`, `LEAN_US` to 0 in the
bake) without the voice's weight moving at all.

## How its levels were set (2026-11-22, and for the third cut 2026-11-23)

Not by ear. The game's own mix was recorded with the engine's movie writer (`tests/record_ramjet.gd`: the cockpit on the
range, flown as the headset's trigger scheme flies it, fourth gear, both triggers in) with the craft's speed pinned, for
the engine audio before the ramjet had a voice (`e0a2e7b`) and for each cut. Seven seconds on the ramjet; LUFS is ITU-R
BS.1770's K-weighting, ungated; "over 90 Hz" is the same with everything under 90 Hz taken off, as a headset's speakers
give it:

| Speed | The mix: no voice | first cut | second cut | this cut | The mix over 90 Hz: second cut | this cut | The voice alone, rms: this cut (second cut) | over 90 Hz: this cut (second cut) |
|---|---|---|---|---|---|---|---|---|
| 3,000 mph | -9.5 LUFS | -9.2 | -9.8 | -10.2 | -11.4 | -12.1 | -12.6 dB (-13.0) | -17.8 dB (-15.7) |
| 5,000 mph | -10.8 LUFS | -9.1 | -9.9 | -10.4 | -11.1 | -12.1 | -12.5 dB (-12.5) | -17.5 dB (-14.7) |
| 7,000 mph | -10.4 LUFS | -8.8 | -9.6 | -10.1 | -10.5 | -11.7 | -12.0 dB (-12.3) | -16.6 dB (-14.0) |

The voice's own level is held where the second cut's was; what moved is where its energy lies. So over 90 Hz it is 2.1 to
2.8 dB under the second cut's, and still there: 23 to 27% of its energy lies between 100 and 500 Hz (-18.9 / -18.6 /
-17.7 dB at the three speeds; the second cut had 43 to 56% of its energy there). The mix's plain rms
is -10.5 / -10.7 / -10.9 dB (the second cut: -10.6 / -11.1 / -11.0) and it peaks at -0.3 dBFS (the Master bus's limiter) in
every stretch, the boost held at each of the three speeds among them: nothing clips. K-weighted the mix reads 0.4 to
0.5 LU under the second cut. Over 90 Hz it reads 0.7 to 1.2 LU under it, and 0.6 to 1.3 LU under the burner's own mix at
the same speed: on a headset's own speakers the mix now gets a little quieter as the ramjet lights, where the second cut
was level with the burner or just over it. Whole, the octave from 45 to 90 Hz is 9 dB up on the burner's at 5,000 and
7,000 mph; at 3,000 mph it is level with the burner's, where the V8 has that octave already, and three quarters of what is
in it is the voice. Two runs of one build differ by up to 0.8 LU where nothing changed.

Room is made for it (`TUNE.ram_duck`): under a lit ramjet the V8 plays at 0.75 of its level (-2.5 dB), the second engine
at 0.5 (-6 dB), the turbines' roar at 0.5 (-6 dB) and the burner's rumble at 0.3 (-10.5 dB). That was set for the second
cut and is kept for this one: nothing more is stepped back. Those are the layers in its band: measured alone on the
ramjet, the second engine put -17 dB into 90-180 Hz at 5,000 mph and the V8 -18 dB into every octave from 45 to 700 Hz at
3,000. The turbines' whine and the V12 sit over 700 Hz and are left alone. Whether the limiters pump them under the
voice's crackle was looked for in the band they are in (1.4 to 5.6 kHz): its level wanders 0.95 to 1.5 dB from one
fiftieth of a second to the next with the ramjet lit or boosted (1.0 to 1.5 dB with the second cut), and never moves
against the low band's, which is what a limiter ducking it under each peak would show as. Going into the Engines bus's
limiter (-1 dBFS) each engine's bus peaks at +1.5 to +2.8 dBFS on the ramjet and at +2.7 to +4.4 dBFS with the boost held
(the second cut: +2.5 to +2.8, and +4.4 to +5.3): the limiter is asked for no more than it was.
