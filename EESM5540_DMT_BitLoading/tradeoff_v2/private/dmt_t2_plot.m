function manifest = dmt_t2_plot(cfg,phase,tables,outDir)
%DMT_T2_PLOT Export the three main-study figures from one phase's saved tables.
phase = validatestring(phase,{'preflight','formal'});
if ~isfolder(outDir), mkdir(outDir); end
stems = ["subcarrier_snr_bit_allocation_ber_margin"; ...
    "supported_calibrations_power_adc"; "qualified_cycle_rate_measured_power"];
manifest = table(repmat(string(phase),3,1),stems,repmat("not_available",3,1), ...
    strings(3,1),repmat(string(dmt_v13_hash(tables)),3,1),strings(3,1), ...
    strings(3,1),strings(3,1),'VariableNames',{'phase','figure','status', ...
    'reason','data_hash','png_sha256','pdf_sha256','svg_sha256'});
testOnly = strcmp(phase,'preflight');
reference = cfg.representative;
atReference = @(x) x.P_target==reference.P_target & x.q==reference.q & ...
    x.calibration_id==reference.calibration_id;
hasReference = any(atReference(tables.snr)) || any(atReference(tables.profiles)) || ...
    any(atReference(tables.pool)) || any(atReference(tables.summary) & ...
    tables.summary.state~="incomplete");
hasStudyData = ~isempty(tables.profiles) || ~isempty(tables.seed) || ...
    ~isempty(tables.snr) || any(tables.summary.state~="incomplete");
qualified = tables.scenario.qualified;
assert(~testOnly || ~any(qualified),'DMT:V2FigurePhase','Preflight cannot qualify a formal operating point.');
enabled = [hasReference;hasStudyData;any(qualified)];
manifest.reason = ["No actual records at the predeclared reference condition."; ...
    "No actual design or payload records for this phase."; ...
    "No formal condition qualified across all five calibrations."];
if testOnly
    manifest.reason(3) = "test_only: the preflight plan does not supply five formal calibrations.";
end
draw = {@(f) referenceFigure(f,cfg,tables,atReference,testOnly), ...
    @(f) calibrationFigure(f,cfg,tables,testOnly), ...
    @(f) rateFigure(f,cfg,tables,testOnly)};
sizes = [7.7 6.5;8.7 4.1;8.7 3.7];
for j=1:numel(stems)
    if ~enabled(j), continue; end
    fig = figure('Visible','off','Color','white','Units','inches', ...
        'Position',[1 1 sizes(j,:)],'PaperPositionMode','auto');
    cleanup = onCleanup(@()close(fig));
    try
        draw{j}(fig);
        basename = fullfile(outDir,char(stems(j)));
        exportgraphics(fig,[basename '.png'],'Resolution',300,'BackgroundColor','white');
        exportgraphics(fig,[basename '.pdf'],'ContentType','vector','BackgroundColor','white');
        print(fig,[basename '.svg'],'-dsvg','-painters');
        manifest.png_sha256(j) = fileHash([basename '.png']);
        manifest.pdf_sha256(j) = fileHash([basename '.pdf']);
        manifest.svg_sha256(j) = fileHash([basename '.svg']);
        manifest.status(j) = "written";
        manifest.reason(j) = "Rendered from saved records for the declared phase.";
    catch ME
        manifest.status(j) = "failed";
        manifest.reason(j) = string(ME.message);
        writetable(manifest,fullfile(outDir,'figure_manifest.csv'));
        rethrow(ME);
    end
    clear cleanup;
end
writetable(manifest,fullfile(outDir,'figure_manifest.csv'));
writeCaptions(cfg,testOnly,outDir,manifest);
end

function referenceFigure(fig,cfg,t,atReference,testOnly)
colors = strategyColors();
labels = strategyLabels();
markers = {'o','s','^'};
styles = {'-','--','-.'};
reference = cfg.representative;
layout = tiledlayout(fig,3,1,'TileSpacing','compact','Padding','compact');
title(layout,phaseTitle('Subcarrier SNR, Bit Allocation, and BER Margin',testOnly), ...
    'Color','black','FontSize',13);
subtitle(layout,sprintf('Predeclared example: target power %.1f (normalized), %d-bit ADC, calibration %d', ...
    reference.P_target,reference.q,reference.calibration_id),'Color','black');
axes1 = nexttile(layout); hold(axes1,'on');
axes2 = nexttile(layout); hold(axes2,'on');
axes3 = nexttile(layout); hold(axes3,'on');
xLimits = [min(cfg.k) max(cfg.k)];
referenceSNR = sortrows(t.snr(atReference(t.snr),:),'k');
if isempty(referenceSNR)
    note(axes1,'No saved shared B0 estimate at the reference condition.');
