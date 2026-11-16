function dmt_plot_results(cfg,calibration,profiles,pooled,outDir,mode)
%DMT_PLOT_RESULTS Explicit light styling independent of desktop dark defaults.
% Main input is only actual pooled counts; no curve is generated from smoke.
assert(all(pooled.record_type=="pooled") && all(pooled.seed=="pooled"), ...
    'DMT:PlotLevel','Plot input must contain pooled rows only.');
if strcmpi(mode,'main')
    assert(height(pooled)==72 && all(pooled.tested_bits== ...
        numel(cfg.seeds)*cfg.mainSymbols*pooled.bits_per_symbol), ...
        'DMT:IncompleteMainPlot','Formal figures require complete three-seed pooled counts.');
end
fig = figure('Visible','off','Units','inches','Position',[1 1 6.8 7.8], ...
    'Name','Simplified electrical-baseband DMT');
closeFigure = onCleanup(@() close(fig)); %#ok<NASGU>
if isprop(fig,'Theme')
    fig.Theme = 'light';
end
set(fig,'Color','w','InvertHardcopy','off','PaperPositionMode','auto');
layout = tiledlayout(fig,3,1,'TileSpacing','compact','Padding','compact');
freq = cfg.k(:)*cfg.Fs/cfg.NFFT/1e6;
colors = [0 0.28 0.55;0.72 0.23 0.03;0.12 0.12 0.12];
markers = {'o','s','d'};
styles = {'-','--','-.'};

ax = nexttile(layout);
plot(ax,freq,calibration.gamma_hat_dB(:),'-o','MarkerSize',3.2, ...
    'LineWidth',1.1,'Color',colors(1,:),'DisplayName','Probe-B estimate');
hold(ax,'on');
plot(ax,freq,calibration.gamma_true_dB(:),'--','LineWidth',1.1, ...
    'Color',[0.35 0.35 0.35],'DisplayName','FIR analytical diagnostic');
ylabel(ax,'Electrical symbol SNR (dB)');
title(ax,'(a) Independent-probe quality, E_s/N_0 convention');
xlim(ax,[0.5 24.5]);
styleAxes(ax);
styleLegend(legend(ax,'Location','southoutside','Orientation','horizontal'));

ax = nexttile(layout); hold(ax,'on');
for s = 1:numel(profiles)
    plot(ax,freq,profiles(s).bits_per_symbol(:),'LineStyle',styles{s}, ...
        'Marker',markers{s},'MarkerSize',3.8,'LineWidth',1.1, ...
        'Color',colors(s,:),'DisplayName',profiles(s).name);
end
ylabel(ax,'Bits / subcarrier symbol');
title(ax,'(b) Bit allocation; mean E_s = 1 on every data subcarrier');
yticks(ax,[2 4 6]); ylim(ax,[1.5 6.5]); xlim(ax,[0.5 24.5]);
styleAxes(ax);
styleLegend(legend(ax,'Location','southoutside','Orientation','horizontal'));

ax = nexttile(layout); hold(ax,'on');
positiveLimits = cfg.targetBER;
upperLimits = cfg.targetBER;
for s = 1:numel(profiles)
    data = sortrows(pooled(pooled.scheme==string(profiles(s).name),:),'k');
    assert(height(data)==numel(cfg.k),'DMT:MissingPooledRows', ...
        'Exactly one pooled row per strategy/subcarrier is required.');
    observed = data.error_bits>0;
    if any(observed)
        errorbar(ax,data.frequency_Hz(observed)/1e6,data.BER(observed), ...
            data.BER(observed)-data.CI_low(observed), ...
            data.CI_high(observed)-data.BER(observed), ...
            'LineStyle','none','Marker',markers{s},'MarkerSize',4, ...
            'LineWidth',1,'Color',colors(s,:),'CapSize',3,'HandleVisibility','off');
        positiveLimits = [positiveLimits;data.CI_low(observed)]; %#ok<AGROW>
    end
    if any(~observed)
        if s==1
            zeroFace = 'none';
        elseif s==2
            zeroFace = colors(s,:);
        else
            zeroFace = [0.7 0.7 0.7];
        end
        plot(ax,data.frequency_Hz(~observed)/1e6,data.CI_high(~observed), ...
            'LineStyle','none','Marker','v','MarkerSize',4.3+0.4*s, ...
            'LineWidth',0.8+0.2*s,'Color',colors(s,:),'MarkerFaceColor',zeroFace, ...
            'HandleVisibility','off');
        positiveLimits = [positiveLimits;data.CI_high(~observed)]; %#ok<AGROW>
    end
    upperLimits = [upperLimits;data.CI_high]; %#ok<AGROW>
    % Marker proxies identify strategies even when a strategy has no errors.
    plot(ax,NaN,NaN,'LineStyle','none','Marker',markers{s}, ...
        'MarkerSize',4,'Color',colors(s,:),'DisplayName',profiles(s).name);
end
plot(ax,NaN,NaN,'LineStyle','none','Marker','v','MarkerSize',4.8, ...
    'Color',[0.3 0.3 0.3],'DisplayName','Zero errors: upper limit');
target = yline(ax,cfg.targetBER,':','Target 10^{-3}','Color','k','LineWidth',1, ...
    'LabelHorizontalAlignment','left','HandleVisibility','off');
if isprop(target,'FontColor')
    target.FontColor = 'k';
end
set(ax,'YScale','log');
positiveLimits = positiveLimits(isfinite(positiveLimits) & positiveLimits>0);
lower = 10^floor(log10(min(positiveLimits)))/1.5;
upper = min(1,10^ceil(log10(max(upperLimits)))*1.5);
assert(lower<upper,'DMT:PlotRange','Invalid BER plotting range.');
ylim(ax,[lower upper]); xlim(ax,[0.5 24.5]);
xlabel(ax,'Subcarrier frequency (MHz)'); ylabel(ax,'Uncoded bit error rate');
if strcmpi(mode,'main')
    title(ax,'(c) Formal pooled BER; one frozen calibration');
else
    title(ax,'(c) Smoke only; excluded from formal statistics');
end
styleAxes(ax);
leg = legend(ax,'Location','southoutside','NumColumns',2);
styleLegend(leg);
drawnow;
exportgraphics(fig,fullfile(outDir,'dmt_comparison.png'), ...
    'Resolution',300,'BackgroundColor','white');
exportgraphics(fig,fullfile(outDir,'dmt_comparison.pdf'), ...
    'ContentType','vector','BackgroundColor','white');
savefig(fig,fullfile(outDir,'dmt_comparison.fig'));
end

function styleAxes(ax)
set(ax,'Color','w','XColor','k','YColor','k','ZColor','k', ...
    'FontName','Helvetica','FontSize',8.5,'Box','on', ...
    'GridColor',[0.78 0.78 0.78],'MinorGridColor',[0.88 0.88 0.88], ...
    'GridAlpha',0.65,'MinorGridAlpha',0.35);
grid(ax,'on');
ax.Title.Color = 'k';
ax.XLabel.Color = 'k';
ax.YLabel.Color = 'k';
end

function styleLegend(leg)
set(leg,'Color','w','TextColor','k','EdgeColor',[0.7 0.7 0.7], ...
    'FontSize',7.8,'Box','off');
end
