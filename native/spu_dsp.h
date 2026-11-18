#pragma once
#include "spu_tables.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <vector>

// Independent implementation of the documented SPU sample/DSP arithmetic.
// No emulator sources are included. Coefficients describe the PS1 hardware.
namespace psx_spu {
inline int16_t sat(int64_t n){return int16_t(std::clamp<int64_t>(n,-32768,32767));}
inline int mul(int a,int b){return int((int64_t(a)*b)>>15);}
inline constexpr int filters[5][2]={{0,0},{60,0},{115,-52},{98,-55},{122,-60}};

inline void decode_block(const uint8_t *block,int &s1,int &s2,int16_t *out){
    int shift=block[0]&15,filter=(block[0]>>4)&15;
    if(shift>12)shift=9;
    if(filter>4)filter=0;
    for(int i=0;i<28;i++){
        int nibble=(block[2+i/2]>>((i&1)*4))&15;
        if(nibble>=8)nibble-=16;
        int prediction=((s1*filters[filter][0])>>6)+((s2*filters[filter][1])>>6);
        int sample=sat(((nibble*4096)>>shift)+prediction);
        out[i]=int16_t(sample);s2=s1;s1=sample;
    }
}

inline void encode_block(const int16_t *input,int &s1,int &s2,uint8_t *out){
    int64_t best_error=INT64_MAX;
    std::array<uint8_t,16> best{};
    int best_s1=s1,best_s2=s2;
    // Filter and shift are selected per 28-sample block. The error is measured
    // against the *decoded* history, so predictor error cannot accumulate.
    for(int filter=0;filter<5;filter++)for(int shift=0;shift<=12;shift++){
        std::array<uint8_t,16> block{};block[0]=uint8_t((filter<<4)|shift);
        int a=s1,b=s2;int64_t error=0;
        const int step=4096>>shift;
        for(int i=0;i<28;i++){
            int prediction=((a*filters[filter][0])>>6)+((b*filters[filter][1])>>6);
            int nibble=std::clamp(int(std::lround(double(input[i]-prediction)/step)),-8,7);
            int sample=sat(nibble*step+prediction);
            int64_t delta=int(input[i])-sample;error+=delta*delta;
            block[2+i/2]|=uint8_t(nibble&15)<<((i&1)*4);
            b=a;a=sample;
            if(error>=best_error)break;
        }
        if(error<best_error){best_error=error;best=block;best_s1=a;best_s2=b;}
    }
    std::copy(best.begin(),best.end(),out);s1=best_s1;s2=best_s2;
}

inline int16_t interpolate(const int16_t *s,int phase){
    int i=(phase>>4)&255;
    // Keep one fractional bit in each product, then truncate the final sum.
    // This differs from SNES's intermediate wrap and from rounding each tap
    // to 16 bits. The PS1 hardware table never exceeds unity gain.
    int out=(int(gaussian[255-i])*s[0])>>14;
    out+=(int(gaussian[511-i])*s[1])>>14;
    out+=(int(gaussian[256+i])*s[2])>>14;
    out+=(int(gaussian[i])*s[3])>>14;
    return sat(out>>1);
}

struct Reverb {
    // Documented Studio Medium preset. Addresses are in 8-byte units;
    // the circular work RAM is signed 16-bit, advanced at 22050 Hz.
    static constexpr uint16_t regs[32]={
        0x00B1,0x007F,0x70F0,0x4FA8,0xBCE0,0x4510,0xBEF0,0xB4C0,
        0x5280,0x4EC0,0x0904,0x076B,0x0824,0x065F,0x07A2,0x0616,
        0x076C,0x05ED,0x05EC,0x042E,0x050F,0x0305,0x0462,0x02B7,
        0x042F,0x0265,0x0264,0x01B2,0x0100,0x0080,0x8000,0x8000};
    static constexpr int fir[39]={-1,0,2,0,-10,0,35,0,-103,0,266,0,-616,0,1332,0,-2960,0,10246,16384,10246,0,-2960,0,1332,0,-616,0,266,0,-103,0,35,0,-10,0,2,0,-1};
    std::array<int16_t,0x4840/2> ram{};
    std::array<std::array<int16_t,64>,2> input{},output{};
    int address=0,history=0;
    int read(int offset)const{
        int at=(address+offset)%int(ram.size());if(at<0)at+=int(ram.size());
        return ram[at];
    }
    int r(int reg,int delta=0)const{return read(int(regs[reg])*4+delta);}
    void w(int reg,int value){ram[(address+int(regs[reg])*4)%ram.size()]=sat(value);}
    int c(int reg)const{return int16_t(regs[reg]);}
    std::array<int16_t,2> tick(int left,int right){
        int in[2]={mul(left,c(30)),mul(right,c(31))};
        for(int channel=0;channel<2;channel++){
            int same=10+channel,diff=18+channel;
            int prev=r(same,-1);
            w(same,mul(in[channel]+mul(r(16+channel),c(7))-prev,c(2))+prev);
            prev=r(diff,-1);
            w(diff,mul(in[channel]+mul(r(24+(1-channel)),c(7))-prev,c(2))+prev);
        }
        std::array<int16_t,2> result{};
        for(int channel=0;channel<2;channel++){
            int out=mul(r(12+channel),c(3))+mul(r(14+channel),c(4))+mul(r(20+channel),c(5))+mul(r(22+channel),c(6));
            for(int stage=0;stage<2;stage++){
                int reg=26+stage*2+channel;
                int delayed=read(int(regs[reg])*4-int(regs[stage])*4);
                out=sat(out-mul(delayed,c(8+stage)));w(reg,out);
                out=sat(mul(out,c(8+stage))+delayed);
            }
            result[channel]=sat(out);
        }
        address=(address+1)%ram.size();return result;
    }
    std::array<int16_t,2> process(int16_t left,int16_t right){
        int index=history&63;input[0][index]=left;input[1][index]=right;
        std::array<int16_t,2> wet{};
        if((history&1)==0){
            int filtered[2]={};
            for(int ch=0;ch<2;ch++){
                int64_t sum=0;for(int tap=0;tap<39;tap++)sum+=int(input[ch][(history-tap)&63])*fir[tap];
                filtered[ch]=sat(sum>>15);
            }
            wet=tick(filtered[0],filtered[1]);
        }
        for(int ch=0;ch<2;ch++)output[ch][index]=wet[ch];
        for(int ch=0;ch<2;ch++){
            int64_t sum=0;for(int tap=0;tap<39;tap++)sum+=int(output[ch][(history-tap)&63])*fir[tap];
            wet[ch]=sat(sum>>14); // zero-stuffed 2x reconstruction gain
        }
        history=(history+1)&63;return wet;
    }
};
}
