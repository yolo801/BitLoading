function [report,tables] = verify_dmt_vcsel_mmf_2025(folder,requireFigures)
%VERIFY_DMT_VCSEL_MMF_2025 Recompute formal results without sending symbols.
if nargin<2,requireFigures=true;end
folder=char(string(folder));
root=fileparts(mfilename('fullpath'));
tables=struct();
report=struct('output_dir',folder,'phase','','valid',false,'data_integrity_valid',false, ...
    'acquisition_complete',false,'figures_valid',false,'fit_passed',false, ...
    'planned',0,'completed',0,'design_rejected',0,'power_error',0,'execution_error',0, ...
    'incomplete',0,'qualified',0,'source_id','','config_id','','mechanical_sha256','','detail','');
try
    saved=load(fullfile(folder,'Protocol.mat'),'checkpoint');
    p=saved.checkpoint;
    report.phase=p.phase;
    report.planned=p.planned_payload_slots;
    report.incomplete=p.planned_payload_slots;
    report.source_id=p.source_id;
    report.config_id=p.config_id;
    dmt_vm_identity(root,folder,p);
    report.fit_passed=true;
    report.mechanical_sha256=dmt_vm_gates(folder,p);
    log=fileread(fullfile(folder,'run.log'));
    if strcmp(p.phase,'preflight')
        assert(isempty(dir(fullfile(folder,'checkpoints','*.mat'))) && ...
            contains(log,'VCSEL PREFLIGHT COMPLETE'),'DMT:VMPreflightComplete','Preflight completion evidence is missing.');
        report.data_integrity_valid=true;
        report.acquisition_complete=true;
        report.valid=true;
        report.detail='Recorded production mechanical and strategy preflight passed.';
        return;
    end
    records=dmt_vm_records(folder,p,'audit');
    [tables,stats]=dmt_vm_tables(p.cfg,p.plan,records);
    for key=fieldnames(stats).'
        name=key{1};
        report.(name)=stats.(name);
    end
    if ~report.acquisition_complete
        report.detail='Available records were audited. Planned acquisition remains incomplete.';
        return;
    end
    report.data_integrity_valid=false;
    dmt_vm_exports(folder,p,tables,'verify');
    marker=sprintf('VCSEL ACQUISITION COMPLETE | %s | sent=%d rejected=%d planned=%d', ...
        p.phase,report.completed,report.design_rejected,report.planned);
    assert(contains(log,marker),'DMT:VMCompletionLog','The log lacks the exact acquisition end record.');
    if strcmp(p.phase,'pilot')
        saved=load(fullfile(folder,'pilot_timing.mat'),'checkpoint');
        timing=saved.checkpoint;
        assert(timing.planning_only && timing.pilot_sent==report.completed && timing.wall_seconds>=0 && ...
            (isfinite(timing.formal_seconds_estimate) || timing.resumed), ...
            'DMT:VMPilotTiming','Pilot timing evidence is invalid.');
        report.pilot_timing=timing;
    end
    report.data_integrity_valid=true;
    if strcmp(p.phase,'formal') && requireFigures
        dmt_vm_graphics(folder,p.cfg,tables,'verify');
        report.figures_valid=true;
    end
    report.valid=true;
    report.detail='Protocol, source, phase gates, stored records and exact counter exports agree.';
catch ME
    report.detail=getReport(ME,'extended','hyperlinks','off');
end
end
