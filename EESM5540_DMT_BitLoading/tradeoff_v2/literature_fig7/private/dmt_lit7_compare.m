function comparison = dmt_lit7_compare(folder, baseline, cfg, tables)
%DMT_LIT7_COMPARE Report full-point rates and compare one fixed calibration.
% Caller supplies tables from authenticated formal supplemental records.
assert(height(tables.status)==30 && height(tables.summary)==15 && ...
    all(tables.status.planned_symbols==50000 & ~tables.status.test_only & ...
    tables.status.phase=="formal" & tables.status.P_target==1 & tables.status.q==8 & ...
    ismember(tables.status.status,["completed","design_rejected"])), ...
    'DMT:Lit7ComparisonAcquisition','Formal supplemental acquisition is incomplete.');
original = "original_three_tap";
literature = "literature_fig7_fir";
hasBaseline = strcmp(baseline.status,'verified');
originalTables = [];
if hasBaseline, originalTables = baseline.tables; end
summary = [summarize(original,baseline.status,cfg,originalTables); ...
    summarize(literature,'verified',cfg,tables)];
calibrations = observedRounds(literature,tables,cfg);
if hasBaseline
    calibrations = [observedRounds(original,baseline.tables,cfg);calibrations];
end
writetable(summary,fullfile(folder,'channel_summary.csv'));
writetable(calibrations,fullfile(folder,'channel_calibrations.csv'));
comparison = struct('baseline_status',baseline.status,'baseline_folder',baseline.folder, ...
    'baseline_detail',baseline.detail,'figure_status','not_available', ...
    'figure_detail','Authenticated formal baseline is unavailable.', ...
    'figure_png_sha256','','figure_pdf_sha256','','figure_data_sha256','', ...
    'loaded_vs_qpsk',rateDecision(cfg,tables));

stem = 'Subcarrier_Channel_Comparison';
if hasBaseline
    ref = cfg.representative;
    assert(ref.P_target==1 && ref.q==8 && ref.calibration_id==1);
    early = referenceRows(baseline.tables,ref.calibration_id);
    late = referenceRows(tables,ref.calibration_id);
    drawComparison(folder,stem,cfg,early,late);
    comparison.figure_status = 'written';
    comparison.figure_detail = 'Same formal working point, calibration 1, paired by role.';
    comparison.figure_data_sha256 = dmt_v13_hash({early,late});
    comparison.figure_png_sha256 = fileHash(fullfile(folder,[stem '.png']));
    comparison.figure_pdf_sha256 = fileHash(fullfile(folder,[stem '.pdf']));
end
figureManifest = table(string(stem),string(comparison.figure_status), ...
    string(comparison.figure_detail),string(comparison.figure_data_sha256), ...
    string(comparison.figure_png_sha256),string(comparison.figure_pdf_sha256), ...
    'VariableNames',{'figure','status','detail','data_sha256','png_sha256','pdf_sha256'});
writetable(figureManifest,fullfile(folder,'channel_comparison_figure_manifest.csv'));
writeCaption(folder,comparison);
end

function result = summarize(channel, status, cfg, tables)
template = struct('channel',channel,'source_status',string(status),'scheme',"", ...
    'planned_calibrations',cfg.calibration_count,'supported_calibrations',NaN, ...
    'ber_failed_calibrations',NaN,'ber_inconclusive_calibrations',NaN, ...
    'rejected_calibrations',NaN,'power_mismatch_calibrations',NaN, ...
    'power_error_calibrations',NaN,'incomplete_calibrations',NaN, ...
    'measured_rate_calibrations',NaN,'all_five_supported',false, ...
    'R_cycle_min_Mbps',NaN,'R_cycle_median_Mbps',NaN,'R_cycle_max_Mbps',NaN);
