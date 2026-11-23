# Fleet sound banks

The primary drives and turbines are original performances synthesized by `tools/fleet_engine_bake.py`. Shrike RS uses paired short-intake impulses, Orrery IX three rotating coil groups, Kiln Six six unevenly spaced pressure pulses, and Vesper two near-synchronous blade trains. Each performance has sample-aligned bandwidth-limited copies for playback across the rev range.

The staged starts, catches and chimes combine original synthesis with recorded machine sounds. The second-bank engagements and lift-off sounds use new edits of the same field-recording collection. The source takes include the 12 V solenoid, BMW M6 starter, fuel pump, air release, Dremel, server fan and large electrical relay. Artist credits, original recording links and CC0 terms are in [the startup recording credits](../startup/CREDITS.md). The bakes are `tools/fleet_startup_bake.py` and `tools/fleet_exhaust_bake.py`.

The four full-boost crackle loops are new cuts of the NASA Stennis RS-25 steady firing used by the original ramjet board. Each is layered over the common shuttle roar in flight. See [the ramjet recording credits](../ramjet/CREDITS.md) and `tools/fleet_ramjet_bake.py`. The common piano-derived engine layers retain [their existing credits](../engines/CREDITS.md).

After baking, import the project, run `python tools/prepare_audio_imports.py`, and reimport if the WAV import settings changed. The runtime expects mono PCM16 for loop frame counts. Run `res://tests/test_fleet_audio.gd` to exercise craft selection and playback routing.
