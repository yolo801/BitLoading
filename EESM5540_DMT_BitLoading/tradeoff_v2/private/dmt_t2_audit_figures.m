function info = dmt_t2_audit_figures(folder,phase,cfg,tables)
%DMT_T2_AUDIT_FIGURES Audit the declared figure CSV against tables and files.
path=fullfile(folder,'figure_manifest.csv');
file=java.io.File(path);
if ~file.isAbsolute(),file=java.io.File(fullfile(pwd,path));end
path=char(file.getCanonicalPath());
required={'phase','figure','status','reason','data_hash', ...
    'png_sha256','pdf_sha256','svg_sha256'};
fid=fopen(path,'r','n','UTF-8');
assert(fid>=0,'DMT:V2FigureManifest','Cannot open %s.',path);
closer=onCleanup(@()fclose(fid));
header=fgetl(fid);
clear closer;
assert(ischar(header),'DMT:V2FigureHeader','The figure manifest has no header: %s.',path);
fprintf('Figure manifest path: %s\nCSV first line: %s\n',path,header);
columns=strsplit(strtrim(header),',','CollapseDelimiters',false);
assert(isequal(sort(columns),sort(required)), ...
    'DMT:V2FigureHeader','Invalid figure CSV columns in %s: %s.',path,header);

% The first line has already supplied the exact names. Import line 2 onward
% with the declared comma delimiter and text types, without header inference.
opts=delimitedTextImportOptions('NumVariables',numel(columns));
opts.Delimiter=',';
opts.DataLines=[2 Inf];
opts.VariableNames=columns;
opts.VariableTypes=repmat({'string'},size(columns));
opts.ExtraColumnsRule='error';
opts.EmptyLineRule='read';
optionsText='encoding=UTF-8, delimiter=comma, names=validated line 1, data lines=[2 Inf], all columns=string, extra columns=error, empty lines=read';
fprintf('Figure manifest import: %s\n',optionsText);
manifest=readtable(path,opts,'Encoding','UTF-8');
importedNames=manifest.Properties.VariableNames;
fprintf('Imported table size: %d x %d\nImported variables: %s\n', ...
    height(manifest),width(manifest),strjoin(importedNames,', '));
assert(isequal(importedNames,columns), ...
    'DMT:V2FigureSchema','Imported figure CSV columns differ from the header in %s.',path);
info=struct('path',path,'first_line',header,'import_options',optionsText, ...
    'size',size(manifest),'variable_names',{importedNames},'manifest',manifest);

stems=["subcarrier_snr_bit_allocation_ber_margin";"supported_calibrations_power_adc"; ...
    "qualified_cycle_rate_measured_power"];
assert(isequal(sort(string(manifest.figure)),sort(stems)) && ...
    all(string(manifest.phase)==string(phase)) && ...
    all(string(manifest.data_hash)==string(dmt_v13_hash(tables))), ...
    'DMT:V2Plots','Figure plan or table identity differs.');
point=cfg.representative;
referenceRows=@(t)t.P_target==point.P_target & t.q==point.q & t.calibration_id==point.calibration_id;
hasReference=any(referenceRows(tables.snr)) || any(referenceRows(tables.profiles)) || ...
    any(referenceRows(tables.pool)) || any(referenceRows(tables.summary) & tables.summary.state~="incomplete");
hasRecords=~isempty(tables.profiles) || ~isempty(tables.seed) || ~isempty(tables.snr) || ...
    any(tables.summary.state~="incomplete");
planned=[hasReference;hasRecords;any(tables.scenario.qualified)];
for j=1:height(manifest)
    stem=char(manifest.figure(j));
    status=string(manifest.status(j));
    assert(planned(stems==string(stem))==(status=="written"), ...
        'DMT:V2PlotAvailability','Figure status differs from its saved data: %s.',stem);
    if status=="written"
        for format={'png','pdf','svg'}
            ext=format{1}; name=[ext '_sha256'];
            path=fullfile(folder,[stem '.' ext]);
            fid=fopen(path,'rb');assert(fid>=0,'DMT:V2MissingFigure','Missing %s.',path);
            closer=onCleanup(@()fclose(fid));
            raw=fread(fid,Inf,'*uint8');clear closer;
            assert(~isempty(raw) && strcmp(dmt_sha256(raw),char(manifest.(name)(j))), ...
                'DMT:V2FigureHash','Figure file differs: %s.',path);
        end
    else
        assert(status=="not_available" && ~ismissing(manifest.reason(j)) && ...
            strlength(string(manifest.reason(j)))>0,'DMT:V2FigureStatus','Invalid plot status.');
        for format={'png','pdf','svg'}
            assert(~isfile(fullfile(folder,[stem '.' format{1}])));
        end
    end
end
end