rows = repmat(template,numel(cfg.scheme_names),1);
for s = 1:numel(rows)
    name = string(cfg.scheme_names{s});
    row = template;
    row.scheme = name;
    if ~isempty(tables)
        q = tables.scenario(tables.scenario.scheme==name,:);
        assert(height(q)==1 && q.planned_calibrations==cfg.calibration_count);
        row.supported_calibrations = q.supported_count;
        row.ber_failed_calibrations = q.ber_failed_count;
        row.ber_inconclusive_calibrations = q.inconclusive_count;
        row.rejected_calibrations = q.design_rejected_count;
        row.power_mismatch_calibrations = q.power_mismatch_count;
        row.power_error_calibrations = q.power_error_count;
        row.incomplete_calibrations = q.incomplete_count;
        row.measured_rate_calibrations = q.measured_rate_calibrations;
        row.all_five_supported = q.qualified;
        if q.measured_rate_calibrations==cfg.calibration_count
            round = tables.summary(tables.summary.scheme==name,:);
            assert(height(round)==cfg.calibration_count && ...
                all(round.payload_slots_completed==cfg.payload_repeats & isfinite(round.R_cycle)));
            rates = round.R_cycle/1e6;
            row.R_cycle_min_Mbps = min(rates);
            row.R_cycle_median_Mbps = median(rates);
            row.R_cycle_max_Mbps = max(rates);
        end
    end
    rows(s) = row;
end
result = struct2table(rows);
end

function result = observedRounds(channel,tables,cfg)
result = tables.summary(:,{'scheme','calibration_id','state','BER_state', ...
    'design_status','design_reason','payload_slots_completed','power_match', ...
    'Umax_over_target','total_error_bits','total_tested_bits','bits_per_symbol'});
result = addvars(result,repmat(channel,height(result),1),'Before',1,'NewVariableNames','channel');
result.R_cycle_observed_Mbps = tables.summary.R_cycle/1e6;
result.R_cycle_observed_Mbps(result.payload_slots_completed~=cfg.payload_repeats) = NaN;
end

function decision = rateDecision(cfg,tables)
q = tables.scenario;
qualified = @(key) q.qualified(q.scheme==key);
decision = struct('status','not_supported_across_all_five_calibrations', ...
    'FixedQPSK_all_five_supported',qualified("FixedQPSK"), ...
    'ValidatedLoading_all_five_supported',qualified("ValidatedLoading"), ...
    'paired_calibrations',0,'min_rate_ratio',NaN,'median_rate_ratio',NaN,'max_rate_ratio',NaN);
if ~(decision.FixedQPSK_all_five_supported && decision.ValidatedLoading_all_five_supported)
    return;
end
pairs = tables.pair_gains(tables.pair_gains.baseline=="FixedQPSK" & ...
    tables.pair_gains.comparison=="ValidatedLoading",:);
assert(height(pairs)==cfg.calibration_count*cfg.payload_repeats);
matched = pairs.status=="qualified_paired_comparison";
for c = 1:cfg.calibration_count
    rows = pairs.calibration_id==c;
    assert(sum(rows)==cfg.payload_repeats);
    decision.paired_calibrations = decision.paired_calibrations+all(matched(rows));
end
if ~all(matched)
    decision.status = 'paired_power_criterion_not_met_across_all_five_calibrations';
    return;
end
ratios = nan(cfg.calibration_count,1);
for c = 1:cfg.calibration_count
    gain = pairs.R_cycle_relative_gain(pairs.calibration_id==c);
    assert(all(isfinite(gain) & gain==gain(1)));
    ratios(c) = 1+gain(1);
end
decision.min_rate_ratio = min(ratios);
decision.median_rate_ratio = median(ratios);
decision.max_rate_ratio = max(ratios);
if all(ratios>1)
    decision.status = 'qualified_and_faster_in_all_five_calibrations';
else
    decision.status = 'qualified_rate_gain_not_strictly_positive_in_all_five_calibrations';
end
end

