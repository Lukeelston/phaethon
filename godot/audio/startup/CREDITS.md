# Start-up sounds

Baked by `tools/startup_audio_bake.py` from field recordings published on Freesound (https://freesound.org), every one under
Creative Commons 0 (public domain dedication, https://creativecommons.org/publicdomain/zero/1.0/): no attribution is required,
and it is given here anyway. The sources are the site's high-quality previews, kept in `tools/audio_src/startup` so the bake
can be run again. Fetched 2026-11-21; each licence was read from the sound's own page that day.

| Freesound id | By | Title | Used for |
|---|---|---|---|
| [188194](https://freesound.org/s/188194/) | SpliceSound | Heavy metal light switch, flipping.wav | the BATT and ENGINE toggles |
| [795663](https://freesound.org/s/795663/) | TheTechTinkerer | toggle switch 1 | the PARK paddle |
| [451933](https://freesound.org/s/451933/) | kyles | switch big breaker metal click on, off.flac | the parking brake's latch, on and off |
| [47988](https://freesound.org/s/47988/) | vibe_crc | zippo_light_5shots.wav | the ENGINE guard, lifted and fallen shut |
| [615298](https://freesound.org/s/615298/) | bog.dan.0 | Big heavy button press | the START button |
| [870770](https://freesound.org/s/870770/) | CHallSmith | Electrical Relays, Very Large, Close and | the battery contactor, closing and opening |
| [679204](https://freesound.org/s/679204/) | shdwtek | 12 Volt Solenoid Clicks | the starter solenoid, and a refused control's knock |
| [732705](https://freesound.org/s/732705/) | tt_runscript | 1U Rackmount Server Fan | the fans winding up and down with the bus, and their loop |
| [23216](https://freesound.org/s/23216/) | Noizemaker | NZP BMW 1150GS Fuel pump.wav | the fuel pumps priming |
| [879806](https://freesound.org/s/879806/) | Qvantor | Airplane Cabin Chime | the self-test and turbine chime |
| [398274](https://freesound.org/s/398274/) | FlashTrauma | Electricity | the binder's first sparks |
| [675760](https://freesound.org/s/675760/) | craigsmith | S16-18 Tesla coil sparking and humming.wav | the binder's buzz |
| [733737](https://freesound.org/s/733737/) | chungus43A | 60Hz electrical mains hum | the binder's hum |
| [750486](https://freesound.org/s/750486/) | Nomracer | Fuel pump | an engine's start: its ignition relays and fuel pump priming |
| [125401](https://freesound.org/s/125401/) | jasonLON | Electric Motor Whir.aif | an engine's start: the pre-starter whine (a small motor run up to speed) |
| [478597](https://freesound.org/s/478597/) | Kinoton | Car, BMW M6, Start, Idle, Accelerate | an engine's start: its starter, the engine turning under it, and the weight under its catch |
| [564373](https://freesound.org/s/564373/) | JaimeLopes | Lambo Start Up Sound | an engine catching: it fires, flares and settles |
| [131302](https://freesound.org/s/131302/) | reg7783 | release_air_pffft.wav | the parking brake's air |
| [438252](https://freesound.org/s/438252/) | craigsmith | G20-37-Buzzer Bursts.wav | a refused control's buzzer |

The four that make an engine's start were fetched 2026-11-22 for the staged start (Luke: "a staged supercar style start -
Brief pre-starter whine, then starter engage"); their licences were read from their own pages that night. They replaced a car
that would not start (32416), a five-litre V8's cold start (700655) and a truck's (328224, still the ground-power cart's
idle: `tools/pad_audio_bake.py`), whose recordings are kept in `tools/audio_src/startup` for the old bank.

Nothing here is synthesised. The whine is the motor's own run-up with a tape's speed-up laid over it (it plays at 0.56 of its
speed at first and reaches full speed in half a second), which is processing, not synthesis. Lengths, peaks and loudness are
measured; none of it had been judged by ear when this was written.
