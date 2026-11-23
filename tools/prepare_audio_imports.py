"""Keep engine loop frame counts valid: imported resources must be mono PCM16.
(The ramjet's bank, godot/audio/ramjet, is read the same way by EngineAudio and is kept the same way.)"""
from pathlib import Path
import wave
root = Path(__file__).resolve().parents[1]
files = list((root/'godot/audio/engines').glob('*.wav')) + list((root/'godot/audio/ramjet').glob('*.wav'))
files += list((root/'godot/audio/fleet').glob('*/*.wav'))
for wav in files:
    with wave.open(str(wav)) as source:
        assert source.getnchannels() == 1 and source.getsampwidth() == 2, wav.name
    settings = wav.with_suffix('.wav.import')
    text = settings.read_text(encoding='utf-8')
    text = text.replace('compress/mode=2', 'compress/mode=0')
    assert 'compress/mode=0' in text, wav.name
    settings.write_text(text, encoding='utf-8', newline='\n')
print(f'Validated {len(files)} mono PCM16 WAVs; imports preserve PCM16.')
