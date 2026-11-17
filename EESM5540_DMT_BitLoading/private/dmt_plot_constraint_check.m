function rows = dmt_plot_constraint_check(cfg,calibration,profiles,pooled,outDir)
%DMT_PLOT_CONSTRAINT_CHECK One fixed reference, one statistic at every point.
% All panels use reference calibration 0. The ordinate in (c) is Wilson's
% pointwise upper endpoint / target, never observed BER or a confidence band.
assert(strcmp(cfg.runMode,'main'),'DMT:ReferenceNotMain', ...
    'Reference figure requires completed main data, not smoke.');
assert(numel(cfg.k)==24 && numel(profiles)==3 && height(pooled)==72, ...
    'DMT:ReferenceShape','Expected three strategies and 24 data subcarriers.');
assert(cfg.mainSymbols==100000 && isequal(cfg.seeds,[11 22 33]), ...
    'DMT:IncompleteReference','Expected the frozen three-seed main protocol.');
assert(isequal(string({profiles.name}),["Uniform" "Loaded" "Fixed16"]));
required = {'scheme','k','frequency_Hz','tested_bits','error_bits','CI_low','CI_high'};
assert(all(ismember(required,pooled.Properties.VariableNames)));
rows = table();
for s = 1:3
    one = sortrows(pooled(string(pooled.scheme)==string(profiles(s).name),:),'k');
    assert(height(one)==24 && isequal(one.k,cfg.k), ...
        'DMT:ReferenceCarriers','Each reference strategy needs k=1:24 exactly once.');
    n = double(one.tested_bits);
    e = double(one.error_bits);
    assert(all(n==300000*log2(profiles(s).M)) && all(isfinite(e)) && ...
        all(e>=0 & e<=n & e==fix(e)),'DMT:IncompleteReference', ...
        'Reference counters must contain exactly three complete formal seeds.');
    [lo,hi] = dmt_wilson(e,n);
    assert(all(isfinite(one.CI_low) & isfinite(one.CI_high)) && ...
        all(abs(lo-one.CI_low)<=1e-12+1e-10*abs(lo)) && ...
        all(abs(hi-one.CI_high)<=1e-12+1e-10*abs(hi)), ...
        'DMT:ReferenceIntervals','Saved reference intervals disagree with formal counts.');
    u = hi/cfg.targetBER;
    status = repmat("inconclusive",24,1);
    status(hi<cfg.targetBER) = "supported";
    status(lo>cfg.targetBER) = "failed";
    part = table(zeros(24,1),repmat(string(profiles(s).name),24,1), ...
        cfg.k,cfg.k*cfg.Fs/cfg.NFFT,calibration.gamma_hat_dB(:), ...
        profiles(s).M(:),log2(profiles(s).M(:)),n,e,e./n,lo,hi,u,status, ...
        'VariableNames',{'calibration_id','scheme','k','frequency_Hz','SNR_est_dB', ...
        'M','bits_per_symbol','tested_bits','error_bits','BER','CI_low','CI_high', ...
        'CI_upper_over_target','pointwise_status'});
    if isempty(rows)
        rows = part;
    else
        rows = [rows;part]; %#ok<AGROW>
    end
end
assert(all(isfinite(rows.CI_upper_over_target) & rows.CI_upper_over_target>0));
fig = figure('Visible','off','Units','inches','Position',[1 1 6.7 5.15], ...
    'Name','Reference calibration 0: DMT constraint check');
cleanup = onCleanup(@() close(fig)); %#ok<NASGU>
if isprop(fig,'Theme')
    fig.Theme = 'light';
end
set(fig,'Color','w','InvertHardcopy','off','PaperPositionMode','auto');
layout = tiledlayout(fig,2,2,'TileSpacing','compact','Padding','compact');
colors = [0 0.28 0.55;0.72 0.23 0.03;0.12 0.12 0.12];
markers = {'o','s','d'};
styles = {'-','--','-.'};
freq = cfg.k*cfg.Fs/cfg.NFFT/1e6;

ax = nexttile(layout,1);
plot(ax,freq,calibration.gamma_hat_dB(:),'-o','MarkerSize',3, ...
    'LineWidth',1,'Color',colors(1,:),'DisplayName','Probe-B estimate');
hold(ax,'on');
plot(ax,freq,calibration.gamma_true_dB(:),'--','LineWidth',1, ...
    'Color',[0.4 0.4 0.4],'DisplayName','FIR diagnostic');
