#include "spu_envelope.h"
#include "spu_transport.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/audio_stream.hpp>
#include <godot_cpp/classes/audio_stream_playback.hpp>
#include <godot_cpp/classes/audio_stream_wav.hpp>
#include <godot_cpp/classes/audio_server.hpp>
#include <godot_cpp/classes/audio_frame.hpp>
#include <godot_cpp/classes/audio_effect.hpp>
#include <godot_cpp/classes/audio_effect_instance.hpp>
#include <atomic>
#include <memory>
#include <mutex>
using namespace godot;

class AudioStreamPSX;
static std::atomic<int> active_voices{0};
struct SPUSample {std::vector<uint8_t> left,right;};
struct SPUDecoder {
    std::array<int16_t,31> samples{};
    int s1=0,s2=0;
    int64_t virtual_block=-1;
    void read(const std::vector<uint8_t> &bytes,int64_t index,int end,int loop_begin,bool looping,int16_t *out){
        int64_t block=index/28;
        if(virtual_block!=block){
            if(virtual_block+1!=block){samples={};s1=0;s2=0;}
            samples[0]=samples[28];samples[1]=samples[29];samples[2]=samples[30];
            int64_t physical=block*28;
            if(looping&&end>loop_begin&&physical>=end)physical=loop_begin+(physical-end)%(end-loop_begin);
            size_t address=size_t(physical/28)*16;
            if(address+16<=bytes.size())psx_spu::decode_block(bytes.data()+address,s1,s2,samples.data()+3);
            else std::fill(samples.begin()+3,samples.end(),0);
            virtual_block=block;
        }
        int offset=int(index%28);
        for(int tap=0;tap<4;tap++)out[tap]=samples[offset+tap];
    }
};
struct SPUControls {
    std::atomic<uint32_t> volumes{0x3fff3fff};
    std::atomic<bool> reverb{true},paused{false};
};
struct SPUVoice {
    std::shared_ptr<const SPUSample> sample;
    std::shared_ptr<SPUControls> controls;
    uint64_t counter=0;
    int frame_count=0,loop_begin=0,loop_end=0,pitch=0,channels=1,loops=0;
    bool looping=false,active=false,releasing=false;
    psx_spu::Envelope envelope;
    psx_spu::Volume left,right;
    std::array<SPUDecoder,2> decoder;
    int end()const{
        int requested=looping&&loop_end>loop_begin?std::min(loop_end,frame_count):frame_count;
        return std::min(((requested+27)/28)*28,int(sample->left.size()/16)*28);
    }
    void finish(){if(active){active=false;active_voices.fetch_sub(channels);}envelope.phase=psx_spu::Envelope::OFF;envelope.level=0;}
    std::array<int,2> tick(){
        if(!active||controls->paused.load(std::memory_order_relaxed))return {0,0};
        int64_t index=counter>>12;
        if(index>=end()){
            if(looping&&end()>loop_begin)loops=1+int((index-end())/(end()-loop_begin));
            else{finish();return {0,0};}
        }
        uint32_t volumes=controls->volumes.load(std::memory_order_relaxed);
        left.write(uint16_t(volumes));right.write(uint16_t(volumes>>16));
        int values[2]={};
        for(int ch=0;ch<channels;ch++){
            int16_t history[4];decoder[ch].read(ch?sample->right:sample->left,index,end(),loop_begin,looping,history);
            values[ch]=psx_spu::mul(psx_spu::interpolate(history,int(counter)&4095),envelope.level);
        }
        if(channels==1)values[1]=values[0];
        std::array<int,2> result={psx_spu::mul(values[0],left.level),psx_spu::mul(values[1],right.level)};
        envelope.tick();left.tick();right.tick();counter+=pitch;
        if(envelope.phase==psx_spu::Envelope::OFF)finish();
        return result;
    }
};
struct SPUMixBlock {
    static constexpr int CAPACITY=4096;
    std::mutex mutex;
    std::array<psx_spu::MixerFrame,CAPACITY> frames{};
    std::array<std::shared_ptr<SPUVoice>,24> releases{};
    std::array<std::weak_ptr<SPUVoice>,24> voices{};
    int collected=0,max_callback=0;
    uint64_t blocks=0,voice_frames=0,overflow=0;
    uint64_t phase=0,spu_ticks=0,host_frames=0,output_samples=0;
    int output_rate=22050;
    void add(int frame,int l,int r,bool wet){
        if(frame>=CAPACITY){overflow++;return;}
        frames[frame].add(l,r,wet);collected=std::max(collected,frame+1);voice_frames++;
    }
    void release(const std::shared_ptr<SPUVoice> &voice){
        if(!voice||!voice->active||voice->releasing)return;
        if(voice->controls->paused.load()){voice->finish();return;}
        voice->releasing=true;voice->envelope.key_off();
        for(auto &slot:releases)if(!slot||!slot->active){slot=voice;return;}
        voice->finish();
    }
    void make_room(int needed){
        // Driver policy: reuse a channel that is already in release before
        // refusing a new key-on. Never exceed 24 simultaneous mono voices.
        for(auto &voice:releases)if(active_voices.load()+needed>24&&voice&&voice->active)voice->finish();
    }
};
static SPUMixBlock spu_mix;
class AudioStreamPlaybackPSX : public AudioStreamPlayback {
    GDCLASS(AudioStreamPlaybackPSX,AudioStreamPlayback)
    Ref<AudioStreamPSX> stream;
    std::shared_ptr<SPUVoice> voice;
    bool managed=false;
    uint64_t phase=0;
    psx_spu::OutputTransport transport;
protected:
    static void _bind_methods(){
        ClassDB::bind_method(D_METHOD("key_off"),&AudioStreamPlaybackPSX::key_off);
        ClassDB::bind_method(D_METHOD("get_spu_state"),&AudioStreamPlaybackPSX::get_spu_state);
        ClassDB::bind_method(D_METHOD("mix_spu","frames","rate_scale"),&AudioStreamPlaybackPSX::mix_spu,DEFVAL(1.0));
    }
public:
    void setup(const Ref<AudioStreamPSX> &source){stream=source;}
    void _start(double position) override;
    void _stop() override;
    bool _is_playing()const override{std::lock_guard<std::mutex> lock(spu_mix.mutex);return voice&&voice->active&&!voice->releasing;}
    int32_t _get_loop_count()const override{std::lock_guard<std::mutex> lock(spu_mix.mutex);return voice?voice->loops:0;}
    double _get_playback_position()const override;
    void _seek(double position) override;
    int32_t _mix(AudioFrame *buffer,float rate_scale,int32_t frames) override;
    void key_off(){std::lock_guard<std::mutex> lock(spu_mix.mutex);if(voice)voice->envelope.key_off();}
    Dictionary get_spu_state()const;
    PackedVector2Array mix_spu(int frames,double rate_scale=1.0);
    ~AudioStreamPlaybackPSX(){_stop();}
};

