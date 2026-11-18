"""Synthesize original, deterministic underwater ambience and interface sounds."""
import math,random,struct,wave
from pathlib import Path
root=Path(__file__).resolve().parents[1]/'game/assets/audio'
root.mkdir(parents=True,exist_ok=True)
random.seed(613)
sr=22050

def write(name,duration,fn):
    with wave.open(str(root/(name+'.wav')),'w') as w:
        w.setnchannels(1);w.setsampwidth(2);w.setframerate(sr)
        data=bytearray()
        for i in range(int(sr*duration)):
            t=i/sr
            v=max(-1,min(1,fn(t,duration)))
            data.extend(struct.pack('<h',int(v*32767)))
        w.writeframes(data)
write('ocean',16,lambda t,d:(math.sin(t*math.tau*42)*.07+math.sin(t*math.tau*63)*.025+math.sin(t*math.tau*84)*.013)*(0.8+0.2*math.sin(t*math.tau/16)))
write('sonar',1.8,lambda t,d:math.sin(t*math.tau*(950-80*t))*math.exp(-t*3.5)*.16)
write('click',.12,lambda t,d:math.sin(t*math.tau*700)*math.exp(-t*60)*.15)
write('build',.65,lambda t,d:(math.sin(t*math.tau*330)+math.sin(t*math.tau*495)+math.sin(t*math.tau*660))*.05*math.sin(math.pi*t/d)**2)
write('alert',1,lambda t,d:math.sin(t*math.tau*(440 if t<.45 else 330))*.12*math.sin(math.pi*t/d)**2)
write('research',1.2,lambda t,d:(math.sin(t*math.tau*440)+math.sin(t*math.tau*550)+math.sin(t*math.tau*660))*.04*math.sin(math.pi*t/d)**2)
print('Original audio generated:',len(list(root.glob('*.wav'))))
