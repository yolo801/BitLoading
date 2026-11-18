function tables = dmt_t2_export(folder,cfg,phase,plan,shared,designs,runs)
%DMT_T2_EXPORT Tables derive only from executed and saved evidence.
tables=dmt_t2_tables(cfg,phase,plan,shared,designs,runs);
names=fieldnames(tables);
for j=1:numel(names)
    name=names{j};
    assert(istable(tables.(name)));
    writetable(tables.(name),fullfile(folder,[name '.csv']));
end
snapshot=struct('phase',phase,'tables',tables,'tables_hash',dmt_v13_hash(tables));
dmt_v13_atomic_save(fullfile(folder,'tables.mat'),snapshot);
end
