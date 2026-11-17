function environment=dmt_to_runtime(root)
%DMT_TO_RUNTIME Record actual MATLAB/toolbox and private resolution at runtime.
environment=struct('version',version,'release',version('-release'),'matlabroot',matlabroot, ...
    'pwd',pwd,'toolboxes',ver,'computer',computer,'resolved_functions',struct([]));
names={'dmt_to_config','dmt_to_initial','dmt_to_design','dmt_to_link','dmt_to_measure', ...
    'dmt_to_power_cal','dmt_to_payload','dmt_to_validate','dmt_to_tables', ...
    'dmt_v13_make_frame','dmt_v13_stream','dmt_demod_errors','dmt_qam_ber','dmt_wilson','qammod','qamdemod'};
for j=1:numel(names)
    first=which(names{j});allPaths=which(names{j},'-all');
    if ischar(allPaths),allPaths={allPaths};end
    environment.resolved_functions(j)=struct('name',names{j},'first',first,'all',{allPaths});
    assert(~isempty(first),'DMT:TradeoffUnresolvedFunction','MATLAB cannot resolve %s.',names{j});
    if startsWith(names{j},'dmt_')
        expected=fullfile(root,'private',[names{j} '.m']);
        actualFile=java.io.File(first);expectedFile=java.io.File(expected);
        assert(strcmpi(char(actualFile.getCanonicalPath()),char(expectedFile.getCanonicalPath())), ...
            'DMT:TradeoffShadowedFunction','Unexpected private resolution for %s: %s',names{j},first);
    else
        assert(startsWith(first,[matlabroot filesep 'toolbox' filesep],'IgnoreCase',ispc), ...
            'DMT:TradeoffShadowedQAM','Use the installed Communications Toolbox %s, found %s.',names{j},first);
    end
end
end
