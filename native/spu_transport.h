#pragma once
#include "spu_dsp.h"

namespace psx_spu {
// Host-device rate conversion occurs AFTER the SPU signed-16-bit output.
// It never changes the pitch counter, envelope rates or reverb clock.
struct OutputTransport {
    static constexpr int TAPS=32,PHASES=1024;
    std::array<std::array<int16_t,2>,64> history{};
    std::vector<std::array<double,TAPS>> weights;
    uint64_t written=0;
    int host_rate=0,input_rate=44100;
    void configure(int rate,int source_rate=44100){
        if(host_rate==rate&&input_rate==source_rate)return;
        host_rate=rate;input_rate=source_rate;weights.resize(PHASES);
        double cutoff=std::min(1.0,double(rate)/source_rate);
        constexpr double pi=3.14159265358979323846;
        for(int phase=0;phase<PHASES;phase++){
            double fraction=double(phase)/PHASES,sum=0;
            for(int tap=0;tap<TAPS;tap++){
                double x=15.0-tap-fraction;
                double sinc=std::abs(x)<1e-12?cutoff:std::sin(pi*x*cutoff)/(pi*x);
                double window=std::abs(x)<16?.5+.5*std::cos(pi*x/16):0;
                weights[phase][tap]=sinc*window;sum+=weights[phase][tap];
            }
            for(auto &weight:weights[phase])weight/=sum;
        }
    }
    void push(std::array<int16_t,2> value){history[written++&63]=value;}
    std::array<float,2> read(uint64_t remainder)const{
        if(!written)return {0,0};
        const auto &kernel=weights[std::min(int(remainder*PHASES/host_rate),PHASES-1)];
        double left=0,right=0;
        for(int tap=0;tap<TAPS;tap++)if(written>uint64_t(tap)){
            auto value=history[(written-1-tap)&63];left+=value[0]*kernel[tap];right+=value[1]*kernel[tap];
        }
        return {float(left/32768.0),float(right/32768.0)};
    }
};
}
