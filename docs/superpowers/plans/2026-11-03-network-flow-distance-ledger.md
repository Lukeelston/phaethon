# v025 execution ledger

Base be81820, existing isolated release/experimental checkout. User praised v024
in the headset, especially Basalt/desert. Continuing delegated judgment and the
existing local build/package/playtest workflow; no original checkout changes.

Builder check: distance_builder_check found nothing important unanswered.
Ruling: a smooth cubic bow approximates the requested exponential-looking climb
while preserving the varied existing launch heights and exact lip derivatives.
Several existing mean slopes exceed lip slopes, making an everywhere-convex
exponential mathematically impossible without changing their ballistic flights.
Keep lateral transfer bends and side-road hills, remove transfer vertical waves.

RED: original launches failed all20 continuous-climb checks and recovery descent
failed. GREEN: ten profile and five rhythm tests pass after exact derivative keys.
Independent JS/GD generator blocks regenerated from design_network.py.

Ruling: full traversal found J5 minimum3250mph missed by ~0.31m due to changed
finite-step launch vz (256.20684 vs256.29398m/s). Extend the existing7m catch
entry margin to all longer flights, previously only slower ones. This lowers
some long-flight receiving decks4m; lip heights/angles, gaps and posted minimums
remain unchanged. JS60trials plusfour complete transfer routes pass afterward.

Distance: full road detail26km (was20), distant coarse pavement100km, terrain
RANGE8/MAX289 (was5/121); 96groves/tile with highway-adjacent inhabited clusters.
Props prebuilt4tiles out and shader-faded22–30km; terrain/water fade54–64km.
All creation fades last1.8seconds. Coarse road decks8m below detail to contain
chord errors; transforms move one static parent rather than hundreds of meshes.

Review: distance_final_review identified first-frame prop flash and incomplete
performance warmup. New batches now start reveal0 before entering scene;
actual renderer test covers first frame/half fade/full fade. Water fades too.
Added settled benchmark with4000warmup iterations and explicit ready/count logs.
v024 pristine source copied from be81820 into ignored .tools/v025-baseline-project;
no original worktree touched. Renderer instances serialized throughout.

Preliminary cold-start route: v024 streamCPUmean3.985ms, v0255.146ms; cannot call
this a fully populated GPU comparison. Both have inherited mesh/sign upload
stalls ~34ms. Optional phase instrumentation found those in finish/sign, not
per-sample road geometry or new terrain. Do not claim they are fixed.

Actual regional render: nine regions and three road views passed GPU anchor
checks, terrain slices<=4.251ms, prop slices<=3.182ms. Landscape gate32checks:
118902road probes, prop supports/clearance, allfournewfamilies, bounded289tiles,
origin transform and far-road endpoints.

Final source checks: landscape33/33 including both far-road edges at both block
ends and sampled chord intrusion (maximum -6.627m below detailed deck). Actual
Vulkan first-frame/half/full creation fade5/5; three ramp snapshots inspected.
Godot60jumptrials pass after entry-margin correction; landings200positive and
8negative pass, fastcapture81cases through9000mph pass, twists4197/4197 pass.
Shaft mesh237/237 passes on actualVulkan; headless dummy renderer cannot retain
MultiMesh transforms and was not a valid way to run its GPU-readback assertions.
Junction clearance, Networkworld9, full JS/GD parity, partner recorded19529frame
replay withzerooverlaps, score display17/17 pass. Python profiles10/rhythm5 pass.

Settled performance: baseline121terrain/25decorations; v025289/81, alljobsready.
Matched moving70km route streamCPUmean3.8554->4.8990ms, renderGPU0.3591->0.4788ms.
Display-paced frame means16.722->16.674ms; p95stalls35.68->37.909ms. This mono
renderer workload excludes headset stereo, physics and traffic. User VR feel
remains pending; inherited road mesh/sign upload stalls remain explicitly open.

Source checkpoint f42ff93. Both exports completed; freshly extracted desktop
186/186 and PCVR XR-off305/305 diagnostics passed. Both42file archives validated,
and all14 historical/current ZIP hashes verified. RELEASE_REPORT.txt contains
exact artifacts and performance measurements; evidence/v025-performance.json
retains full benchmark summaries.

Fresh-extracted PCVR0.2.5 launched as PID24360 withNetwork selected and partner
enabled. Oculus OpenXR initialized; main menu ready, runtime currently IDLE
awaiting headset wake. Asynchronous ramp/distance/frame-pacing feedback requested.
Physical headset outcome remains unverified - needs user confirmation.
All bounded test/export helpers exited; only requested interactive game retained.
No push/merge/store update. Original and Claude checkouts untouched.
