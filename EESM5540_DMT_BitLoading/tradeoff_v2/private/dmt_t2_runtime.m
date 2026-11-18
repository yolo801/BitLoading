function environment = dmt_t2_runtime(root)
%DMT_T2_RUNTIME Record the actual MATLAB and project resolution used by v2.
names = {'dmt_t2_config','dmt_t2_plan','dmt_t2_design','dmt_t2_payload', ...
    'dmt_to_initial','dmt_to_design','dmt_to_measure','dmt_to_link', ...
    'dmt_to_quantize','dmt_v13_make_frame','dmt_v13_stream','qammod','qamdemod'};
template = struct('name','','first','','all',{{}});
resolved = repmat(template,1,numel(names));
for j = 1:numel(names)
    name = names{j};
    first = which(name);
    paths = which(name,'-all');
    assert(~isempty(first),'DMT:V2MissingFunction','MATLAB cannot resolve %s.',name);
    if ischar(paths), paths = {paths}; end
    if startsWith(name,'dmt_')
        actualFile = java.io.File(first);
        expectedFile = java.io.File(fullfile(root,'private',[name '.m']));
        a = char(actualFile.getCanonicalPath());
        b = char(expectedFile.getCanonicalPath());
        matches = strcmp(a,b);
        if ispc, matches = strcmpi(a,b); end
        assert(matches,'DMT:V2ShadowedFunction','Unexpected path for %s: %s.',name,first);
    else
        assert(startsWith(first,[matlabroot filesep 'toolbox' filesep],'IgnoreCase',ispc), ...
            'DMT:V2ShadowedQAM','Expected toolbox function %s, found %s.',name,first);
    end
    resolved(j).name = name;
    resolved(j).first = first;
    resolved(j).all = paths;
end
assert(~isempty(ver('comm')),'DMT:V2Toolbox','Communications Toolbox is required.');
environment = struct('version',version,'release',version('-release'), ...
    'matlabroot',matlabroot,'toolboxes',ver,'computer',computer,'pwd',pwd, ...
    'resolved_functions',resolved);
end