else
    assert(isequal(referenceSNR.k,cfg.k(:)) && all(isfinite(referenceSNR.SNR_dB)));
    plot(axes1,referenceSNR.k,referenceSNR.SNR_dB,'-d','Color',[.12 .12 .12], ...
        'LineWidth',1.2,'MarkerSize',4,'DisplayName','Shared B0 SNR');
    thresholds = [referenceSNR.threshold_M4_dB(1) referenceSNR.threshold_M16_dB(1) ...
        referenceSNR.threshold_M64_dB(1)];
    assert(all(isfinite(thresholds)));
    thresholdLabels = {'QPSK threshold','16-QAM threshold','64-QAM threshold'};
    for s=1:numel(thresholds)
        plot(axes1,xLimits,[thresholds(s) thresholds(s)],styles{s},'Color',colors(s,:), ...
            'LineWidth',1.1,'DisplayName',thresholdLabels{s});
    end
    legendStyle(legend(axes1,'Location','best','NumColumns',2));
end
ylabel(axes1,'Effective SNR (dB)');
title(axes1,'Shared B0 estimate and initial thresholds including 1 dB margin');
summary = t.summary(atReference(t.summary),:);
profiles = t.profiles(atReference(t.profiles),:);
pool = t.pool(atReference(t.pool),:);
noBits = strings(0,1);
noBER = strings(0,1);
shownBits = false;
shownBER = false;
boundRange = 1;
for s=1:numel(cfg.scheme_names)
    key = string(cfg.scheme_names{s});
    orders = sortrows(profiles(profiles.scheme==key,:),'k');
    ber = sortrows(pool(pool.scheme==key,:),'k');
    status = summary(summary.scheme==key,:);
    if isempty(status)
        reason = "not planned";
    else
        assert(height(status)==1);
        reason = string(status.state);
        if reason=="design_rejected"
            reason = reason+" ("+string(status.design_status)+")";
        end
        reason = replace(reason,"_"," ");
    end
    if isempty(orders)
        noBits(end+1,1) = string(labels{s})+": "+reason; %#ok<AGROW>
    else
        assert(isequal(orders.k,cfg.k(:)) && all(ismember(orders.bits_k,log2(cfg.Mset))));
        stairs(axes2,orders.k,orders.bits_k,'LineStyle',styles{s},'Marker',markers{s}, ...
            'Color',colors(s,:),'LineWidth',1.2,'MarkerSize',4,'DisplayName',labels{s});
        shownBits = true;
    end
    if isempty(ber)
        noBER(end+1,1) = string(labels{s})+": "+reason; %#ok<AGROW>
    else
        assert(isequal(ber.k,cfg.k(:)) && all(isfinite(ber.CI_high) & ber.CI_high>0));
        relativeUpper = ber.CI_high/cfg.targetBER;
        semilogy(axes3,ber.k,relativeUpper,'LineStyle',styles{s},'Marker',markers{s}, ...
            'Color',colors(s,:),'LineWidth',1.15,'MarkerSize',4,'DisplayName',labels{s});
        shownBER = true;
        boundRange = [boundRange;relativeUpper(:)]; %#ok<AGROW>
    end
end
ylabel(axes2,'Bits / subcarrier');
yticks(axes2,log2(cfg.Mset));
ylim(axes2,[1.4 6.6]);
panelTitle(axes2,'Frozen bit allocation',noBits,shownBits);
if shownBits, legendStyle(legend(axes2,'Location','best','NumColumns',3)); end
ylabel(axes3,'Wilson upper BER bound / target');
set(axes3,'YScale','log');
yline(axes3,1,':k','Target ratio = 1','HandleVisibility','off', ...
    'LabelHorizontalAlignment','left');
ylim(axes3,[min(.5,.8*min(boundRange)) max(2,1.25*max(boundRange))]);
panelTitle(axes3,'Pooled payload BER upper bounds',noBER,shownBER);
if shownBER, legendStyle(legend(axes3,'Location','best','NumColumns',3)); end
for ax=[axes1 axes2 axes3]
    style(ax);xlim(ax,xLimits);xticks(ax,[1 4 8 12 16 20 24]);
end
linkaxes([axes1 axes2 axes3],'x');
xlabel(layout,'Active subcarrier index');
end

function panelTitle(ax,heading,absent,hasData)
title(ax,heading,'Color','black');
if isempty(absent),return;end
if hasData
    subtitle(ax,cellstr(absent),'Color',[.24 .24 .24],'Interpreter','none','FontSize',8);
else
    note(ax,cellstr(absent));
end
end

