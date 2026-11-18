function checks=dmt_vm_preflight(cfg,conditions)
%DMT_VM_PREFLIGHT Exercise the real link and verify its numeric invariants.
% These independent fixtures are never inputs to calibration or formal BER.
if istable(conditions),conditions=table2struct(conditions);end
assert(cfg.Fs==128e9 && ismember(cfg.NFFT,[512 1024]) && ...
    cfg.NCP>=max(arrayfun(@(c)numel(c.h)-1,conditions)) && ...
    numel(conditions)==6 && all([conditions.P_target]==1) && ...
    all([conditions.q]==8) && isequal(unique([conditions.swing]),[.25 .5 .75]) && ...
    isequal(cfg.Mset,[4 16 64]) && cfg.Es==1 && cfg.chunkSize>=2 && ...
    cfg.P_peak>1 && cfg.noise_variance>0 && cfg.rho==4 && ...
    cfg.power_cal_symbols==8192 && cfg.targetBER==1e-3 && ...
    cfg.payload_symbols==25000 && cfg.control_delay==0, ...
    'DMT:VMPreflightConfig','The model and fixture geometry do not match the frozen protocol.');
middle=conditions([conditions.swing]==.5);
assert(numel(middle)==2);
link=cell(6,1);
for j=1:numel(middle)
    for k=1:numel(cfg.Mset)
        n=(j-1)*numel(cfg.Mset)+k;
        link{n}=checkNoiseless(cfg,middle(j),cfg.Mset(k),2030000000+2*n-1,2030000000+2*n);
    end
end
link=vertcat(link{:});
high=conditions([conditions.swing]==.75);
physical=checkPhysical(cfg,high(end),2030000021,2030000022);
adc=checkADC(cfg);
power=cell(numel(conditions),1);
for j=1:numel(conditions)
    power{j}=checkPower(cfg,conditions(j),2030000030+j,2030000023);
end
power=vertcat(power{:});
unreachable=checkUnreachablePower(cfg,middle(1),2030000039);
counters=checkCounters(cfg);
checkpoint=checkCheckpoint(cfg);
strategy=dmt_vm_strategy_fixtures(cfg);
checks=struct('scope','Mechanical fixtures, excluded from study BER and rate', ...
    'config_hash',dmt_v13_hash(cfg),'conditions_hash',dmt_v13_hash(conditions), ...
    'fixture_seeds',[2030000001:2030000012 2030000021:2030000023 2030000031:2030000036 2030000039], ...
    'link',link,'physical',physical,'adc',adc,'power',power,'unreachable_power',unreachable, ...
    'counters',counters,'checkpoint',checkpoint,'strategy',strategy);
checks.passed=all([link.passed]) && physical.passed && adc.passed && all([power.passed]) && ...
    unreachable.passed && counters.passed && checkpoint.passed && strategy.passed;
end

function one=checkNoiseless(cfg,condition,order,trainingSeed,dataSeed)
bias=1;
scale=.25;
M=order*ones(numel(cfg.k),1);
trainingSymbols=min(7,cfg.chunkSize);
headSymbols=min(13,cfg.chunkSize);
tailSymbols=min(19,cfg.chunkSize);
A=dmt_v13_make_frame(cfg,M,trainingSymbols,dmt_v13_stream(cfg,trainingSeed));
stream=dmt_v13_stream(cfg,dataSeed);
[head,bitsHead]=dmt_v13_make_frame(cfg,M,headSymbols,stream);
[tail,bitsTail]=dmt_v13_make_frame(cfg,M,tailSymbols,stream);
[Ya,ma,state,da]=dmt_vm_link(cfg,condition,scale*A,bias,[],[],false,true);
[Y1,m1,state,d1]=dmt_vm_link(cfg,condition,scale*head,bias,state,[],false,true);
[Y2,m2,~,d2]=dmt_vm_link(cfg,condition,scale*tail,bias,state,[],false,true);
known=A(cfg.k+1,:);
Hhat=sum(Ya.*conj(known),2)./sum(abs(known).^2,2);
H=scale*dmt_vm_drive_scale(cfg,condition)* ...
    (exp(-2i*pi*(cfg.k(:)/cfg.NFFT)*(0:numel(condition.h)-1))*condition.h(:));
