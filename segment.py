# Beat tracking example
from __future__ import print_function
import librosa

# 1. Get the file path to the included audio example
filename = "beets.wav"

# 2. Load the audio as a waveform `y`
#    Store the sampling rate as `sr`
y, sr = librosa.load(filename)

# 3. Run the default beat tracker
segments = librosa.effects.split(y, top_db=10, frame_length=2048, hop_length=512)

#print(segments)
i = 0
for samp in segments:
    print(samp)
    triggertime = str(int(1000*samp[0]/float(sr)))
    librosa.output.write_wav("beat" + triggertime + ".wav", y[samp[0]:samp[1]], sr, norm=False)