title(ax,'(a) Reference 0 quality');
xlabel(ax,'Frequency (MHz)'); ylabel(ax,'Electrical symbol SNR (dB)');
xlim(ax,[0.5 24.5]); styleAxes(ax);
styleLegend(legend(ax,'Location','southoutside','Orientation','horizontal'));

ax = nexttile(layout,2); hold(ax,'on');
for s = 1:3
    plot(ax,freq,log2(profiles(s).M(:)),'LineStyle',styles{s}, ...
        'Marker',markers{s},'MarkerSize',3.1,'LineWidth',1, ...
        'Color',colors(s,:),'DisplayName',profiles(s).name);
end
title(ax,'(b) Reference 0 bit allocation');
xlabel(ax,'Frequency (MHz)'); ylabel(ax,'Bits / subcarrier symbol');
yticks(ax,[2 4 6]); ylim(ax,[1.6 6.4]); xlim(ax,[0.5 24.5]);
styleAxes(ax);
styleLegend(legend(ax,'Location','southoutside','Orientation','horizontal'));

ax = nexttile(layout,3,[1 2]); hold(ax,'on');
for s = 1:3
    one = rows(rows.scheme==string(profiles(s).name),:);
    plot(ax,one.frequency_Hz/1e6,one.CI_upper_over_target, ...
        'LineStyle',styles{s},'Marker',markers{s},'MarkerSize',3.8, ...
        'LineWidth',1.05,'Color',colors(s,:),'DisplayName',profiles(s).name);
end
line = yline(ax,1,':','Upper-endpoint criterion = 1', ...
    'Color','k','LineWidth',1,'LabelHorizontalAlignment','left', ...
    'HandleVisibility','off');
if isprop(line,'FontColor')
    line.FontColor = 'k';
end
set(ax,'YScale','log');
minimum = min([1;rows.CI_upper_over_target]);
maximum = max([1;rows.CI_upper_over_target]);
ylim(ax,[10^floor(log10(minimum))/1.15 10^ceil(log10(maximum))*1.15]);
xlim(ax,[0.5 24.5]);
title(ax,'(c) Per-subcarrier BER constraint check');
xlabel(ax,'Subcarrier frequency (MHz)');
ylabel(ax,{'Pointwise 95% CI upper endpoint','/ BER target'});
styleAxes(ax);
fixed = rows(rows.scheme=="Fixed16" & rows.CI_low>cfg.targetBER,:);
if ~isempty(fixed)
    label = ['Fixed16 lower CI > target: k=' mat2str(fixed.k.')];
    text(ax,0.015,0.97,label,'Units','normalized','VerticalAlignment','top', ...
        'Color','k','FontSize',7.2,'Interpreter','none','BackgroundColor','w');
end
styleLegend(legend(ax,'Location','southoutside','Orientation','horizontal'));
drawnow;
exportgraphics(fig,fullfile(outDir,'figure2_constraint_check.png'), ...
    'Resolution',300,'BackgroundColor','white');
exportgraphics(fig,fullfile(outDir,'figure2_constraint_check.pdf'), ...
    'ContentType','vector','BackgroundColor','white');
savefig(fig,fullfile(outDir,'figure2_constraint_check.fig'));
try
    exportgraphics(fig,fullfile(outDir,'figure2_constraint_check.svg'), ...
        'ContentType','vector','BackgroundColor','white');
    svgStatus = 'SVG exported.';
catch ME
    svgStatus = ['Optional SVG export unavailable: ' ME.message];
end
fid = fopen(fullfile(outDir,'svg_export_status.txt'),'w','n','UTF-8');
assert(fid>=0);
closeFile = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',svgStatus);
end

function styleAxes(ax)
set(ax,'Color','w','XColor','k','YColor','k','ZColor','k','FontName','Helvetica', ...
    'FontSize',7.8,'Box','on','GridColor',[0.8 0.8 0.8], ...
    'MinorGridColor',[0.9 0.9 0.9],'GridAlpha',0.6,'MinorGridAlpha',0.35);
grid(ax,'on');
ax.Title.Color = 'k'; ax.Title.FontSize = 8.3;
ax.XLabel.Color = 'k'; ax.YLabel.Color = 'k';
end

function styleLegend(leg)
set(leg,'Color','w','TextColor','k','EdgeColor',[0.7 0.7 0.7], ...
    'FontSize',6.7,'Box','off');
end