function ref = referenceRows(tables,calibration)
ref = struct();
names = {'snr','profiles','pool','summary'};
for j = 1:numel(names)
    name = names{j};
    rows = tables.(name);
    ref.(name) = rows(rows.calibration_id==calibration,:);
end
end

function drawComparison(folder,stem,cfg,early,late)
fig = figure('Visible','off','Color','white','Units','inches', ...
    'Position',[1 1 8 7.1],'PaperPositionMode','auto');
cleanup = onCleanup(@()close(fig)); %#ok<NASGU>
layout = tiledlayout(fig,3,1,'TileSpacing','compact','Padding','compact');
title(layout,'Same-Point DMT Comparison with the Fig. 7 FIR','Color','black');
subtitle(layout,'Target optical power 1.0 (normalized), 8-bit ADC, formal calibration 1', ...
    'Color','black');
ax1 = nexttile(layout); hold(ax1,'on');
ax2 = nexttile(layout); hold(ax2,'on');
ax3 = nexttile(layout); hold(ax3,'on');
data = {early,late};
channelLabels = {'Original three-tap','Fig. 7 FIR'};
styles = {'--','-'};
colors = [.10 .34 .64;.79 .27 .11;.06 .48 .34];
snrColors = [.24 .24 .24;.18 .44 .66];
labels = {'Fixed QPSK','Fixed 64-QAM','Validated bit loading'};
markers = {'o','s','^'};
k = cfg.k(:);
fMHz = k*cfg.Fs/cfg.NFFT/1e6;
noAllocation = strings(0,1);
noPayload = strings(0,1);
yRange = 1;
for i = 1:2
    t = data{i};
    snr = sortrows(t.snr,'k');
    assert(isequal(snr.k,k) && all(isfinite(snr.SNR_dB)));
    plot(ax1,fMHz,snr.SNR_dB,'LineStyle',styles{i},'Color',snrColors(i,:), ...
        'LineWidth',1.5,'DisplayName',channelLabels{i});
    for s = 1:numel(cfg.scheme_names)
        key = string(cfg.scheme_names{s});
        p = sortrows(t.profiles(t.profiles.scheme==key,:),'k');
        b = sortrows(t.pool(t.pool.scheme==key,:),'k');
        state = t.summary(t.summary.scheme==key,:);
        assert(height(state)==1);
        display = sprintf('%s, %s',labels{s},channelLabels{i});
        status = replace(string(state.state),"_"," ");
        if isempty(p)
            noAllocation(end+1,1) = string(display)+": "+status; %#ok<AGROW>
        else
            assert(isequal(p.k,k) && all(ismember(p.bits_k,log2(cfg.Mset))));
            % Channel distinctions for coinciding or nearly coinciding allocations.
            style = bitStyle(i,colors(s,:));
            stairs(ax2,fMHz,p.bits_k,'Color',colors(s,:),'LineStyle',styles{i}, ...
                'LineWidth',style.width,'Marker',markers{s},'MarkerSize',style.size, ...
                'MarkerFaceColor',style.face,'DisplayName',display);
        end
        if isempty(b)
            noPayload(end+1,1) = string(display)+": "+status; %#ok<AGROW>
        else
            assert(isequal(b.k,k) && all(isfinite(b.CI_high) & b.CI_high>0));
            y = b.CI_high/cfg.targetBER;
            yRange = [yRange;y]; %#ok<AGROW>
            plot(ax3,fMHz,y,'Color',colors(s,:),'LineStyle',styles{i}, ...
                'LineWidth',1.2,'Marker',markers{s},'MarkerSize',3.6, ...
                'DisplayName',display);
        end
    end
