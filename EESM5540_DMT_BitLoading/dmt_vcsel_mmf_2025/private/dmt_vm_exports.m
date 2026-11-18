function tables=dmt_vm_exports(folder,p,tables,action)
%DMT_VM_EXPORTS Publish, check or read back source-bound result tables.
action=validatestring(action,{'write','verify','read'});
snapshot=struct('study',p.version,'phase',p.phase,'source_id',p.source_id, ...
    'config_id',p.config_id,'seed_id',p.seed_id,'tables',tables,'tables_hash',dmt_v13_hash(tables));
path=fullfile(folder,'tables.mat');
if strcmp(action,'verify')
    previous=load(path,'checkpoint');
    assert(isequaln(previous.checkpoint,snapshot),'DMT:VMExportMAT','Saved tables differ from computed records.');
end
for name=fieldnames(tables).'
    label=name{1};
    t=tables.(label);
    filename=fullfile(folder,[label '.csv']);
    if strcmp(action,'write')
        writetable(t,filename,'Delimiter',',','Encoding','UTF-8');
    else
        dmt_fb_audit_csv(filename,t);
        if strcmp(action,'read'),tables.(label)=readCSV(filename,t);end
    end
end
if strcmp(action,'write'),dmt_v13_atomic_save(path,snapshot);end
end

function t=readCSV(filename,template)
if isempty(template),t=template;return;end
opts=detectImportOptions(filename,'Delimiter',',','Encoding','UTF-8','VariableNamingRule','preserve');
opts=setvartype(opts,opts.VariableNames,'string');
t=readtable(filename,opts);
for name=template.Properties.VariableNames
    label=name{1};
    column=template.(label);
    v=t.(label);
    if isnumeric(column) || islogical(column)
        v=lower(v);
        v(v=="true")="1";v(v=="false")="0";
        v=str2double(v);
        if islogical(column),v=logical(v);end
    else
        v(ismissing(v))="";
    end
    t.(label)=v;
end
end