function calibrationFigure(fig,cfg,t,testOnly)
labels = strategyLabels();
colors = strategyColors();
layout = tiledlayout(fig,1,3,'TileSpacing','compact','Padding','compact');
title(layout,phaseTitle('Supported Calibrations across Optical Power and ADC Resolution',testOnly), ...
    'Color','black','FontSize',12.5);
subtitle(layout,{'Cell: supported / planned calibrations', ...
    'B BER failed   I inconclusive   D design rejected   P power mismatch   M incomplete   E power error'}, ...
    'Color','black','FontSize',9);
for s=1:numel(cfg.scheme_names)
    ax = nexttile(layout); hold(ax,'on');
    x = t.scenario(t.scenario.scheme==string(cfg.scheme_names{s}),:);
    for ip=1:numel(cfg.P_targets)
        for iq=1:numel(cfg.adc_bits)
            row = x(x.P_target==cfg.P_targets(ip) & x.q==cfg.adc_bits(iq),:);
            assert(height(row)<=1);
            tone = [1 1 1];
            if ~isempty(row)
                ratio = row.supported_count/row.planned_calibrations;
                tone = 1-(.05+.33*ratio)*(1-colors(s,:));
            end
            patch(ax,iq+[-.5 .5 .5 -.5],ip+[-.5 -.5 .5 .5],tone, ...
                'EdgeColor',[.76 .76 .76],'LineWidth',.65,'HandleVisibility','off');
            if isempty(row)
                text(ax,iq,ip,'Not planned','Color',[.35 .35 .35],'FontSize',7.5, ...
                    'HorizontalAlignment','center');
                continue;
            end
            text(ax,iq,ip-.20,sprintf('%d/%d',row.supported_count,row.planned_calibrations), ...
                'Color','black','FontSize',10,'FontWeight','bold','HorizontalAlignment','center');
            counts = [row.ber_failed_count row.inconclusive_count row.design_rejected_count ...
                row.power_mismatch_count row.incomplete_count row.power_error_count];
            keys = 'BIDPME';
            codes = strings(0,1);
            for c=find(counts>0)
                codes(end+1,1) = sprintf('%s%d',keys(c),counts(c)); %#ok<AGROW>
            end
            if isempty(codes), continue; end
            nFirst = min(3,numel(codes));
            text(ax,iq,ip,strjoin(codes(1:nFirst),' '),'Color','black','FontSize',7.3, ...
                'HorizontalAlignment','center');
            if nFirst<numel(codes)
                text(ax,iq,ip+.21,strjoin(codes(nFirst+1:end),' '),'Color','black','FontSize',7.3, ...
                    'HorizontalAlignment','center');
            end
        end
    end
    style(ax);grid(ax,'off');
    set(ax,'YDir','reverse','TickLength',[0 0]);
    xlim(ax,[.5 numel(cfg.adc_bits)+.5]);ylim(ax,[.5 numel(cfg.P_targets)+.5]);
    xticks(ax,1:numel(cfg.adc_bits));xticklabels(ax,compose('%d',cfg.adc_bits));
    yticks(ax,1:numel(cfg.P_targets));yticklabels(ax,compose('%.1f',cfg.P_targets));
    title(ax,labels{s},'Color','black','FontSize',10.5);
end
xlabel(layout,'ADC resolution (bits)');
ylabel(layout,'Target average optical power (normalized)');
end

function rateFigure(fig,cfg,t,testOnly)
labels = strategyLabels();
colors = strategyColors();
markers = {'o','s','^'};
styles = {'-','--','-.'};
x = t.scenario(t.scenario.qualified,:);
assert(all(x.supported_count==cfg.calibration_count & x.planned_calibrations==cfg.calibration_count));
allPower = x.P_actual_max;
allRate = [x.R_cycle_min;x.R_cycle_max]/1e6;
assert(all(isfinite(allPower) & allPower>0) && all(isfinite(allRate) & allRate>0));
layout = tiledlayout(fig,1,numel(cfg.adc_bits),'TileSpacing','compact','Padding','compact');
title(layout,phaseTitle('Qualified Cycle Rate versus Measured Optical Power',testOnly), ...
    'Color','black','FontSize',12.5);
subtitle(layout,'Five supported calibrations per point. Bars show observed minimum to maximum.', ...
    'Color','black','FontSize',9);
