"""Original 96 BPM score, sharing the sound palette of the approved App Store cut."""
import wave
import numpy as np


def compose(path, duration=60):
    sr=48000
    n=int((duration+3)*sr)
    dry=np.zeros((n,2)); pad=np.zeros_like(dry)
    rng=np.random.default_rng(27092026)
    def hz(m): return 440*2**((m-69)/12)
    def add(bus,s,start,gain,pan=0):
        i=int(start*sr); end=min(n,i+len(s)); angle=(pan+1)*np.pi/4
        if end<=i:return
        bus[i:end,0]+=s[:end-i]*gain*np.cos(angle)
        bus[i:end,1]+=s[:end-i]*gain*np.sin(angle)
    def piano(m,length=4.,v=.65):
        t=np.arange(int(length*sr))/sr; s=np.zeros_like(t)
        for k,a in enumerate([1,.36,.13,.07,.032,.014],1):
            f=hz(m)*k*np.sqrt(1+.00008*k*k)
            tau=(2.1 if m<60 else 1.45)/(1+.32*(k-1))
            s+=a*np.exp(-t/tau)*(np.sin(2*np.pi*f*t)+.24*np.sin(2*np.pi*f*1.0009*t+.15))
        env=(1-np.exp(-t/.007))*np.minimum(1,(length-t)/.12)
        return (s*env+rng.normal(0,.018,len(t))*np.exp(-t/.012))*v
    D=[50,57,61,64,66]; B=[47,54,57,61,66]; G=[43,50,54,57,62]; A=[45,52,57,59,64]
    progression=[D,B,G,A,G,D] if duration<=30 else [D,B,G,A,D,B,G,A,B,G,A,D]
    end_note=duration-2.5
    for ci,notes in enumerate(progression):
        start=ci*5; t=np.arange(7*sr)/sr
        env=np.minimum(1,t/.9)*np.minimum(1,np.maximum(0,7-t)/2.1)
        for j,m in enumerate(notes[1:]):
            f=hz(m)
            s=(np.sin(2*np.pi*f*t)+.2*np.sin(2*np.pi*2*f*t)+.1*np.sin(2*np.pi*3*f*t))
            add(pad,s*env*(.9+.1*np.sin(2*np.pi*.21*t+j)),start,.012,-.6+j*.4)
        add(dry,piano(notes[0],4.5),start,.14,-.05)
        for k,j in enumerate([1,3,2,4,1,3,2,4]):
            when=start+k*.625
            if when>=end_note:continue
            m=notes[j]+(12 if k==3 and ci%4==1 else 0)
            add(dry,piano(m,v=.6+.09*(k%3)),when,.095 if k%2==0 else .066,[-.28,.22,-.1,.32][k%4])
        # A second melodic voice enters in the middle act and resolves in the final act.
        if duration>30 and 4<=ci<=9:
            for k,j in enumerate([4,3,2]):
                add(dry,piano(notes[j]+12,3.2,.48),start+1.25+k*1.25,.047,(-.35 if k%2 else .35))
    for b in range(8,int(end_note/.625)):
        t=np.arange(int(.2*sr))/sr
        if b%2==0:
            phase=np.cumsum(48+56*np.exp(-t/.022))*2*np.pi/sr
            add(dry,np.sin(phase)*np.exp(-t/.05)*(1-np.exp(-t/.002)),b*.625,.058)
        else:
            noise=np.concatenate(([0],np.diff(rng.normal(0,1,len(t)))))
            add(dry,noise*np.exp(-t/.023)*(1-np.exp(-t/.002)),b*.625,.007,.35 if b%4==1 else -.35)
    for j,m in enumerate([50,57,61,66,74]):add(dry,piano(m,4.8),end_note+j*.034,.078,-.3+j*.15)
    ir=np.zeros((int(2.5*sr),2))
    for c in range(2):
        for _ in range(900):
            t=rng.uniform(.027,2.5)
            ir[int(t*sr),c]+=rng.normal()*np.exp(-t/.58)*.011
        for t,g in [(.067,.11),(.101,.07),(.163,.035)]:ir[int((t+c*.008)*sr),c]+=g
    size=1<<int(np.ceil(np.log2(n+len(ir)-1)))
    f=np.fft.rfft(dry.mean(axis=1),size)
    for c in range(2):pad[:,c]+=np.fft.irfft(f*np.fft.rfft(ir[:,c],size),size)[:n]
    mix=dry[:int(duration*sr)]+pad[:int(duration*sr)]
    t=np.arange(len(mix))/sr
    mix*= (np.minimum(1,t/.12)*np.minimum(1,np.maximum(0,duration-t)/1.5))[:,None]
    mix=np.tanh(mix*1.25);mix*=.8/max(np.max(np.abs(mix)),1e-8)
    with wave.open(str(path),'wb') as w:
        w.setnchannels(2);w.setsampwidth(2);w.setframerate(sr)
        w.writeframes((mix*32767).astype('<i2').tobytes())