class AudioStreamPSX : public AudioStream {
    GDCLASS(AudioStreamPSX,AudioStream)
    PackedByteArray left_data,right_data;
    std::shared_ptr<SPUSample> pcm=std::make_shared<SPUSample>();
    std::shared_ptr<SPUControls> controls=std::make_shared<SPUControls>();
    bool managed=false;
    int adsr1=0x00ff,adsr2=0x1fc0;
    int mix_rate=22050,frame_count=0,loop_begin=0,loop_end=0;
    bool loop=false;
protected:
    static void _bind_methods(){
        ClassDB::bind_method(D_METHOD("configure_source","source","sample_rate"),&AudioStreamPSX::configure_source,DEFVAL(0));
        ClassDB::bind_method(D_METHOD("make_voice"),&AudioStreamPSX::make_voice);
        ClassDB::bind_method(D_METHOD("is_managed"),&AudioStreamPSX::is_managed);
        ClassDB::bind_method(D_METHOD("key_off_all"),&AudioStreamPSX::key_off_all);
        ClassDB::bind_method(D_METHOD("set_spu_controls","left","right","reverb","paused"),&AudioStreamPSX::set_spu_controls,DEFVAL(false));
        ClassDB::bind_method(D_METHOD("get_mixer_diagnostics"),&AudioStreamPSX::get_mixer_diagnostics);
        ClassDB::bind_method(D_METHOD("set_adsr1","value"),&AudioStreamPSX::set_adsr1);
        ClassDB::bind_method(D_METHOD("get_adsr1"),&AudioStreamPSX::get_adsr1);
        ClassDB::bind_method(D_METHOD("set_adsr2","value"),&AudioStreamPSX::set_adsr2);
        ClassDB::bind_method(D_METHOD("get_adsr2"),&AudioStreamPSX::get_adsr2);
        ADD_GROUP("SPU ADSR","");
        ADD_PROPERTY(PropertyInfo(Variant::INT,"adsr1",PROPERTY_HINT_RANGE,"0,65535,1"),"set_adsr1","get_adsr1");
        ADD_PROPERTY(PropertyInfo(Variant::INT,"adsr2",PROPERTY_HINT_RANGE,"0,65535,1"),"set_adsr2","get_adsr2");
        ADD_GROUP("","");
        ClassDB::bind_method(D_METHOD("get_adpcm_left"),&AudioStreamPSX::get_adpcm_left);
        ClassDB::bind_method(D_METHOD("set_adpcm_left","data"),&AudioStreamPSX::set_adpcm_left);
        ClassDB::bind_method(D_METHOD("get_adpcm_right"),&AudioStreamPSX::get_adpcm_right);
        ClassDB::bind_method(D_METHOD("set_adpcm_right","data"),&AudioStreamPSX::set_adpcm_right);
        ADD_PROPERTY(PropertyInfo(Variant::PACKED_BYTE_ARRAY,"adpcm_left",PROPERTY_HINT_NONE,"",PROPERTY_USAGE_STORAGE),"set_adpcm_left","get_adpcm_left");
        ADD_PROPERTY(PropertyInfo(Variant::PACKED_BYTE_ARRAY,"adpcm_right",PROPERTY_HINT_NONE,"",PROPERTY_USAGE_STORAGE),"set_adpcm_right","get_adpcm_right");
        ClassDB::bind_method(D_METHOD("get_mix_rate"),&AudioStreamPSX::get_mix_rate);
        ClassDB::bind_method(D_METHOD("set_mix_rate","rate"),&AudioStreamPSX::set_mix_rate);
        ADD_PROPERTY(PropertyInfo(Variant::INT,"mix_rate"),"set_mix_rate","get_mix_rate");
        ClassDB::bind_method(D_METHOD("get_frame_count"),&AudioStreamPSX::get_frame_count);
        ClassDB::bind_method(D_METHOD("set_frame_count","frames"),&AudioStreamPSX::set_frame_count);
        ADD_PROPERTY(PropertyInfo(Variant::INT,"frame_count",PROPERTY_HINT_NONE,"",PROPERTY_USAGE_STORAGE),"set_frame_count","get_frame_count");
        ClassDB::bind_method(D_METHOD("get_loop"),&AudioStreamPSX::get_loop);
        ClassDB::bind_method(D_METHOD("set_loop","enabled"),&AudioStreamPSX::set_loop);
        ADD_PROPERTY(PropertyInfo(Variant::BOOL,"loop"),"set_loop","get_loop");
        ClassDB::bind_method(D_METHOD("get_loop_begin"),&AudioStreamPSX::get_loop_begin);
        ClassDB::bind_method(D_METHOD("set_loop_begin","frame"),&AudioStreamPSX::set_loop_begin);
        ADD_PROPERTY(PropertyInfo(Variant::INT,"loop_begin"),"set_loop_begin","get_loop_begin");
        ClassDB::bind_method(D_METHOD("get_loop_end"),&AudioStreamPSX::get_loop_end);
        ClassDB::bind_method(D_METHOD("set_loop_end","frame"),&AudioStreamPSX::set_loop_end);
        ADD_PROPERTY(PropertyInfo(Variant::INT,"loop_end"),"set_loop_end","get_loop_end");
    }
public:
    PackedByteArray get_adpcm_left()const{return left_data;}
    void set_adpcm_left(PackedByteArray data){if(!pcm.unique())pcm=std::make_shared<SPUSample>(*pcm);left_data=data;pcm->left.assign(data.ptr(),data.ptr()+data.size());}
    PackedByteArray get_adpcm_right()const{return right_data;}
    void set_adpcm_right(PackedByteArray data){if(!pcm.unique())pcm=std::make_shared<SPUSample>(*pcm);right_data=data;pcm->right.clear();if(!data.is_empty())pcm->right.assign(data.ptr(),data.ptr()+data.size());}
    int get_adsr1()const{return adsr1;}void set_adsr1(int value){adsr1=value&65535;}
    int get_adsr2()const{return adsr2;}void set_adsr2(int value){adsr2=value&65535;}
    bool is_managed()const{return managed;}
    void key_off_all(){
        std::lock_guard<std::mutex> lock(spu_mix.mutex);
        for(auto &slot:spu_mix.voices)if(auto voice=slot.lock())if(voice->active&&voice->controls==controls)spu_mix.release(voice);
    }
    void set_spu_controls(int left,int right,bool reverb,bool paused=false){
        controls->volumes.store(uint32_t(uint16_t(left))|(uint32_t(uint16_t(right))<<16),std::memory_order_relaxed);
        controls->reverb.store(reverb,std::memory_order_relaxed);controls->paused.store(paused,std::memory_order_relaxed);
    }
    Ref<AudioStreamPSX> make_voice()const{
        Ref<AudioStreamPSX> result;result.instantiate();
        result->left_data=left_data;result->right_data=right_data;result->pcm=pcm;
        result->mix_rate=mix_rate;result->frame_count=frame_count;result->loop_begin=loop_begin;result->loop_end=loop_end;result->loop=loop;
        result->adsr1=adsr1;result->adsr2=adsr2;result->managed=true;result->set_name(get_name());
        return result;
    }
    Dictionary get_mixer_diagnostics()const{
        std::lock_guard<std::mutex> lock(spu_mix.mutex);Dictionary d;
        d["active_voices"]=active_voices.load();d["blocks"]=int64_t(spu_mix.blocks);d["voice_frames"]=int64_t(spu_mix.voice_frames);
        d["max_callback_frames"]=spu_mix.max_callback;d["overflow"]=int64_t(spu_mix.overflow);
        d["spu_ticks"]=int64_t(spu_mix.spu_ticks);d["host_frames"]=int64_t(spu_mix.host_frames);
        d["spu_rate"]=44100;d["host_rate"]=AudioServer::get_singleton()->get_mix_rate();d["output_rate"]=spu_mix.output_rate;d["output_samples"]=int64_t(spu_mix.output_samples);return d;
    }
    std::shared_ptr<SPUVoice> create_state(double position)const{
        auto result=std::make_shared<SPUVoice>();result->sample=pcm;result->controls=controls;
        result->counter=uint64_t(std::clamp(position,0.0,_get_length())*mix_rate)*4096;
        result->frame_count=frame_count;result->loop_begin=(loop_begin/28)*28;result->loop_end=loop_end;result->looping=loop;
        result->channels=channels();result->active=true;result->envelope.key_on(adsr1,adsr2);
        return result;
    }
    int get_mix_rate()const{return mix_rate;}
    void set_mix_rate(int rate){mix_rate=std::clamp(rate,4000,44100);}
    int get_frame_count()const{return frame_count;}
    void set_frame_count(int count){frame_count=std::max(count,0);}
    bool get_loop()const{return loop;}
    void set_loop(bool enabled){loop=enabled;}
    int get_loop_begin()const{return loop_begin;}
    void set_loop_begin(int frame){loop_begin=std::max(frame,0);}
    int get_loop_end()const{return loop_end;}
    void set_loop_end(int frame){loop_end=std::max(frame,0);}
    double _get_length()const override{return double(frame_count)/mix_rate;}
    bool _has_loop()const override{return loop;}
    String _get_stream_name()const override{return "PS1 SPU ADPCM";}
    Ref<AudioStreamPlayback> _instantiate_playback()const override{
        Ref<AudioStreamPlaybackPSX> playback;playback.instantiate();
        playback->setup(Ref<AudioStreamPSX>(const_cast<AudioStreamPSX*>(this)));return playback;
    }
    int channels()const{return right_data.is_empty()?1:2;}
    int end()const{return loop&&loop_end>loop_begin?std::min(loop_end,frame_count):frame_count;}
    bool can_loop()const{return loop&&end()>loop_begin;}
    bool configure_source(Ref<AudioStream> source,int override_rate=0){
        if(source.is_null()||Object::cast_to<AudioStreamPSX>(source.ptr()))return false;
        auto wav=Object::cast_to<AudioStreamWAV>(source.ptr());
        int source_rate=wav?wav->get_mix_rate():44100;
        set_mix_rate(override_rate>0?override_rate:source_rate);
        double length=source->get_length();
        if(!std::isfinite(length)||length<=0||length>3600)return false;
        frame_count=int(std::ceil(length*mix_rate));loop=false;loop_begin=0;loop_end=frame_count;
        if(wav){
            loop=wav->get_loop_mode()!=AudioStreamWAV::LOOP_DISABLED;
            loop_begin=int(int64_t(wav->get_loop_begin())*mix_rate/source_rate);
            loop_end=wav->get_loop_end()>0?int(int64_t(wav->get_loop_end())*mix_rate/source_rate):frame_count;
        }else if(source->has_method("has_loop")){
            loop=bool(source->call("has_loop"));
            if(source->has_method("get_loop_offset"))loop_begin=int(double(source->call("get_loop_offset"))*mix_rate);
        }
        Ref<AudioStreamPlayback> playback=source->instantiate_playback();
        if(playback.is_null())return false;
        playback->start(0);
        std::vector<int16_t> pcm[2];pcm[0].resize(frame_count);pcm[1].resize(frame_count);
        bool stereo=false;
        float speed=float(AudioServer::get_singleton()->get_mix_rate())/mix_rate;
        for(int start=0;start<frame_count;start+=4096){
            int count=std::min(4096,frame_count-start);
            PackedVector2Array decoded=playback->mix_audio(speed,count);
            for(int i=0;i<count&&i<decoded.size();i++){
                Vector2 frame=decoded[i];
                for(int ch=0;ch<2;ch++)pcm[ch][start+i]=psx_spu::sat(std::lround(std::clamp(double(frame[ch]),-1.0,1.0)*32768));
                if(pcm[0][start+i]!=pcm[1][start+i])stereo=true;
            }
        }
        playback->stop();
        PackedByteArray encoded[2];
        int blocks=(frame_count+27)/28;
        for(int ch=0;ch<(stereo?2:1);ch++){
            encoded[ch].resize(blocks*16);int s1=0,s2=0;
            for(int block=0;block<blocks;block++){
                int16_t samples[28]={};
                for(int i=0;i<28&&block*28+i<frame_count;i++)samples[i]=pcm[ch][block*28+i];
                uint8_t *bytes=encoded[ch].ptrw()+block*16;
                psx_spu::encode_block(samples,s1,s2,bytes);
                if(block==blocks-1)bytes[1]=loop?3:1;
                if(loop&&block==loop_begin/28)bytes[1]|=4;
            }
        }
        set_adpcm_left(encoded[0]);set_adpcm_right(encoded[1]);return true;
    }
};