for iq=1:numel(cfg.adc_bits)
    ax = nexttile(layout);hold(ax,'on');
    condition = x(x.q==cfg.adc_bits(iq),:);
    for s=1:numel(cfg.scheme_names)
        rows = sortrows(condition(condition.scheme==string(cfg.scheme_names{s}),:),'P_actual_max');
        if isempty(rows),continue;end
        med = rows.R_cycle_median/1e6;
        lower = rows.R_cycle_min/1e6;
        upper = rows.R_cycle_max/1e6;
        assert(all(lower<=med & med<=upper));
        errorbar(ax,rows.P_actual_max,med,med-lower,upper-med, ...
            'Color',colors(s,:),'LineStyle',styles{s},'Marker',markers{s}, ...
            'LineWidth',1.1,'MarkerSize',5,'CapSize',4,'DisplayName',labels{s});
    end
    style(ax);
    xlim(ax,paddedRange(allPower,.035));ylim(ax,paddedRange(allRate,2));
    title(ax,sprintf('%d-bit ADC',cfg.adc_bits(iq)),'Color','black');
    if isempty(condition)
        note(ax,'No qualified point');
    else
        legendStyle(legend(ax,'Location','best'));
    end
end
xlabel(layout,'Maximum measured average optical power (normalized)');
ylabel(layout,'Cycle payload rate (Mbit/s)');
end

function limits = paddedRange(values,minPad)
low = min(values);
high = max(values);
pad = max(minPad,.08*(high-low));
limits = [max(0,low-pad) high+pad];
end

function style(ax)
set(ax,'Color','white','XColor','black','YColor','black','FontName','Arial', ...
    'FontSize',9,'LineWidth',.7,'Box','on','GridColor',[.78 .78 .78]);
grid(ax,'on');
end

function legendStyle(value)
set(value,'TextColor','black','Color','white','FontSize',7.8,'Interpreter','none');
end

function note(ax,message)
text(ax,.5,.55,message,'Units','normalized','HorizontalAlignment','center', ...
    'Color',[.24 .24 .24],'FontSize',9,'Interpreter','none');
end

function value = phaseTitle(name,testOnly)
value = name;
if testOnly, value = ['TEST ONLY: ' name]; end
end

function labels = strategyLabels()
labels = {'Fixed QPSK','Fixed 64-QAM','Validated Bit Loading'};
end

function colors = strategyColors()
colors = [.10 .34 .64;.79 .27 .11;.06 .48 .34];
end

function id = fileHash(path)
fid = fopen(path,'rb');
assert(fid>=0,'DMT:V2FigureFile','Cannot read exported figure %s.',path);
cleanup = onCleanup(@()fclose(fid)); %#ok<NASGU>
bytes = fread(fid,Inf,'*uint8');
assert(~isempty(bytes),'DMT:V2FigureFile','Empty exported figure %s.',path);
id = string(dmt_sha256(bytes));
end

function writeCaptions(cfg,testOnly,outDir,manifest)
fid = fopen(fullfile(outDir,'figure_captions_en.txt'),'w','n','UTF-8');
assert(fid>=0,'DMT:V2FigureCaption','Cannot write English figure captions.');
cleanup = onCleanup(@()fclose(fid)); %#ok<NASGU>
if testOnly
    fprintf(fid,'TEST ONLY: preflight records for the two predeclared conditions.\n\n');
else
    fprintf(fid,'Formal tradeoff_v2 phase.\n\n');
end
explanations = { ...
    ['The predeclared condition is P_target=1.0, 8-bit ADC, calibration 1. The shared B0 effective SNR ' ...
    'is compared with the approximate initial QAM design thresholds, including the 1 dB margin. The staircase ' ...
    'shows each frozen modulation table. Relative upper bounds use integer errors and bits pooled from the two ' ...
    'completed payload slots. Ratio 1 is the strict design target boundary. Approximate 95%% pointwise Wilson ' ...
    'bounds do not specify simultaneous coverage.']; ...
    ['Each cell shows supported over planned calibrations at a target normalized power and ideal ADC setting. ' ...
    'B, I, D, P, M, and E denote BER failed, inconclusive, design rejected, power mismatch, incomplete, ' ...
    'and power error respectively. The numbers beside the codes give the number of calibrations in each state.']; ...
    ['Qualification requires all %d calibrations to be supported, including per-payload power matching. ' ...
    'Horizontal coordinates use the maximum measured average optical power across the ten payloads at each point. ' ...
    'The marker is the observed median cycle payload rate. The bars show observed minima and maxima, ' ...
    'rather than confidence intervals. Lines connect tested conditions.']};
for j=1:height(manifest)
    fprintf(fid,'%s | %s\n',char(manifest.figure(j)),char(manifest.status(j)));
    if manifest.status(j)=="written"
        if j==3
            fprintf(fid,explanations{j},cfg.calibration_count);
        else
            fprintf(fid,explanations{j});
        end
        fprintf(fid,'\n\n');
    else
        fprintf(fid,'%s\n\n',char(manifest.reason(j)));
    end
end
end
