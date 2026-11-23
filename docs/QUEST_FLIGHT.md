# Quest 3 standalone flight test

The Android test package is `com.elstonworks.phaethon.questtest`. It starts in the course menu. The Range starts with foveation off, full eye images and 4× MSAA. Each app launch resets the test to this baseline.

1. Finish the current session and leave Quest Link. Enable developer mode on the Quest, plug it into your trusted PC and approve its USB-debugging prompt. Run `adb devices -l` and copy the Quest serial from a row in the `device` state.
2. From this worktree run `adb -s SERIAL install -r build/quest/PhaethonQuestFlight.apk`. Open **Phaethon Quest Test** under **Unknown Sources**, start **The Range**, then start `python tools/quest_perf.py capture --serial SERIAL --minutes 10 --output build/quest/flight-001.log` on the PC. Pick a new log filename for each run.
3. Every 100 seconds tap the left **Menu**, select **Quest Graphics** with **A**, use the right stick and **A** to change one setting, then press **B** to fly. Follow the six settings below on the same stretch of the Range. Capture prints the grouped results and saves the original log.

| Start | Foveation | Eye scale | MSAA |
| --- | --- | --- | --- |
| 0:00 | Off | 1.0 | 4× |
| 1:40 | Medium | 1.0 | 4× |
| 3:20 | Medium | 0.8 | 4× |
| 5:00 | Medium | 0.7 | 4× |
| 6:40 | Medium | 0.7 | 2× |
| 8:20 | Medium | 0.7 | Off |

Godot submits a centered OpenXR projection subimage at each eye scale. The swapchain retains its full allocation so the pilot can change settings in flight. An Android reader checks both eye rectangles in the actual OpenXR composition layer. `QUEST_SETTINGS` records the requested scale, allocation and observed image dimensions. `QUEST_PERF` groups active flight by observed width and height, foveation level and viewport MSAA. Flight Hold, loss of focus and a one-second settling interval reset the window. Missing GPU timestamps are excluded. A rendered five-second window after eye readback is required to produce a sample. The capture does not alter headset graphics settings.

To reopen a capture, run `python tools/quest_perf.py summary build/quest/flight-001.log`. FPS uses total frames divided by total time, and GPU milliseconds are weighted by valid timestamp count. The same command reads the original November 20 two-line Godot format and labels its unrecorded settings as unknown.

## Rebuilding offline

Run the export on Windows with Godot 4.7.1, JDK 17 or 21, the cached Gradle distribution/dependencies and the Android SDK packages used in the original test. The template uses platform 36, build-tools 36.1.0 and NDK 29.0.14206865. Supply the original 4.7.1 Android export templates, an existing local debug keystore and the original test's Godot project containing `android/` and `addons/godotopenxrvendors/` (5.2.0). The wrapper imports, tests and exports in an isolated staging directory. It substitutes an empty device list for Godot's automatic adb discovery. Signing uses the local test key.

```powershell
.\tools\quest-export.ps1 -QuestProject $questProject -Sdk $sdk -Godot $godotExe -Templates $androidExportTemplates -DebugKeystore $debugKey
```

`-Templates` is the directory containing `android_debug.apk`. The native readback uses the Khronos 1.1.54 headers in the cached Android loader. Supply an equivalent include directory via `-OpenXRHeaders` if needed. The wrapper enables ETC2/ASTC texture import in the staged Android project. The Windows project keeps its normal desktop texture formats. The script checks both mobile texture formats in the APK, its signature and its 16 KiB native-library alignment before writing `build/quest/PhaethonQuestFlight.apk`. SDK binaries, the vendor plugin and signing material stay local.
