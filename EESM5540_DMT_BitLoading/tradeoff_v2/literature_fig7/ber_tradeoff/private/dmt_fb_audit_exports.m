function dmt_fb_audit_exports(folder,p,tables,action)
%DMT_FB_AUDIT_EXPORTS Publish or independently compare CSV and MAT exports.
assert(any(strcmp(action,{'write','verify'})));
write=strcmp(action,'write');
path=fullfile(folder,'tables.mat');
snapshot=struct('study',p.study,'phase',p.phase,'source_id',p.source_id, ...
    'config_id',p.config_id,'seed_id',p.seed_id,'tables',tables, ...
    'tables_hash',dmt_v13_hash(tables));
if write
    writeOrCheck(tables,'');
    dmt_v13_atomic_save(path,snapshot);
else
    saved=load(path,'checkpoint');
    assert(isequaln(saved.checkpoint,snapshot),'DMT:FBExportMAT', ...
        'MAT export differs from the checkpoint-derived tables.');
    dmt_fb_audit_csv(fullfile(folder,'source_manifest.csv'),p.source_manifest);
    dmt_fb_audit_csv(fullfile(folder,'seed_plan.csv'),p.plan);
    writeOrCheck(tables,'');
end

    function writeOrCheck(group,prefix)
        names=fieldnames(group);
        for j=1:numel(names)
            leaf=group.(names{j});
            stem=[prefix names{j}];
            if isstruct(leaf)
                writeOrCheck(leaf,[stem '_']);
            elseif write
                csv=fullfile(folder,[stem '.csv']);
                temp=[tempname(folder) '.csv'];
                cleanup=onCleanup(@()deleteIfPresent(temp));
                writetable(leaf,temp,'Delimiter',',','Encoding','UTF-8');
                [ok,message]=movefile(temp,csv,'f');
                assert(ok,'DMT:FBExportCSV','%s',message);
                clear cleanup;
            else
                dmt_fb_audit_csv(fullfile(folder,[stem '.csv']),leaf);
            end
        end
    end
end

function deleteIfPresent(file)
if isfile(file),delete(file);end
end