void AudioStreamPlaybackPSX::_start(double position){
    _stop();if(stream.is_null()||stream->get_frame_count()<=0)return;
    std::lock_guard<std::mutex> lock(spu_mix.mutex);
    int needed=stream->channels();spu_mix.make_room(needed);
    if(active_voices.load()+needed>24)return;
    voice=stream->create_state(position);managed=stream->is_managed();phase=0;
    for(auto &slot:spu_mix.voices){auto current=slot.lock();if(!current||!current->active){slot=voice;break;}}
    if(!managed){transport.configure(int(AudioServer::get_singleton()->get_mix_rate()));transport.history={};transport.written=0;}
    active_voices.fetch_add(needed);
}
void AudioStreamPlaybackPSX::_stop(){
    std::lock_guard<std::mutex> lock(spu_mix.mutex);
    if(voice){if(managed)spu_mix.release(voice);else voice->finish();voice.reset();}
}
void AudioStreamPlaybackPSX::_seek(double position){
    std::lock_guard<std::mutex> lock(spu_mix.mutex);
    if(voice)voice->counter=uint64_t(std::clamp(position,0.0,stream->_get_length())*stream->get_mix_rate())*4096;
}
double AudioStreamPlaybackPSX::_get_playback_position()const{
    std::lock_guard<std::mutex> lock(spu_mix.mutex);
    if(stream.is_null()||!voice)return 0;
    double frame=voice->counter/4096.0;
    if(voice->looping&&voice->end()>voice->loop_begin&&frame>=voice->end())frame=voice->loop_begin+std::fmod(frame-voice->loop_begin,voice->end()-voice->loop_begin);
    return frame/stream->get_mix_rate();
}
int32_t AudioStreamPlaybackPSX::_mix(AudioFrame *buffer,float rate_scale,int32_t frames){
    std::lock_guard<std::mutex> lock(spu_mix.mutex);
    int written=0;
    // Rate conversion is confined to the final transport. Every voice and
    // ADSR tick is still clocked at 44,100 Hz, even on a 48/96 kHz device.
    if(voice)voice->pitch=std::clamp(int(std::lround(stream->get_mix_rate()/44100.0*rate_scale*4096)),0,0x3fff);
    if(managed)spu_mix.max_callback=std::max(spu_mix.max_callback,int(frames));
    int host_rate=int(AudioServer::get_singleton()->get_mix_rate());
    if(managed){
        int native_frames=int((spu_mix.phase+uint64_t(frames)*44100)/host_rate);
        std::fill(buffer,buffer+frames,AudioFrame{0,0});
        for(int i=0;i<native_frames;i++)if(voice&&voice->active&&!voice->releasing){
            auto value=voice->tick();spu_mix.add(i,value[0],value[1],voice->controls->reverb.load(std::memory_order_relaxed));written++;
        }
        return written?frames:0;
    }
    for(int i=0;i<frames;i++){
        buffer[i]={0,0};if(!voice||!voice->active||voice->releasing)continue;
        std::array<int,2> value{};phase+=44100;
        while(phase>=uint64_t(host_rate)){
            value=voice->tick();transport.push({psx_spu::sat(value[0]),psx_spu::sat(value[1])});phase-=host_rate;
        }
        if(host_rate==44100){buffer[i].left=value[0]/32768.0f;buffer[i].right=value[1]/32768.0f;}
        else{auto sample=transport.read(phase);buffer[i].left=sample[0];buffer[i].right=sample[1];}
        written++;
    }
    return written;
}
PackedVector2Array AudioStreamPlaybackPSX::mix_spu(int frames,double rate_scale){
    std::lock_guard<std::mutex> lock(spu_mix.mutex);PackedVector2Array out;
    frames=std::clamp(frames,0,44100*60);out.resize(frames);
    if(!voice||managed)return out;
    voice->pitch=std::clamp(int(std::lround(stream->get_mix_rate()/44100.0*rate_scale*4096)),0,0x3fff);
    for(int i=0;i<frames;i++){auto value=voice->tick();out.set(i,Vector2(value[0]/32768.0,value[1]/32768.0));}
    return out;
}
Dictionary AudioStreamPlaybackPSX::get_spu_state()const{
    std::lock_guard<std::mutex> lock(spu_mix.mutex);Dictionary d;
    d["managed"]=managed;d["active"]=voice&&voice->active;
    d["envelope"]=voice?voice->envelope.level:0;d["phase"]=voice?int(voice->envelope.phase):0;
    d["pitch"]=voice?voice->pitch:0;d["left"]=voice?voice->left.level:0;d["right"]=voice?voice->right.level:0;
    return d;
}

