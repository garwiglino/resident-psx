#pragma once
#include "spu_dsp.h"

// Independent implementation of the register arithmetic documented by PSX-SPX,
// SPU Volume and ADSR Generator. Every call represents one 44,100 Hz SPU tick.
namespace psx_spu {
struct EnvelopeClock {
    uint32_t counter=0;
    bool tick(int &level,int shift,int step_bits,bool decreasing,bool exponential,
              bool negative=false,int rate_mask=127) {
        int step=7-step_bits;
        negative=negative&&!(decreasing&&exponential);
        if(decreasing!=negative)step=~step;
        step*=1<<std::max(0,11-shift);
        uint32_t increment=0x8000u>>std::max(0,shift-11);
        if(exponential&&!decreasing&&level>=0x6000){
            if(shift<10)step>>=2;
            else if(shift>=11)increment>>=2;
            else{step>>=1;increment>>=1;}
        }else if(exponential&&decreasing){step=mul(step,level);}
        if((step_bits|(shift<<2))!=rate_mask)increment=std::max(increment,1u);
        counter+=increment;
        if(!(counter&0x8000))return false;
        counter=0;
        int next=level+step;
        if(!decreasing)level=std::clamp(next,-32768,32767);
        else if(negative)level=std::clamp(next,-32768,0);
        else level=std::max(next,0);
        return true;
    }
};

struct Envelope {
    enum Phase { OFF,ATTACK,DECAY,SUSTAIN,RELEASE };
    uint16_t adsr1=0x00ff,adsr2=0x1fc0;
    Phase phase=OFF;
    int level=0;
    EnvelopeClock clock;
    void key_on(uint16_t first,uint16_t second){adsr1=first;adsr2=second;level=0;phase=ATTACK;clock.counter=0;}
    void key_off(){if(phase!=OFF&&phase!=RELEASE){phase=RELEASE;clock.counter=0;}}
    void tick(){
        switch(phase){
        case ATTACK:
            clock.tick(level,(adsr1>>10)&31,(adsr1>>8)&3,false,adsr1&0x8000);
            if(level==32767){phase=DECAY;clock.counter=0;}
            break;
        case DECAY:
            clock.tick(level,(adsr1>>4)&15,0,true,true,false,60);
            if(level<=((adsr1&15)+1)*0x800){phase=SUSTAIN;clock.counter=0;}
            break;
        case SUSTAIN:
            clock.tick(level,(adsr2>>8)&31,(adsr2>>6)&3,adsr2&0x4000,adsr2&0x8000);break;
        case RELEASE:
            clock.tick(level,adsr2&31,0,true,adsr2&0x20,false,124);
            if(level==0){phase=OFF;clock.counter=0;}
            break;
        default:break;
        }
    }
};

struct Volume {
    uint16_t reg=0x3fff;
    int level=32766;
    EnvelopeClock clock;
    void write(uint16_t value){
        if(reg==value)return;
        reg=value;clock.counter=0;
        if(!(reg&0x8000))level=int16_t(uint16_t(reg<<1));
    }
    void tick(){
        if(reg&0x8000)clock.tick(level,(reg>>2)&31,reg&3,reg&0x2000,reg&0x4000,reg&0x1000);
    }
};

struct MixerFrame {
    int left=0,right=0,send_left=0,send_right=0;
    void add(int l,int r,bool reverb){left+=l;right+=r;if(reverb){send_left+=l;send_right+=r;}}
    std::array<int16_t,2> finish(int wet_l,int wet_r,int master_l,int master_r)const{
        // Accumulate all voices in a wide integer, add reverb, THEN clamp,
        // then multiply by MVOLL/MVOLR. Never clip between individual voices.
        return {int16_t(mul(sat(left+wet_l),master_l)),int16_t(mul(sat(right+wet_r),master_r))};
    }
};
}
