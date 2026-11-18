function fit = dmt_vm_fit_audit(folder,cfg,fit)
%DMT_VM_FIT_AUDIT Recompute the fit error and the Case 2 feature gate.
assert(strcmp(fit.source_csv,'Fig2a_digitized.csv') && ...
    strcmp(fit.source_provenance,'Fig2a_provenance.json') && ...
    strcmpi(fit.source_DOI,'10.1364/SPPCOM.2025.SpTh3E.4') && ...
    strcmp(fit.digitized_sha256,dmt_fb_filehash(fullfile(folder,fit.source_csv))) && ...
    strcmp(fit.provenance_sha256,dmt_fb_filehash(fullfile(folder,fit.source_provenance))) && ...
    strcmp(fit.active_response_sha256,dmt_fb_filehash(fullfile(folder,'active_response.csv'))), ...
    'DMT:VMFitSource','The accepted fit must use the supplied Fig. 2(a) source.');
files=dir(folder);
files=files(~[files.isdir]);
names=sort(string({files.name}));
hashes=strings(numel(names),1);
for j=1:numel(names),hashes(j)=dmt_fb_filehash(fullfile(folder,names(j)));end
fit.evidence_files=names(:);
fit.evidence_sha256=hashes;
source=readtable(fullfile(folder,fit.source_csv),'VariableNamingRule','preserve');
targets=readtable(fullfile(folder,'active_response.csv'),'VariableNamingRule','preserve');
ids=cellfun(@(one)one.case_id,fit.cases);
frequency=cfg.k(:)*cfg.Fs/cfg.NFFT/1e9;
resolution=cfg.Fs/cfg.NFFT/1e9;
fit.audited_active_rms_dB=nan(1,2);
for id=1:2
    samples=sortrows(source(source.('case')==id,:),'frequency_GHz');
    x=samples.frequency_GHz;
    y=samples.gain_dB;
    assert(all(isfinite(x) & isfinite(y)) && all(diff(x)>0) && ...
        min(frequency)>=x(1) && max(frequency)<=x(end) && max(diff(x))<=3, ...
        'DMT:VMFitCoverage','Case %d lacks continuous Fig. 2(a) coverage.',id);
    one=fit.cases{ids==id};
    h=one.taps(:);
    assert(mod(numel(h),2)==1 && max(abs(h-flipud(h)))<=1e-12 && ...
        one.fir_memory_samples==numel(h)-1 && one.group_delay_samples==(numel(h)-1)/2, ...
        'DMT:VMFitPhase','Case %d does not have the declared causal linear-phase FIR.',id);
    data=targets(targets.case_id==id,:);
    modeledDb=firDb(h,frequency);
    sourceDb=interp1(x,y,frequency,'linear');
    errorDb=modeledDb-sourceDb;
    rms=sqrt(mean(errorDb.^2));
    assert(isequal(data.k,cfg.k(:)) && isequal(data.frequency_GHz,frequency) && ...
        all(abs(data.source_dB-sourceDb)<1e-7) && all(abs(data.fit_dB-modeledDb)<1e-7) && ...
        all(abs(data.residual_dB-errorDb)<1e-7) && rms<=1 && abs(rms-one.active_rms_error_dB)<=1e-7 && ...
        abs(max(abs(errorDb))-one.active_max_abs_error_dB)<=1e-7, ...
        'DMT:VMFitResidual','Case %d active-band FIR error exceeds or differs from its receipt.',id);
    fit.audited_active_rms_dB(id)=rms;
    if id==2
        dense=(0:.0125:64).';
        assert(dense(1)>=x(1) && dense(end)<=x(end));
        measured=features(dense,interp1(x,y,dense,'linear'));
        modeled=features(dense,firDb(h,dense));
        assert(abs(measured.notch_GHz-cfg.case2_notch_GHz)<=.0125 && ...
            abs(modeled.notch_GHz-measured.notch_GHz)<=2*resolution && ...
            abs(modeled.notch_dB-measured.notch_dB)<=1 && modeled.recovery_rise_dB>=2 && ...
            measured.notch_GHz>=frequency(1) && measured.recovery_GHz<=frequency(end) && ...
            modeled.notch_GHz>=frequency(1) && modeled.recovery_GHz<=frequency(end) && ...
            one.notch_and_recovery_passed, ...
            'DMT:VMFitNotch','Case 2 did not retain the first measured notch and rebound.');
        fit.audited_case2_source=measured;
        fit.audited_case2_model=modeled;
    end
end
end

function db=firDb(h,frequency)
response=exp(-2i*pi*frequency(:)/128*(0:numel(h)-1))*h;
db=20*log10(abs(response));
end

function f=features(freq,db)
trough=find(freq>=15 & freq<=32);
recovery=find(freq>=32 & freq<=53);
[low,i]=min(db(trough));
[high,j]=max(db(recovery));
assert(i>1 && j>1 && i<numel(trough) && j<numel(recovery), ...
    'DMT:VMFitNotch','A required interior feature was not resolved.');
f=struct('notch_GHz',freq(trough(i)),'notch_dB',low,'recovery_GHz',freq(recovery(j)), ...
    'recovery_dB',high,'recovery_rise_dB',high-low);
end