struct SPUMasterControls {
    std::atomic<bool> native_mixer{false};
    std::atomic<int> output_rate{22050};
    std::atomic<int> reverb_level{7209},left{0x3fff},right{0x3fff};
};

class AudioEffectInstancePSX : public AudioEffectInstance {
    GDCLASS(AudioEffectInstancePSX,AudioEffectInstance)
    psx_spu::Reverb reverb;
    double clock=0;
    std::array<int16_t,2> last{};
    psx_spu::Volume master_left,master_right;
    psx_spu::OutputTransport transport,content_transport;
    uint64_t content_phase=0;
    int previous_output_rate=0;
    std::array<int16_t,2> last_content{};
protected:
    static void _bind_methods(){
        ClassDB::bind_method(D_METHOD("process_samples","frames"),&AudioEffectInstancePSX::process_samples);
    }
public:
    std::shared_ptr<std::atomic<int>> wet_source;
    std::shared_ptr<SPUMasterControls> master;
    int wet_level()const{return wet_source?wet_source->load(std::memory_order_relaxed):7209;}
    bool _process_silence()const override{return wet_level()>0||(master&&master->native_mixer.load());}
    void _process(const void *src,AudioFrame *dst,int32_t frames) override{
        const auto *input=static_cast<const AudioFrame*>(src);
        if(master&&master->native_mixer.load()){
            std::lock_guard<std::mutex> lock(spu_mix.mutex);
            master_left.write(uint16_t(master->left.load()));master_right.write(uint16_t(master->right.load()));
            int wet=master->reverb_level.load();
            int host_rate=int(AudioServer::get_singleton()->get_mix_rate());
            int output_rate=master->output_rate.load();
            if(output_rate!=previous_output_rate){
                content_phase=0;last_content={};content_transport.history={};content_transport.written=0;transport.history={};transport.written=0;previous_output_rate=output_rate;
            }
            content_transport.configure(output_rate);transport.configure(host_rate,output_rate);spu_mix.output_rate=output_rate;
            uint64_t phase=spu_mix.phase;int native_index=0;
            for(int i=0;i<frames;i++){
              phase+=44100;std::array<int16_t,2> output{};
              while(phase>=uint64_t(host_rate)){
                psx_spu::MixerFrame sum=native_index<SPUMixBlock::CAPACITY?spu_mix.frames[native_index]:psx_spu::MixerFrame{};
                for(auto &voice:spu_mix.releases)if(voice&&voice->active){
                    auto release=voice->tick();sum.add(release[0],release[1],voice->controls->reverb.load());
                }
                // Imported editor previews / external PCM inputs may reach
                // this sink too. Project voices themselves contribute zero
                // to Godot's float buses and are summed above as integers.
                sum.left+=psx_spu::sat(std::lround(std::clamp(double(input[i].left),-1.0,1.0)*32768));
                sum.right+=psx_spu::sat(std::lround(std::clamp(double(input[i].right),-1.0,1.0)*32768));
                auto tail=reverb.process(psx_spu::sat(sum.send_left),psx_spu::sat(sum.send_right));
                output=sum.finish(psx_spu::mul(tail[0],wet),psx_spu::mul(tail[1],wet),master_left.level,master_right.level);
                master_left.tick();master_right.tick();
                // Voice, ADSR and reverb clocks remain at 44.1 kHz. Sample the
                // finished mix at the content rate before device adaptation.
                content_transport.push(output);content_phase+=output_rate;
                if(content_phase>=44100){
                    content_phase-=44100;
                    if(output_rate==44100)last_content=output;
                    else{auto value=content_transport.read(content_phase);last_content={psx_spu::sat(std::lround(value[0]*32768)),psx_spu::sat(std::lround(value[1]*32768))};}
                    transport.push(last_content);spu_mix.output_samples++;
                }
                phase-=host_rate;spu_mix.spu_ticks++;
                if(native_index<SPUMixBlock::CAPACITY)spu_mix.frames[native_index]={};native_index++;
              }
              if(host_rate==output_rate){dst[i].left=last_content[0]/32768.0f;dst[i].right=last_content[1]/32768.0f;}
              else{
                  uint64_t remainder=(content_phase*uint64_t(host_rate)+phase*uint64_t(output_rate))/44100;
                  auto sample=transport.read(remainder);dst[i].left=sample[0];dst[i].right=sample[1];
              }
            }
            if(spu_mix.collected>native_index)spu_mix.overflow++;
            spu_mix.phase=phase;spu_mix.collected=0;spu_mix.blocks++;spu_mix.host_frames+=frames;return;
        }
        const int wet=wet_level();
        // The master stage can retain signed 16-bit saturation without adding
        // reverb. Per-voice EON routing happens on the upstream send bus.
        if(wet==0){
            for(int i=0;i<frames;i++){
                dst[i].left=psx_spu::sat(std::lround(std::clamp(double(input[i].left),-1.0,1.0)*32768))/32768.0f;
                dst[i].right=psx_spu::sat(std::lround(std::clamp(double(input[i].right),-1.0,1.0)*32768))/32768.0f;
            }
            return;
        }
        double rate=44100.0/AudioServer::get_singleton()->get_mix_rate();
        for(int i=0;i<frames;i++){
            int16_t left=psx_spu::sat(std::lround(std::clamp(double(input[i].left),-1.0,1.0)*32768));
            int16_t right=psx_spu::sat(std::lround(std::clamp(double(input[i].right),-1.0,1.0)*32768));
            clock+=rate;
            while(clock>=1){last=reverb.process(left,right);clock-=1;}
            dst[i].left=psx_spu::sat(left+psx_spu::mul(last[0],wet))/32768.0f;
            dst[i].right=psx_spu::sat(right+psx_spu::mul(last[1],wet))/32768.0f;
        }
    }
    PackedVector2Array process_samples(PackedVector2Array input){
        std::vector<AudioFrame> src(input.size()),dst(input.size());
        for(int i=0;i<input.size();i++)src[i]={float(input[i].x),float(input[i].y)};
        _process(src.data(),dst.data(),int32_t(input.size()));
        PackedVector2Array result;result.resize(input.size());
        for(int i=0;i<input.size();i++)result[i]=Vector2(dst[i].left,dst[i].right);
        return result;
    }
};
class AudioEffectPSXReverb : public AudioEffect {
    GDCLASS(AudioEffectPSXReverb,AudioEffect)
    std::shared_ptr<std::atomic<int>> wet_source=std::make_shared<std::atomic<int>>(7209);
    std::shared_ptr<SPUMasterControls> master=std::make_shared<SPUMasterControls>();
protected:
    static void _bind_methods(){
        ClassDB::bind_method(D_METHOD("set_wet","level"),&AudioEffectPSXReverb::set_wet);
        ClassDB::bind_method(D_METHOD("get_wet"),&AudioEffectPSXReverb::get_wet);
        ADD_PROPERTY(PropertyInfo(Variant::FLOAT,"wet",PROPERTY_HINT_RANGE,"0,1,0.01"),"set_wet","get_wet");
        ClassDB::bind_method(D_METHOD("set_native_mixer","enabled"),&AudioEffectPSXReverb::set_native_mixer);
        ClassDB::bind_method(D_METHOD("get_native_mixer"),&AudioEffectPSXReverb::get_native_mixer);
        ADD_PROPERTY(PropertyInfo(Variant::BOOL,"native_mixer"),"set_native_mixer","get_native_mixer");
        ClassDB::bind_method(D_METHOD("set_output_rate","rate"),&AudioEffectPSXReverb::set_output_rate);
        ClassDB::bind_method(D_METHOD("get_output_rate"),&AudioEffectPSXReverb::get_output_rate);
        ADD_PROPERTY(PropertyInfo(Variant::INT,"output_rate",PROPERTY_HINT_ENUM,"22050 Hz:22050,11025 Hz:11025,44100 Hz:44100"),"set_output_rate","get_output_rate");
        ClassDB::bind_method(D_METHOD("set_reverb_level","level"),&AudioEffectPSXReverb::set_reverb_level);
        ClassDB::bind_method(D_METHOD("get_reverb_level"),&AudioEffectPSXReverb::get_reverb_level);
        ADD_PROPERTY(PropertyInfo(Variant::FLOAT,"reverb_level",PROPERTY_HINT_RANGE,"0,1,0.01"),"set_reverb_level","get_reverb_level");
        ClassDB::bind_method(D_METHOD("set_master_left","value"),&AudioEffectPSXReverb::set_master_left);
        ClassDB::bind_method(D_METHOD("get_master_left"),&AudioEffectPSXReverb::get_master_left);
        ClassDB::bind_method(D_METHOD("set_master_right","value"),&AudioEffectPSXReverb::set_master_right);
        ClassDB::bind_method(D_METHOD("get_master_right"),&AudioEffectPSXReverb::get_master_right);
        ADD_PROPERTY(PropertyInfo(Variant::INT,"master_left",PROPERTY_HINT_RANGE,"0,65535,1"),"set_master_left","get_master_left");
        ADD_PROPERTY(PropertyInfo(Variant::INT,"master_right",PROPERTY_HINT_RANGE,"0,65535,1"),"set_master_right","get_master_right");
    }
public:
    void set_wet(double level){wet_source->store(std::clamp(int(std::lround(level*32768)),0,32768),std::memory_order_relaxed);}
    double get_wet()const{return double(wet_source->load(std::memory_order_relaxed))/32768;}
    void set_native_mixer(bool enabled){master->native_mixer.store(enabled);}bool get_native_mixer()const{return master->native_mixer.load();}
    void set_output_rate(int rate){master->output_rate.store(rate==11025?11025:rate==44100?44100:22050);}int get_output_rate()const{return master->output_rate.load();}
    void set_reverb_level(double level){master->reverb_level.store(std::clamp(int(std::lround(level*32768)),0,32767));}
    double get_reverb_level()const{return master->reverb_level.load()/32768.0;}
    void set_master_left(int value){master->left.store(value&65535);}int get_master_left()const{return master->left.load();}
    void set_master_right(int value){master->right.store(value&65535);}int get_master_right()const{return master->right.load();}
    Ref<AudioEffectInstance> _instantiate() override{
        Ref<AudioEffectInstancePSX> instance;instance.instantiate();instance->wet_source=wet_source;instance->master=master;return instance;
    }
};
void register_psx_audio(){
    ClassDB::register_class<AudioStreamPSX>();
    ClassDB::register_class<AudioStreamPlaybackPSX>();
    ClassDB::register_class<AudioEffectInstancePSX>();
    ClassDB::register_class<AudioEffectPSXReverb>();
}
