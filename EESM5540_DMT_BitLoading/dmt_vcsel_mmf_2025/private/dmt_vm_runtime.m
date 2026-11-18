function environment = dmt_vm_runtime(root)
% Record actual MATLAB resolution, including any shadowed alternatives.
names={'dmt_vm_config','dmt_vm_plan','dmt_vm_initial','dmt_vm_design','dmt_vm_measure', ...
    'dmt_vm_link','dmt_vm_power_cal','dmt_vm_tables','dmt_v13_make_frame', ...
    'dmt_v13_stream','qammod','qamdemod'};
result=repmat(struct('name','','first','','all',{{}}),numel(names),1);
for j=1:numel(names)
    name=names{j};
    first=which(name);
    paths=which(name,'-all');
    assert(~isempty(first),'DMT:VMRuntime','MATLAB cannot resolve %s.',name);
    if ischar(paths),paths={paths};end
    if startsWith(name,'dmt_')
        expected=canonical(fullfile(root,'private',[name '.m']));
        found=canonical(first);
        matches=strcmp(expected,found) || (ispc && strcmpi(expected,found));
    else
        matches=startsWith(first,[matlabroot filesep 'toolbox' filesep],'IgnoreCase',ispc);
    end
    assert(matches,'DMT:VMRuntime','Unexpected MATLAB path for %s: %s.',name,first);
    result(j).name=name;
    result(j).first=first;
    result(j).all=paths;
end
assert(~isempty(ver('comm')),'DMT:VMRuntime','Communications Toolbox is required.');
environment=struct('version',version,'release',version('-release'),'matlabroot',matlabroot, ...
    'pwd',pwd,'toolboxes',ver,'computer',computer,'resolved_functions',result);
end

function path=canonical(path)
file=java.io.File(path);
path=char(file.getCanonicalPath());
end
