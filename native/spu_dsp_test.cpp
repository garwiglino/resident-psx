#include "spu_envelope.h"
#include <iostream>
#include <cstdlib>
static void check(bool value,const char *message){if(!value){std::cerr<<message<<'\n';std::exit(1);}}
int main(){
    psx_spu::Envelope envelope;
    envelope.key_on(0x00ff,0x1fc0);
    check(envelope.level==0&&envelope.phase==psx_spu::Envelope::ATTACK,"Key-on resets ENVX and starts attack");
    envelope.tick();check(envelope.level==14336,"Fastest attack: +7 shifted by eleven");
    envelope.tick();check(envelope.level==28672,"Attack tick two");
    envelope.tick();check(envelope.level==32767&&envelope.phase==psx_spu::Envelope::DECAY,"Attack saturates and enters decay");
    for(int i=0;i<16;i++)envelope.tick();
    check(envelope.level==32767&&envelope.phase==psx_spu::Envelope::SUSTAIN,"Maximum sustain threshold transitions even between envelope rate steps");
    for(int i=0;i<100000;i++)envelope.tick();
    check(envelope.level==32767,"All-ones sustain rate holds indefinitely");
    envelope.key_off();envelope.tick();check(envelope.level==16383,"Key-off applies the first linear release step");
    envelope.tick();check(envelope.level==0&&envelope.phase==psx_spu::Envelope::OFF,"Release terminates at zero on its second fixed-point step");
    psx_spu::EnvelopeClock slow;int level=0;
    for(int i=0;i<32767;i++)slow.tick(level,31,0,false,false);
    check(level==0,"Slow rate counter waits for bit 15 rather than using frame delta");
    slow.tick(level,31,0,false,false);check(level==7,"Slow non-all-ones rate increments by at least one counter unit");
    psx_spu::EnvelopeClock exponential;level=0x6000;
    exponential.tick(level,10,0,false,true);check(level==0x6000,"Exponential attack shift 10 halves counter increment");
    exponential.tick(level,10,0,false,true);check(level==0x6007,"Exponential attack shift 10 also halves the step");
    psx_spu::EnvelopeClock decreasing;level=16384;
    decreasing.tick(level,11,0,true,true);check(level==16380,"Exponential decrease scales -8 by current ENVX");
    psx_spu::Volume sweep;sweep.write(0x4000);check(sweep.level==-32768,"Direct volume sign-extends the signed 15-bit register");
    sweep.write(0);sweep.write(0x8000);sweep.tick();check(sweep.level==14336,"Volume sweep uses the hardware envelope clock");
    psx_spu::MixerFrame mix;mix.add(30000,30000,true);mix.add(30000,30000,false);mix.add(-30000,-30000,false);
    auto mixed=mix.finish(0,0,16384,16384);
    check(mixed[0]==15000&&mixed[1]==15000&&mix.send_left==30000,"Wide signed sum preserves cancellation and independent EON sends");
    mix.add(30000,30000,false);mixed=mix.finish(0,0,16384,16384);
    check(mixed[0]==16383,"Clamp occurs before master multiplication");
    check(psx_spu::mul(-1,16384)==-1,"Negative fixed-point multiplication uses arithmetic shift");
    uint8_t block[16]={0x0c,0,0x71,0xf8};int s1=0,s2=0;int16_t decoded[28];
    psx_spu::decode_block(block,s1,s2,decoded);
    check(decoded[0]==1&&decoded[1]==7&&decoded[2]==-8&&decoded[3]==-1,"SPU signed nibbles are low-first with the correct shift");
    std::fill(std::begin(block),std::end(block),0);block[0]=0x2c;s1=1000;s2=-500;
    psx_spu::decode_block(block,s1,s2,decoded);
    check(decoded[0]==2202,"SPU predictor truncates its two signed products separately");
    int16_t impulse[4]={0,32767,0,0};
    check(psx_spu::interpolate(impulse,0)==22962,"Hardware Gaussian coefficient at phase zero");
    double signal=0,error=0;int enc1=0,enc2=0,dec1=0,dec2=0;
    for(int batch=0;batch<800;batch++){
        int16_t input[28];
        for(int i=0;i<28;i++)input[i]=int16_t(std::sin((batch*28+i)*6.283185307179586*440/22050)*16000);
        psx_spu::encode_block(input,enc1,enc2,block);
        check((block[0]>>4)<=4&&(block[0]&15)<=12,"Encoder emits legal hardware filters and shifts");
        psx_spu::decode_block(block,dec1,dec2,decoded);
        for(int i=0;i<28;i++){signal+=double(input[i])*input[i];error+=std::pow(double(input[i])-decoded[i],2);}
    }
    double snr=10*std::log10(signal/error);
    check(snr>35,"ADPCM roundtrip signal-to-noise must exceed 35 dB for the reference tone");
    psx_spu::Reverb reverb;
    for(int i=0;i<44100;i++){
        auto silence=reverb.process(0,0);check(silence[0]==0&&silence[1]==0,"Zero input must not generate reverb noise");
    }
    std::cout<<"SPU_DSP_OK: fixed-clock ADSR, release, infinite rates, signed volume/sweeps, wide mixer/clipping order, ADPCM vectors, hardware Gaussian rounding, valid blocks, SNR "<<snr<<" dB, silent reverb\n";
}