assert(all(isfinite(Hhat) & abs(Hhat)>0 & abs(H)>0),'DMT:VMPreflightLink', ...
    'An active tone cannot be equalized with this noiseless fixture.');
X=[head(cfg.k+1,:) tail(cfg.k+1,:)];
Y=[Y1 Y2];
Z=Y./Hhat;
[errors,tested]=dmt_demod_errors(cfg,Z, ...
    cellfun(@vertcat,bitsHead,bitsTail,'UniformOutput',false),M);
tx=[da.p;d1.p;d2.p];
rx=[da.rx_before_adc;d1.rx_before_adc;d2.rx_before_adc];
linear=conv(tx,condition.h(:));
reset=conv(d2.p,condition.h(:));
metrics=[ma m1 m2];
used=[cfg.k(:)+1;cfg.NFFT-cfg.k(:)+1];
unused=setdiff((1:cfg.NFFT).',used);
whole=[A head tail];
one=struct('case_id',condition.case_id,'qam_order',order, ...
    'training_seed',trainingSeed,'data_seed',dataSeed, ...
    'training_symbols',trainingSymbols,'data_chunk_symbols',[headSymbols tailSymbols], ...
    'fft_length',cfg.NFFT,'cp_length',cfg.NCP,'fir_memory',numel(condition.h)-1, ...
    'first_fft_sample',cfg.NCP+1,'active_k',cfg.k(:), ...
    'hermitian',isequal(whole(cfg.NFFT-cfg.k+1,:),conj(whole(cfg.k+1,:))), ...
    'empty_dc_nyquist_guard',all(whole(unused,:)==0,'all'), ...
    'added_noise_energy',sum([metrics.noise_sum_sq]), ...
    'clipped_samples',sum([metrics.lower_clip_count])+sum([metrics.upper_clip_count]), ...
    'adc_bypassed',isequal([da.adc_output;d1.adc_output;d2.adc_output],rx), ...
    'max_convolution_error',max(abs(rx-linear(1:numel(rx)))), ...
    'tail_state_reset_difference',max(abs(d2.rx_before_adc-reset(1:numel(d2.p)))), ...
    'training_complex_response_error',abs(Hhat-H), ...
    'data_complex_response_error',max(abs(Y./X-H),[],2), ...
    'max_zf_error',max(abs(Z-X),[],2),'error_bits',errors,'tested_bits',tested);
tol=5e-10;
one.passed=one.hermitian && one.empty_dc_nyquist_guard && ...
    one.added_noise_energy==0 && one.clipped_samples==0 && one.adc_bypassed && ...
    one.max_convolution_error<=tol && ...
    (one.fir_memory==0 || one.tail_state_reset_difference>tol) && ...
    all(one.training_complex_response_error<=tol) && all(one.data_complex_response_error<=tol) && ...
    all(one.max_zf_error<=tol) && all(errors==0) && ...
    all(tested==log2(order)*(headSymbols+tailSymbols));
end

function one=checkPhysical(cfg,condition,dataSeed,noiseSeed)
M=repmat(cfg.Mset(:),ceil(numel(cfg.k)/numel(cfg.Mset)),1);
M=M(1:numel(cfg.k));
headSymbols=min(15,max(1,floor(cfg.chunkSize/3)));
tailSymbols=min(22,cfg.chunkSize-headSymbols);
nSymbols=headSymbols+tailSymbols;
[X,bits]=dmt_v13_make_frame(cfg,M,nSymbols,dmt_v13_stream(cfg,dataSeed));
stream=dmt_v13_stream(cfg,dataSeed);
[head,bitsHead]=dmt_v13_make_frame(cfg,M,headSymbols,stream);
[tail,bitsTail]=dmt_v13_make_frame(cfg,M,tailSymbols,stream);

% A separate bias stress fixture activates the clipper even when the actual
% matched-mean high-drive working point does not clip.
bias=min(cfg.b_bounds(2),cfg.P_peak);
[Y,metrics,~,whole]=dmt_vm_link(cfg,condition,X,bias,[], ...
    dmt_v13_stream(cfg,noiseSeed),true,false);
stream=dmt_v13_stream(cfg,noiseSeed);
[Y1,~,state,d1]=dmt_vm_link(cfg,condition,head,bias,[],stream,true,false);
[Y2,~,~,d2]=dmt_vm_link(cfg,condition,tail,bias,state,stream,true,false);
noise=sqrt(cfg.noise_variance)*randn(dmt_v13_stream(cfg,noiseSeed),numel(whole.p),1);
raw=bias+dmt_vm_drive_scale(cfg,condition)*whole.tx_serial;
p=min(cfg.P_peak,max(0,raw));
linear=conv(p,condition.h(:));
expectedAnalog=linear(1:numel(noise))+noise;
[expectedADC,lo,hi]=independentADC(cfg,condition,expectedAnalog);
samples=reshape(expectedADC,cfg.NFFT+cfg.NCP,nSymbols);
expectedFFT=fft(samples(cfg.NCP+1:end,:),[],1)/sqrt(cfg.NFFT);
one=struct('case_id',condition.case_id,'swing',condition.swing,'bias_stress_fixture',bias, ...
    'data_seed',dataSeed,'noise_seed',noiseSeed,'data_chunk_symbols',[headSymbols tailSymbols], ...
    'same_chunk_bits',all(cellfun(@(a,b,c)isequal(a,[b;c]),bits,bitsHead,bitsTail)), ...
    'max_frame_error',max(abs(X-[head tail]),[],'all'), ...
    'max_chunk_tx_error',max(abs(whole.tx_serial-[d1.tx_serial;d2.tx_serial])), ...
    'max_raw_error',max(abs(whole.p_raw-raw)), ...
    'clipped_samples',metrics.lower_clip_count+metrics.upper_clip_count, ...
    'same_clipping',isequal(p,whole.p) && metrics.lower_clip_count==nnz(raw<0) && ...
        metrics.upper_clip_count==nnz(raw>cfg.P_peak), ...
    'same_noise',isequal(noise,whole.noise,[d1.noise;d2.noise]), ...
    'max_analog_error',max(abs(whole.rx_before_adc-expectedAnalog)), ...
    'max_ADC_error',max(abs(whole.adc_output-expectedADC)), ...
    'same_ADC_counts',metrics.adc_low_count==lo && metrics.adc_high_count==hi, ...
    'max_chunk_fft_error',max(abs(Y-[Y1 Y2]),[],'all'), ...
    'max_ADC_fft_error',max(abs(Y-expectedFFT(cfg.k+1,:)),[],'all'));
tol=5e-10;
one.passed=one.same_chunk_bits && one.same_noise && ...
    one.same_clipping && one.clipped_samples>0 && one.same_ADC_counts && ...
    max([one.max_frame_error one.max_chunk_tx_error one.max_raw_error ...
        one.max_analog_error one.max_ADC_error one.max_chunk_fft_error one.max_ADC_fft_error])<=tol;
end

function [output,below,above]=independentADC(cfg,condition,input)
levels=2^condition.q;
lo=cfg.adc_range(1);
hi=cfg.adc_range(2);
step=(hi-lo)/levels;
index=floor((input-lo)/step);
index(index<0)=0;
index(index>=levels)=levels-1;
output=lo+(index+.5)*step;
below=nnz(input<lo);
above=nnz(input>hi);
end

function one=checkADC(cfg)
q=8;
levels=2^q;
lo=cfg.adc_range(1);
hi=cfg.adc_range(2);
step=(hi-lo)/levels;
centers=lo+((0:levels-1)+.5)*step;
input=[lo-1 lo centers hi hi+1];
expected=[centers(1) centers(1) centers centers(end) centers(end)];
[actual,raw]=dmt_to_quantize(input,q,cfg,false);
one=struct('q',q,'levels',raw.levels,'unique_codes',numel(unique(actual)), ...
    'low_count',raw.low_count,'high_count',raw.high_count, ...
    'max_value_error',max(abs(actual-expected)));
one.passed=one.levels==levels && one.unique_codes==levels && ...
    one.low_count==1 && one.high_count==1 && one.max_value_error<=10*eps(hi);
end

function one=checkPower(cfg,condition,calibrationSeed,linkSeed)
M=4*ones(numel(cfg.k),1);
applied=dmt_vm_power_cal(cfg,condition,M,calibrationSeed);
n=(cfg.NFFT+cfg.NCP)*cfg.power_cal_symbols;
X=dmt_v13_make_frame(cfg,M,min(37,cfg.chunkSize),dmt_v13_stream(cfg,linkSeed));
[~,sent,~,debug]=dmt_vm_link(cfg,condition,X,applied.b,[],[],false,true);
drive=(debug.p_raw-applied.b);
% A second optical bias changes only the DC command (including in samples
% outside the optical clip range), with the identical DMT AC drive.
alternateBias=mean([cfg.b_bounds(1) applied.b]);
[~,~,~,alternate]=dmt_vm_link(cfg,condition,X,alternateBias,[],[],false,true);
expectedDrive=condition.swing*condition.P_target*debug.tx_serial/ ...
    (cfg.rho*sqrt(2*numel(cfg.k)*cfg.Es/cfg.NFFT));
sorted=sort(debug.p);
p01=sorted(ceil(.01*length(sorted)));
p99=sorted(ceil(.99*length(sorted)));
histTolerance=cfg.P_peak/(2*sent.tx_hist_bins)+10*eps(cfg.P_peak);
one=struct('case_id',condition.case_id,'swing',condition.swing, ...
    'calibration_data_seed',calibrationSeed,'link_fixture_data_seed',linkSeed, ...
    'calibration_samples',applied.sample_count,'target',condition.P_target, ...
    'calibrated_mean',applied.actual_mean,'relative_error',applied.relative_error, ...
    'calibrated_bias',applied.b,'waveform_hash',applied.waveform_hash, ...
    'calibration_clip_counts',[applied.lower_clip_count applied.upper_clip_count], ...
    'calibration_clip_ratio',(applied.lower_clip_count+applied.upper_clip_count)/applied.sample_count, ...
    'link_fixture_clip_counts',[sent.lower_clip_count sent.upper_clip_count], ...
    'link_fixture_mean',sent.tx_sum/sent.sample_count, ...
    'link_fixture_observed_swing',sent.observed_swing,'link_fixture_ac_rms',sent.drive_ac_rms, ...
    'max_drive_error',max(abs(drive-expectedDrive)), ...
    'max_bias_ac_error',max(abs(drive-(alternate.p_raw-alternateBias))), ...
    'percentile_error',[abs(p01-sent.tx_p01) abs(p99-sent.tx_p99)]);
one.passed=applied.monotone && applied.reachable && one.calibration_samples==n && ...
    abs(one.relative_error)<=cfg.power_cal_tolerance && ...
    abs(applied.actual_mean-applied.tx_sum/n)<=5e-12 && ...
    all(one.percentile_error<=histTolerance) && ...
    one.max_drive_error<5e-12 && one.max_bias_ac_error<5e-12;
end

function one=checkUnreachablePower(cfg,condition,seed)
fixture=cfg;
fixture.power_cal_symbols=3;
condition.P_target=cfg.P_peak+.125;
expected='DMT:TOPowerUnreachable';
id='';
try
    dmt_vm_power_cal(fixture,condition,4*ones(numel(cfg.k),1),seed);
catch exception
    if ~strcmp(exception.identifier,expected),rethrow(exception);end
    id=exception.identifier;
end
one=struct('seed',seed,'target',condition.P_target,'identifier',id,'passed',strcmp(id,expected));
end

function one=checkCounters(cfg)
M=64*ones(numel(cfg.k),1);
n=cfg.payload_symbols*log2(M);
first=zeros(size(n));
second=first;
first(1)=1000;
second(1)=700;
[failed,~,low,upper]=dmt_t2_adjudicate(cfg,first+second,n+n,true,true);
[supported,~,~,zeroUpper]=dmt_t2_adjudicate(cfg,0*first,n+n,true,true);
edge=cfg;edge.targetBER=zeroUpper(1);
strict=dmt_t2_adjudicate(edge,0*first,n+n,true,true);
[powerMismatch,berState]=dmt_t2_adjudicate(cfg,0*first,n+n,true,false);
setup=[cfg.initial_A_symbols cfg.initial_B_symbols cfg.design_A_symbols cfg.design_D_symbols];
bits=sum(log2(M));
seconds=sum(setup)*(cfg.NFFT+cfg.NCP)/cfg.Fs;
rate=cfg.payload_symbols*bits/(cfg.payload_symbols*cfg.Ts+seconds+cfg.control_delay);
independent=cfg.payload_symbols*bits*cfg.Fs/ ...
    ((cfg.payload_symbols+sum(setup))*(cfg.NFFT+cfg.NCP));
one=struct('failed',failed,'supported',supported,'strict',strict, ...
    'power_mismatch',powerMismatch,'ber_state',berState,'zero_error_upper_bound',zeroUpper(1), ...
    'sample_setup_symbols',sum(setup),'sample_setup_seconds',seconds,'sample_cycle_rate_bps',rate);
tol=1e-12;
one.passed=dmt_to_count_valid(first,n,M,cfg.payload_symbols) && ...
    dmt_to_count_valid(second,n,M,cfg.payload_symbols) && ...
    failed=="ber_failed" && low(1)>cfg.targetBER && all(upper>0) && ...
    supported=="supported" && strict=="inconclusive" && ...
    powerMismatch=="power_mismatch" && berState=="supported" && ...
    all(abs(zeroUpper-cfg.Wilson_z^2./(2*n+cfg.Wilson_z^2))<=tol) && ...
    abs(independent-rate)<=tol*max(independent,1);
end

function one=checkCheckpoint(cfg)
folder=tempname;
mkdir(folder);
closer=onCleanup(@()rmdir(folder,'s')); %#ok<NASGU>
mkdir(fullfile(folder,'checkpoints'));
p=struct('phase','preflight','source_id',dmt_v13_hash('VCSEL checkpoint fixture'), ...
    'config_id',dmt_v13_hash(cfg),'seed_id',dmt_v13_hash([101 102]));
first=struct('fixture_slot',1,'tested_bits',[62;62],'error_bits',[0;3]);
second=struct('fixture_slot',2,'tested_bits',[62;62],'error_bits',[1;0]);
dmt_t2_record('save',folder,p,'Payload',1,first);
path=fullfile(folder,'checkpoints','payload_0001.mat');
initial=dmt_fb_filehash(path);
reopened=dmt_t2_record('load',folder,p,'Payload',1,[]);
missing=dmt_t2_record('load',folder,p,'Payload',2,[]);
if isempty(missing),dmt_t2_record('save',folder,p,'Payload',2,second);end
secondRead=dmt_t2_record('load',folder,p,'Payload',2,[]);
count=numel(dir(fullfile(folder,'checkpoints','*.mat')));
id='';
try
    dmt_t2_record('save',folder,p,'Payload',1,second);
catch exception
    if ~strcmp(exception.identifier,'DMT:V2Overwrite'),rethrow(exception);end
    id=exception.identifier;
end
one=struct('first_reopened',isequaln(first,reopened),'second_absent',isempty(missing), ...
    'second_committed',isequaln(second,secondRead),'first_preserved',strcmp(initial,dmt_fb_filehash(path)), ...
    'record_count',count,'overwrite_guard_id',id);
one.passed=one.first_reopened && one.second_absent && one.second_committed && ...
    one.first_preserved && count==2 && strcmp(id,'DMT:V2Overwrite');
end
