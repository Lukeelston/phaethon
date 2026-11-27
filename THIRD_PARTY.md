# Phaethon third-party notices

These credits accompany the Windows Desktop and Windows PC VR editions. The `licenses/` folder beside this file contains the full notices and licence texts referenced below.

## Sound recordings

### Start-up and preflight

Phaethon uses excerpts from the 19 Freesound sources below. Each author published the sound under the [CC0 1.0 Universal public domain dedication](https://creativecommons.org/publicdomain/zero/1.0/). The game trims, layers and levels the sources into the start-up sound bank. Each ID links to the original sound and its licence.

| Freesound ID | Recordist | Original title | Use in Phaethon |
| --- | --- | --- | --- |
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
| [125401](https://freesound.org/s/125401/) | jasonLON | Electric Motor Whir.aif | an engine's start: the pre-starter whine |
| [478597](https://freesound.org/s/478597/) | Kinoton | Car, BMW M6, Start, Idle, Accelerate | an engine's start: its starter, and the weight under its catch |
| [564373](https://freesound.org/s/564373/) | JaimeLopes | Lambo Start Up Sound | an engine catching: it fires, flares and settles |
| [131302](https://freesound.org/s/131302/) | reg7783 | release_air_pffft.wav | the parking brake's air |
| [438252](https://freesound.org/s/438252/) | craigsmith | G20-37-Buzzer Bursts.wav | a refused control's buzzer |

### The ramjet

`tools/ramjet_bake.py` bakes the ramjet's voice from two recordings of rocket engines. The bake cuts them, runs them slower as a tape is run slower (pitch and pace together), filters, levels and loops them. The two loops are also treated so that each crack's edge stands harder: every frequency's phase is turned by one angle, which leaves the spectrum as it was, and the wave is leaned, each part of it moved by up to three samples in proportion to its own pressure, as loud sound leans itself in air. Nothing in the six WAVs in `audio/ramjet/` is synthesised.

| Source | Recordist or owner | Terms | Use in Phaethon |
| --- | --- | --- | --- |
| [Freesound 220127](https://freesound.org/s/220127/), shuttlelaunch.wav | klangfabrik, a re-edit of NASA’s public-domain recordings of Space Shuttle launches | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) | the ramjet’s roar, the thump as it lights, the weight under its shut-down |
| [RS-25 Engine Test 2025-11-12](https://images.nasa.gov/details/SSC_2025-11-12_RS-25_Engine_Test), NASA Image and Video Library | NASA Stennis Space Center | NASA’s own film. NASA content is generally not subject to copyright in the United States. [NASA media usage guidelines](https://www.nasa.gov/nasa-brand-center/images-and-media/) | the ramjet’s tear (the engine’s crackle, four octaves down), the engine catching as it lights, its cut-off as it is shut down |

NASA does not endorse Phaethon, and nothing here should be read as its endorsement.

### Raid sounds

The raid's flyers and four craft's weapons play sounds that `godot/audio/raid_sounds.gd` makes in the game as a flight with raids loads (with raids off the weapons keep the turret's own synthesised sounds), from recordings already listed here: nothing new was downloaded for them. It cuts the recordings, runs them faster or slower as a tape is run (pitch and pace together), layers them and shapes their rise and fall, and lays a slow swell in level over two of the loops. Each recording keeps its credit and terms where its bank lists it: [the start-up recordings](godot/audio/startup/CREDITS.md), [the ramjet's](godot/audio/ramjet/CREDITS.md) and [the engines' piano](godot/audio/engines/CREDITS.md).

| Raid sound | Made from |
| --- | --- |
| The drones' whine | jasonLON, [Electric Motor Whir.aif](https://freesound.org/s/125401/), and tt_runscript, [1U Rackmount Server Fan](https://freesound.org/s/732705/), as the garage door's motor and the start-up's fans (CC0) |
| The gunship's drone | the same fan and motor, slowed, over klangfabrik's [shuttlelaunch.wav](https://freesound.org/s/220127/) (CC0), as the ramjet's roar |
| The gunship's shot | the shuttle launch's ignition thump and NASA's RS-25 film, as the ramjet's light-up; kyles, [switch big breaker metal click on, off.flac](https://freesound.org/s/451933/) (CC0); the engines' bang (Salamander Grand Piano V3, CC BY 3.0) |
| The Shrike's missiles leaving | the breaker; reg7783, [release_air_pffft.wav](https://freesound.org/s/131302/) (CC0); the ramjet's RS-25 crackle and light-up |
| The Kiln's lance | FlashTrauma, [Electricity](https://freesound.org/s/398274/), craigsmith, [S16-18 Tesla coil sparking and humming.wav](https://freesound.org/s/675760/), and chungus43A, [60Hz electrical mains hum](https://freesound.org/s/733737/) (CC0), as the start-up's arc |
| The Vesper's pulse | the ramjet's light-up and cut-off (the shuttle launch and the RS-25), the engines' bang (CC BY 3.0) and the air valve |
| An Orrery orb's strike | the breaker, the start-up's arc and SpliceSound, [Heavy metal light switch, flipping.wav](https://freesound.org/s/188194/) (CC0) |

### Engine loops and one-shots

Alexander Holm recorded the Yamaha C5 for **Salamander Grand Piano V3**. Roberto assembled the SFZ+FLAC V3+20200602 edition for FreePats. The recordings carry [Creative Commons Attribution 3.0 Unported](https://creativecommons.org/licenses/by/3.0/). [Original sound bank](https://freepats.zenvoid.org/Piano/acoustic-grand-piano.html)

Phaethon resamples, granulates, layers, filters, saturates and loops the recordings. Hammer strikes supply combustion pulses and pops, sustained notes supply turbine and rotor tones, and damper releases supply noise and crackle. Band-limited copies support shifts in pitch through the overdrive range. The 33 adapted WAVs in `audio/engines/` are distributed under CC BY 3.0. The game’s general terms do not limit those permissions. See [licence](licenses/CC-BY-3.0.txt) and [original attribution](licenses/SALAMANDER_SOURCE_README.txt).

## Lettering

| Typeface | Where it appears | Credit and licence |
| --- | --- | --- |
| Roadgeek 2014 Series D and Series E(M) | Highway boards and exit signs use the two bundled fonts. Shrike’s livery also uses Roadgeek lettering. | Copyright 2015 Sammi De Guzman. [MIT licence](licenses/ROADGEEK-2014.txt) · [Project](https://github.com/sammdot/roadgeek-fonts) |
| Inter | The cockpit’s gauge faces, odometer strip and overhead switch legends use rendered lettering. | Copyright 2016 The Inter Project Authors. [SIL Open Font License 1.1](https://github.com/rsms/inter/blob/master/LICENSE.txt). Godot’s built-in font notices and the full OFL text are also in [Godot’s copyright inventory](licenses/GODOT_COPYRIGHT.txt). |

## Engine and XR

**Godot Engine 4.7.1-stable** uses the MIT licence. Copyright 2014–present Godot Engine contributors and 2007–2014 Juan Linietsky and Ariel Manzur. The matching [engine licence](licenses/GODOT_LICENSE.txt) and [third-party copyright inventory](licenses/GODOT_COPYRIGHT.txt) ship with the game. The inventory includes the engine’s fonts, codecs, rendering libraries and platform dependencies, each under its own terms. [Godot licensing](https://godotengine.org/license/)

**OpenXR Loader** is part of Godot’s native PC VR support. The engine inventory identifies the Khronos loader under Apache License 2.0, copyright 2020–2025 The Khronos Group Inc. See the `thirdparty/openxr/*` entry and Apache licence text in [Godot’s copyright inventory](licenses/GODOT_COPYRIGHT.txt).

**Godot OpenXR Vendors 5.2.0** is used in the separate Quest development project. The Windows Desktop and Windows PC VR packages use Godot’s built-in support and ship without this GDExtension or its vendor binaries. The wrapper uses MIT. The Android XR, Khronos, Magic Leap and PICO components and Meta’s loader carry Apache 2.0. Meta’s SDK carries the Oculus SDK License Agreement. The installed plugin identifies these terms in the individual vendor folders, including `meta/LICENSE-LOADER` and `meta/LICENSE-SDK`. [Plugin source and licence](https://github.com/GodotVR/godot_openxr_vendors) · [Oculus SDK terms](https://developer.oculus.com/licenses/oculussdk/)

## Roadside scenery

The Phaethon roadside pack contains 18 original designs with close-up and distance models (36 meshes). Its generators produce the buildings, fuel plaza, turbine, vegetation, rocks, fuel-station lettering and both surface atlases. The pack’s source documents and generators identify no outside models, images, fonts or recordings. It carries no separate public asset licence. The editable sources and provenance are maintained with the roadside pack.

## Starting-pad ground crew

The following [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) recordings supply the positional pad sounds. The reproducible edits are in `tools/pad_audio_bake.py`. The sixteen stations key different rhythms on a recorded buzzer and each ends its clearance call on a higher note.

| Pad sound | Original Freesound recordings |
| --- | --- |
| Ground-power cart | danshousestudio, [Truck starting.wav](https://freesound.org/s/328224/), its idling engine, and tt_runscript, [1U Rackmount Server Fan](https://freesound.org/s/732705/), its cooling fan. Both excerpts loop. |
| Lead coming free and hitting the deck | shdwtek, [12 Volt Solenoid Clicks](https://freesound.org/s/679204/), kyles, [switch big breaker metal click on, off.flac](https://freesound.org/s/451933/), and vibe_crc, [zippo_light_5shots.wav](https://freesound.org/s/47988/), layered into a latch snap, impact and bounce. |
| Gate mechanism | shdwtek’s [solenoid](https://freesound.org/s/679204/), Noizemaker, [NZP BMW 1150GS Fuel pump.wav](https://freesound.org/s/23216/), and CHallSmith, [Electrical Relays, Very Large, Close and](https://freesound.org/s/870770/), for the contactor, drive motor and end stop. |
| Station clearance | craigsmith, [G20-37-Buzzer Bursts.wav](https://freesound.org/s/438252/), filtered, cut and repitched for the station horn. |

The review recording `docs/glacier-pad-preflight.wav` captures Godot’s stereo Master output. Its cockpit sounds and Alexander Holm’s Salamander piano recordings carry the credits listed under **Sound recordings** above.