end
ylabel(ax1,'Effective SNR (dB)');
title(ax1,'Shared probe B0');
styleLegend(legend(ax1,'Location','best'));
ylabel(ax2,'Bits per subcarrier');
yticks(ax2,log2(cfg.Mset));
ylim(ax2,[1.4 6.6]);
title(ax2,'Frozen bit allocation');
note(ax2,noAllocation);
styleLegend(legend(ax2,'Location','best','NumColumns',2));
ylabel(ax3,'Wilson upper BER bound / target');
title(ax3,'Two payload slots pooled within calibration 1');
note(ax3,noPayload);
set(ax3,'YScale','log');
yline(ax3,1,':k','Target ratio = 1','HandleVisibility','off');
ylim(ax3,[min(.5,.8*min(yRange)) max(2,1.25*max(yRange))]);
styleLegend(legend(ax3,'Location','best','NumColumns',2));
for ax = [ax1 ax2 ax3]
    set(ax,'Color','white','XColor','black','YColor','black','FontName','Arial', ...
        'FontSize',9,'LineWidth',.65,'Box','on','GridColor',[.78 .78 .78]);
    grid(ax,'on');
    xlim(ax,[min(fMHz) max(fMHz)]);
    xticks(ax,[1 4 8 12 16 20 24]);
end
linkaxes([ax1 ax2 ax3],'x');
xlabel(layout,'Active subcarrier frequency (MHz)');
exportgraphics(fig,fullfile(folder,[stem '.png']),'Resolution',300,'BackgroundColor','white');
exportgraphics(fig,fullfile(folder,[stem '.pdf']),'ContentType','vector','BackgroundColor','white');
end

function style = bitStyle(channel,color)
style = struct('width',1.1,'size',5,'face','white');
if channel==2
    style.width = 1.15;
    style.size = 2.9;
    style.face = color;
end
end

function note(ax,lines)
if ~isempty(lines)
    subtitle(ax,cellstr(lines),'Color',[.23 .23 .23],'Interpreter','none','FontSize',8);
end
end

function styleLegend(handle)
set(handle,'TextColor','black','Color','white','FontSize',7.6,'Interpreter','none');
end

function value = fileHash(path)
fid = fopen(path,'rb');
assert(fid>=0,'DMT:Lit7ComparisonFile','Cannot read figure: %s',path);
cleanup = onCleanup(@()fclose(fid)); %#ok<NASGU>
bytes = fread(fid,Inf,'*uint8');
assert(~isempty(bytes),'DMT:Lit7ComparisonFile','Empty figure: %s',path);
value = dmt_sha256(bytes);
end

function writeCaption(folder,comparison)
path = fullfile(folder,'channel_comparison_caption_en.txt');
fid = fopen(path,'w','n','UTF-8');
assert(fid>=0,'DMT:Lit7ComparisonCaption','Cannot write English caption.');
cleanup = onCleanup(@()fclose(fid)); %#ok<NASGU>
if strcmp(comparison.figure_status,'written')
    fprintf(fid,['Comparison at target normalized transmitted mean optical power 1.0, ' ...
        'with an 8-bit ADC and the predeclared first formal calibration. The Fig. 7 FIR is ' ...
        'a normalized equivalent channel based on a publicly available measured magnitude ' ...
        'response (Zhong et al., Optics Express 23, 1176–1189, 2015, doi:10.1364/OE.23.001176). ' ...
        'Both channels were calibrated and designed separately. Seeds are paired by role. ' ...
        'The SNR is the shared independent B0 probe estimate. Overlapping bit allocations ' ...
        'indicate identical orders. Approximate pointwise 95%% Wilson upper bounds use exactly ' ...
        'the two independent payload slots in the displayed calibration. The strict target ' ...
        'requires a ratio below 1 at every active subcarrier. A rejected design has no ' ...
        'payload or BER curve. Observed cycle-rate ranges use all five calibrations when each ' ...
        'has sent both slots. The original receiver-power scan and this normalized transmitter-' ...
        'power operating point describe different experiments.\n']);
else
    fprintf(fid,'%s\n%s\n',comparison.figure_detail,comparison.baseline_detail);
end
end
