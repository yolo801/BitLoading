function [cfg, receipt] = dmt_vm_three_order_band_gate(cfg,fit,evidenceDir,bandEndGHz,seed)
%DMT_VM_THREE_ORDER_BAND_GATE Audit the unchanged Case 2 FIR on this mask.
% An empty seed performs the coverage and fit audit without generating any
% waveform. Only a completed production-link fixture grants preflight pass.
if nargin<5,seed=[];end
receipt=struct('passed',false,'geometry_passed',false,'link_checked',false, ...
    'status','blocked_source','detail','','case_id',2,'band_end_GHz',bandEndGHz);
assert(isscalar(bandEndGHz) && ismember(bandEndGHz,[60 62]) && ...
    cfg.Fs==128e9 && cfg.NFFT==512 && cfg.NCP==16 && ...
    isequal(cfg.k(:),(1:240).') && cfg.Es==1 && cfg.rho==4, ...
    'DMT:VMThreeBandInput','Start with the verified 60 GHz configuration.');
base=cfg;
spacing=cfg.Fs/cfg.NFFT/1e9;
tones=1:round(bandEndGHz/spacing);
f=tones(:)*spacing;
assert(abs(f(end)-bandEndGHz)<1e-12 && tones(end)<cfg.NFFT/2);
receipt.active_k=tones(:);
receipt.frequencies_GHz=f;
receipt.tone_spacing_GHz=spacing;

sourceName='Fig2a_digitized.csv';
provenanceName='Fig2a_provenance.json';
sourcePath=fullfile(evidenceDir,sourceName);
provenancePath=fullfile(evidenceDir,provenanceName);
doi='10.1364/SPPCOM.2025.SpTh3E.4';
if ~isfile(sourcePath) || ~isfile(provenancePath)
    receipt.detail='The digitized public Fig. 2(a) source and its provenance are required.';
    return;
end
receipt.source_csv_sha256=dmt_fb_filehash(sourcePath);
receipt.provenance_sha256=dmt_fb_filehash(provenancePath);
receipt.source_DOI=doi;
if ~strcmpi(fit.source_DOI,doi) || ~strcmp(fit.source_csv,sourceName) || ...
    ~strcmp(fit.source_provenance,provenanceName) || ...
    ~strcmp(fit.digitized_sha256,receipt.source_csv_sha256) || ...
    ~strcmp(fit.provenance_sha256,receipt.provenance_sha256)
    receipt.detail='The digitized file, provenance, or DOI differs from the verified VCSEL source.';
    return;
end
source=readtable(sourcePath,'Delimiter',',','VariableNamingRule','preserve');
required={'case','frequency_GHz','gain_dB','segment_id'};
if ~all(ismember(required,source.Properties.VariableNames))
    receipt.detail='The Fig. 2(a) curve is missing its case, frequency, gain or path segment column.';
    return;
end
source=sortrows(source(source.('case')==2,:),'frequency_GHz');
x=source.frequency_GHz;
y=source.gain_dB;
if numel(x)<2 || any(~isfinite(x) | ~isfinite(y)) || any(diff(x)<=0)
    receipt.detail='The Case 2 coordinates are missing or invalid.';
    return;
end
receipt.source_frequency_range_GHz=[x(1),x(end)];
receipt.source_point_count=numel(x);
if f(1)<x(1) || f(end)>x(end)
    receipt.detail='At least one active tone lies outside the public Case 2 frequency coverage.';
    return;
end
% Preserve the original permitted dash-gap interpolation interval. This
% records the exact two observed points next to each active frequency.
maxGap=3;
receipt.max_allowed_interpolation_span_GHz=maxGap;
lower=zeros(size(f));upper=lower;
for j=1:numel(f)
    lower(j)=find(x<=f(j),1,'last');
    upper(j)=find(x>=f(j),1,'first');
end
receipt.source_bracket_low_GHz=x(lower);
receipt.source_bracket_high_GHz=x(upper);
receipt.source_bracket_spans_dash=source.segment_id(lower)~=source.segment_id(upper);
receipt.max_active_interpolation_span_GHz=max(x(upper)-x(lower));
receipt.edge_source_bracket_GHz=[x(lower(end)),x(upper(end))];
receipt.edge_source_bracket_spans_dash=receipt.source_bracket_spans_dash(end);
receipt.interpolation='Linear interpolation of reported gain in dB between native source samples.';
receipt.extrapolated_tones=0;
if receipt.max_active_interpolation_span_GHz>maxGap
    receipt.detail='An active-frequency interpolation bracket exceeds the original 3 GHz limit.';
    return;
end
receipt.status='blocked_fit';
cases=fit.cases;
if isstruct(cases),cases=num2cell(cases);end
ids=cellfun(@(one)one.case_id,cases);
assert(nnz(ids==2)==1,'DMT:VMThreeBandFit','Expected one verified Case 2 response.');
one=cases{ids==2};
h=reshape(one.taps,1,[]);
conditionIndex=find([base.conditions.case_id]==2 & [base.conditions.swing]==.5 & ...
    [base.conditions.q]==8 & [base.conditions.P_target]==1,1);
if isempty(conditionIndex)
    receipt.detail='The Case 2 medium-drive physical condition is unavailable.';
    return;
end
condition=base.conditions(conditionIndex);
receipt.FIR=h;
receipt.FIR_memory_samples=numel(h)-1;
receipt.FIR_group_delay_samples=(numel(h)-1)/2;
receipt.CP_samples=cfg.NCP;
receipt.linear_phase_assumption=true;
receipt.dc_gain=sum(h);
if ~one.passed || ~isreal(h) || any(~isfinite(h)) || mod(numel(h),2)~=1 || ...
    max(abs(h-fliplr(h)))>1e-12 || abs(sum(h)-1)>1e-12 || ...
    numel(h)-1>cfg.NCP || ~isequal(h,reshape(condition.h,1,[]))
    receipt.detail='The existing causal linear-phase Case 2 FIR fails identity, DC gain or CP coverage.';
    return;
end
receipt.source_gain_dB=interp1(x,y,f,'linear');
receipt.fitted_gain_dB=firDb(h,f,cfg.Fs);
receipt.residual_dB=receipt.fitted_gain_dB-receipt.source_gain_dB;
receipt.active_rms_limit_dB=1;
receipt.active_rms_dB=sqrt(mean(receipt.residual_dB.^2));
receipt.active_max_abs_dB=max(abs(receipt.residual_dB));
receipt.original_band_rms_dB=sqrt(mean(receipt.residual_dB(1:numel(base.k)).^2));
receipt.edge_gain_source_dB=receipt.source_gain_dB(end);
receipt.edge_gain_fit_dB=receipt.fitted_gain_dB(end);
receipt.edge_residual_dB=receipt.residual_dB(end);
new=tones(:)>max(base.k);
receipt.additional_tone_frequencies_GHz=f(new);
receipt.additional_tone_count=nnz(new);
receipt.additional_tone_gain_source_dB=receipt.source_gain_dB(new);
receipt.additional_tone_gain_fit_dB=receipt.fitted_gain_dB(new);
receipt.additional_tone_residual_dB=receipt.residual_dB(new);
if any(new)
    receipt.additional_tone_rms_dB=sqrt(mean(receipt.additional_tone_residual_dB.^2));
    receipt.additional_tone_max_abs_dB=max(abs(receipt.additional_tone_residual_dB));
end
receipt.minimum_active_gain_dB=min(receipt.fitted_gain_dB);
if any(~isfinite(receipt.residual_dB)) || receipt.active_rms_dB>1 || ...
    abs(receipt.original_band_rms_dB-one.active_rms_error_dB)>1e-7
    receipt.detail='The unchanged FIR fails the original-band receipt or the selected-band RMS criterion.';
    return;
end
% Re-run the original Case 2 feature criteria with the unchanged source.
dense=(15:.0125:53).';
reference=features(dense,interp1(x,y,dense,'linear'));
model=features(dense,firDb(h,dense,cfg.Fs));
receipt.source_notch=reference;
receipt.FIR_notch=model;
if ~reference.interior || ~model.interior || reference.notch_GHz<f(1) || ...
    model.notch_GHz<f(1) || reference.recovery_GHz>f(end) || model.recovery_GHz>f(end) || ...
    abs(model.notch_GHz-reference.notch_GHz)>2*spacing || ...
    abs(model.notch_dB-reference.notch_dB)>1 || model.recovery_rise_dB<2 || ...
    ~one.notch_and_recovery_passed
    receipt.detail='The selected band does not retain the original Case 2 notch and recovery.';
    return;
end
candidate=base;
if bandEndGHz==62
    candidate.k=tones;
    candidate.sigma_ref=sqrt(2*numel(tones)*candidate.Es/candidate.NFFT);
end
assert(base.sigma_ref==sqrt(2*numel(base.k)*base.Es/base.NFFT), ...
    'DMT:VMThreeBandNormalization','The verified reference amplitude does not match the original 240 tones.');
receipt.original_active_k_count=numel(base.k);
receipt.selected_active_k_count=numel(candidate.k);
receipt.original_sigma_ref=base.sigma_ref;
receipt.selected_sigma_ref=candidate.sigma_ref;
receipt.expected_ac_scale_ratio=base.sigma_ref/candidate.sigma_ref;
receipt.expected_ac_scale_change_dB=20*log10(receipt.expected_ac_scale_ratio);
receipt.geometry_passed=true;
if isempty(seed)
    cfg=candidate;
    receipt.status='geometry_passed';
    receipt.detail='The independent coverage and fit audit passed. No production fixture was run.';
    return;
end
assert(isscalar(seed) && isfinite(seed) && seed==fix(seed) && ...
    seed>=0 && seed<=double(intmax('uint32'))-8,'DMT:VMThreeBandSeed','Invalid mechanical fixture seed.');
receipt.link_checked=true;
receipt.status='blocked_link';
receipt.fixture_seeds=seed+(0:8);
link=cell(1,3);
for j=1:numel(link)
    link{j}=checkNoiseless(candidate,condition,candidate.Mset(j),seed+2*j-2,seed+2*j-1);
end
receipt.noiseless_link=[link{:}];
receipt.normalization=checkNormalization(base,candidate,condition,seed+6);
receipt.transmit_power=checkPower(base,candidate,condition,seed+7,seed+8);
if ~all([receipt.noiseless_link.passed]) || ~receipt.normalization.passed || ...
    ~receipt.transmit_power.passed
    receipt.detail='At least one production-link, CP, mask normalization, or optical power fixture failed.';
    return;
end
cfg=candidate;
receipt.passed=true;
receipt.status='passed';
receipt.detail='Source, unchanged FIR, CP, three-QAM link, AC scaling and calibrated optical mean passed.';
end

function db=firDb(h,f,fs)
db=20*log10(abs(exp((-2i*pi*1e9/fs)*f(:)*(0:numel(h)-1))*h(:)));
end

function result=features(f,db)
trough=find(f>=15 & f<=32);
recovery=find(f>=32 & f<=53);
[low,i]=min(db(trough));
[high,j]=max(db(recovery));
result=struct('notch_GHz',f(trough(i)),'notch_dB',low, ...
    'recovery_GHz',f(recovery(j)),'recovery_dB',high,'recovery_rise_dB',high-low, ...
    'interior',i>1 && i<numel(trough) && j>1 && j<numel(recovery));
end

function result=checkNoiseless(cfg,condition,order,trainingSeed,dataSeed)
M=order*ones(numel(cfg.k),1);
bias=1;
scale=.25;
symbols=[7 13 19];
assert(max(symbols)<=cfg.chunkSize);
A=dmt_v13_make_frame(cfg,M,symbols(1),dmt_v13_stream(cfg,trainingSeed));
stream=dmt_v13_stream(cfg,dataSeed);
[X1,bits1]=dmt_v13_make_frame(cfg,M,symbols(2),stream);
[X2,bits2]=dmt_v13_make_frame(cfg,M,symbols(3),stream);
[Ya,ma,state,da]=dmt_vm_link(cfg,condition,scale*A,bias,[],[],false,true);
[Y1,m1,state,d1]=dmt_vm_link(cfg,condition,scale*X1,bias,state,[],false,true);
[Y2,m2,~,d2]=dmt_vm_link(cfg,condition,scale*X2,bias,state,[],false,true);
known=A(cfg.k+1,:);
Hhat=sum(Ya.*conj(known),2)./sum(abs(known).^2,2);
H=scale*dmt_vm_drive_scale(cfg,condition)* ...
    (exp(-2i*pi*(cfg.k(:)/cfg.NFFT)*(0:numel(condition.h)-1))*condition.h(:));
X=[X1(cfg.k+1,:) X2(cfg.k+1,:)];
Y=[Y1 Y2];
Z=Y./Hhat;
assert(all(isfinite(Z(:))),'DMT:VMThreeBandLink','A selected tone cannot be equalized.');
bits=cellfun(@vertcat,bits1,bits2,'UniformOutput',false);
[e,n]=dmt_demod_errors(cfg,Z,bits,M);
tx=[da.p;d1.p;d2.p];
rx=[da.rx_before_adc;d1.rx_before_adc;d2.rx_before_adc];
convolved=conv(tx,condition.h(:));
reset=conv(d2.p,condition.h(:));
metric=[ma m1 m2];
unused=setdiff((1:cfg.NFFT).',[cfg.k(:)+1;cfg.NFFT-cfg.k(:)+1]);
frame=[A X1 X2];
result=struct('M',order,'training_seed',trainingSeed,'block_data_seed',dataSeed, ...
    'symbols_by_chunk',symbols,'fft_first_sample',cfg.NCP+1, ...
    'empty_dc_nyquist_guard',all(frame(unused,:)==0,'all'), ...
    'conjugate_symmetric',isequal(frame(cfg.NFFT-cfg.k+1,:),conj(frame(cfg.k+1,:))), ...
    'added_noise_energy',sum([metric.noise_sum_sq]), ...
    'clipped_samples',sum([metric.lower_clip_count])+sum([metric.upper_clip_count]), ...
    'adc_bypassed',isequal([da.adc_output;d1.adc_output;d2.adc_output],rx), ...
    'max_convolution_error',max(abs(convolved(1:numel(rx))-rx)), ...
    'state_reset_difference',max(abs(reset(1:numel(d2.p))-d2.rx_before_adc)), ...
    'max_complex_channel_error',max(abs(Hhat-H)), ...
    'max_block_fft_error',max(abs(Y-H.*X),[],'all'), ...
    'max_zf_error',max(abs(Z-X),[],'all'), ...
    'payload_errors',sum(e),'payload_bits',sum(n));
tol=5e-10;
result.passed=result.empty_dc_nyquist_guard && result.conjugate_symmetric && ...
    result.added_noise_energy==0 && result.clipped_samples==0 && result.adc_bypassed && ...
    result.max_convolution_error<=tol && result.state_reset_difference>tol && ...
    result.max_complex_channel_error<=tol && result.max_block_fft_error<=tol && ...
    result.max_zf_error<=tol && result.payload_errors==0 && ...
    all(n==sum(symbols(2:end))*log2(order));
end

function result=checkNormalization(base,candidate,condition,seed)
% Use exactly the same 240-carrier waveform in both production link calls
% to isolate drive normalization from the eight carriers' new information.
M=4*ones(numel(base.k),1);
bias=1;
x=.25*dmt_v13_make_frame(base,M,11,dmt_v13_stream(base,seed));
[~,mBase,~,dBase]=dmt_vm_link(base,condition,x,bias,[],[],false,true);
[~,mNew,~,dNew]=dmt_vm_link(candidate,condition,x,bias,[],[],false,true);
baseDrive=dBase.p_raw-bias;
newDrive=dNew.p_raw-bias;
scale=dmt_vm_drive_scale(candidate,condition);
ratio=base.sigma_ref/candidate.sigma_ref;
result=struct('seed',seed,'shared_waveform_active_k_count',numel(base.k), ...
    'original_drive_scale',dmt_vm_drive_scale(base,condition), ...
    'selected_drive_scale',scale,'expected_ratio',ratio, ...
    'observed_ratio',sqrt(sum(newDrive.^2)/sum(baseDrive.^2)), ...
    'max_drive_delta_error',max(abs(newDrive-ratio*baseDrive)), ...
    'max_production_formula_error',max(abs(newDrive-scale*dNew.tx_serial)), ...
    'same_serial_waveform',max(abs(dBase.tx_serial-dNew.tx_serial))<5e-12, ...
    'zero_clipping',sum([mBase.lower_clip_count mBase.upper_clip_count ...
        mNew.lower_clip_count mNew.upper_clip_count])==0);
result.passed=result.same_serial_waveform && result.zero_clipping && ...
    abs(result.observed_ratio-result.expected_ratio)<5e-12 && ...
    result.max_drive_delta_error<5e-12 && result.max_production_formula_error<5e-12;
end

function result=checkPower(base,candidate,condition,originalSeed,selectedSeed)
% Verify the original TX bias calibration with independent, fully occupied
% QPSK masks. Only this fixture uses the local short symbol budget.
base.power_cal_symbols=128;
candidate.power_cal_symbols=128;
original=replayCalibration(base,condition,originalSeed);
selected=replayCalibration(candidate,condition,selectedSeed);
result=struct('fixture_target',condition.P_target,'production_power_tolerance',base.power_cal_tolerance, ...
    'original',original,'selected',selected, ...
    'observed_useful_drive_rms_ratio',selected.useful_drive_rms/original.useful_drive_rms);
result.passed=original.passed && selected.passed && ...
    abs(result.observed_useful_drive_rms_ratio-1)<5e-12;
end

function row=replayCalibration(cfg,condition,seed)
n=cfg.power_cal_symbols;
assert(n<=cfg.chunkSize);
M=4*ones(numel(cfg.k),1);
power=dmt_vm_power_cal(cfg,condition,M,seed);
X=dmt_v13_make_frame(cfg,M,n,dmt_v13_stream(cfg,seed));
[~,m,~,debug]=dmt_vm_link(cfg,condition,X,power.b,[],[],false,true);
drive=reshape(debug.p_raw-power.b,cfg.NFFT+cfg.NCP,n);
useful=drive(cfg.NCP+1:end,:);
replayed=m.tx_sum/m.sample_count;
target=condition.P_target;
row=struct('data_seed',seed,'symbols',n,'active_k_count',numel(cfg.k), ...
    'sample_count_with_CP',m.sample_count,'calibrated_bias',power.b, ...
    'calibrated_mean',power.actual_mean,'replayed_mean',replayed, ...
    'calibrated_relative_error',power.relative_error,'replayed_relative_error',replayed/target-1, ...
    'useful_drive_rms',sqrt(mean(useful.^2,'all')), ...
    'expected_useful_drive_rms',condition.swing*target/cfg.rho, ...
    'clipping_count',m.lower_clip_count+m.upper_clip_count);
row.passed=power.monotone && power.reachable && power.target==target && ...
    m.sample_count==(cfg.NFFT+cfg.NCP)*n && power.sample_count==m.sample_count && ...
    abs(row.calibrated_relative_error)<=cfg.power_cal_tolerance && ...
    abs(row.replayed_relative_error)<=cfg.power_cal_tolerance && ...
    abs(row.calibrated_mean-row.replayed_mean)<5e-12 && ...
    abs(row.useful_drive_rms-row.expected_useful_drive_rms)<5e-12 && ...
    power.lower_clip_count==m.lower_clip_count && power.upper_clip_count==m.upper_clip_count;
end
