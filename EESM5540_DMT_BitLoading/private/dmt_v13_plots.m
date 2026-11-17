function manifest = dmt_v13_plots(cfg,records,runs,tables,outDir,phase)
%DMT_V13_PLOTS Plot actual strata only; structural diagram has no data claims.
names={}; statuses={}; reasons={};
drawDiagram(outDir); add('closed_loop_transceiver','written','Structural model and ideal control assumptions only.');
linearRecord=[];
if ~isempty(records)
    index=find([records.scenario_idx]==0 & [records.calibration_id]==1 & [records.configured]);
    if ~isempty(index), linearRecord=records(index); end
end
linear=tables.pooled(tables.pooled.scenario_idx==0 & tables.pooled.calibration_id==1,:);
if ~isempty(linearRecord) && height(linear)==72
    drawLinear(cfg,linearRecord,linear,outDir,phase);
    add('linear_calibration_1','written','All panels from preselected linear calibration 1.');
    drawDetailedBER(cfg,linear,outDir,phase);
    add('linear_calibration_1_detailed_BER','written','Observed BER plus pointwise intervals; zeros at upper endpoints.');
else
    add('linear_calibration_1','not_available','Calibration 1 lacks three complete configurable strategy results. No substitute chosen.');
end
imdd=tables.summary(tables.summary.scenario_idx>0 & tables.summary.test_seed_count==3,:);
if ~isempty(imdd)
    drawIMDD(cfg,tables,outDir,phase);
    add('imdd_summary','written','Actual complete groups; allocated bit ranges are not confidence intervals.');
else
    add('imdd_summary','not_available','No complete IM/DD strategy/calibration data.');
end
papr=tables.papr(tables.papr.calibration_id==1,:);
if ~isempty(papr)
    drawPAPR(papr,outDir,phase);
    add('papr_calibration_1','written','Before bias/clipping; zero exceedances retained as 0/N in CSV.');
else
    add('papr_calibration_1','not_available','No completed calibration-1 payload groups.');
end
probe=tables.probe_C(tables.probe_C.calibration_id==1,:);
if ~isempty(probe)
    drawProbe(cfg,probe,outDir,phase);
    add('quality_B_C_calibration_1','written','Independent diagnostic probes only, not payload BER samples.');
else
    add('quality_B_C_calibration_1','not_available','No acknowledged calibration-1 C-probe data.');
end
manifest=table(string(names(:)),string(statuses(:)),string(reasons(:)), ...
    'VariableNames',{'figure','status','interpretation'});
writetable(manifest,fullfile(outDir,'figure_manifest.csv'));
if isempty(runs)
    fprintf('No payload figures were inferred from missing runs. Structural figure is model documentation.\n');
end

    function add(name,status,reason)
        names{end+1}=name; statuses{end+1}=status; reasons{end+1}=reason;
    end
end

function drawLinear(cfg,record,pooled,outDir,phase)
fig=makeFigure([6.7 5.2]); cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
layout=tiledlayout(fig,2,2,'TileSpacing','compact','Padding','compact');
frequency=cfg.k*cfg.Fs/cfg.NFFT/1e6; colors=palette(); styles={'-o','--s','-.d'};
ax=nexttile(layout,1);
plot(ax,frequency,record.receiver.gamma_B_dB,'-o','Color',colors(1,:), ...
    'MarkerSize',3,'LineWidth',1);
xlabel(ax,'Frequency (MHz)'); ylabel(ax,'Estimated SNR (dB)');
title(ax,'(a) Linear calibration 1: probe B'); styleAxes(ax);
ax=nexttile(layout,2); hold(ax,'on');
for s=1:3
    p=record.exchange.tx_profiles(s);
    plot(ax,frequency,p.bits_k,styles{s},'Color',colors(s,:), ...
        'MarkerSize',3,'LineWidth',1,'DisplayName',p.scheme);
end
yticks(ax,[2 4 6]); ylim(ax,[1.5 6.5]);
xlabel(ax,'Frequency (MHz)'); ylabel(ax,'Bits / subcarrier symbol');
title(ax,'(b) Accepted Tx/Rx configuration'); styleAxes(ax);
styleLegend(legend(ax,'Location','southoutside','Orientation','horizontal'));
ax=nexttile(layout,3,[1 2]); hold(ax,'on');
limits=1;
for s=1:3
    name=record.exchange.tx_profiles(s).scheme;
    data=sortrows(pooled(string(pooled.scheme)==string(name),:),'k');
    assert(height(data)==24);
    [~,hi]=dmt_wilson(data.error_bits,data.tested_bits);
    u=hi/cfg.targetBER;
    plot(ax,data.frequency_Hz/1e6,u,styles{s},'Color',colors(s,:), ...
        'MarkerSize',3.8,'LineWidth',1.1,'DisplayName',name);
    limits=[limits;u]; %#ok<AGROW>
end
yline(ax,1,':k','Upper-endpoint criterion = 1','HandleVisibility','off');
set(ax,'YScale','log');
ylim(ax,[10^floor(log10(min(limits)))/1.3 10^ceil(log10(max(limits)))*1.3]);
xlabel(ax,'Subcarrier frequency (MHz)');
ylabel(ax,{'Pointwise 95% CI upper endpoint','/ BER target'});
title(ax,['(c) ' scopeName(phase) ': per-subcarrier constraint check']);
styleAxes(ax); styleLegend(legend(ax,'Location','southoutside','Orientation','horizontal'));
saveFigure(fig,outDir,'linear_calibration_1');
end

function drawDetailedBER(cfg,pooled,outDir,phase)
fig=makeFigure([6.7 3.7]); cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
ax=axes(fig); hold(ax,'on'); colors=palette(); markers={'o','s','d'};
names=["Uniform" "Loaded" "Fixed16"]; lower=cfg.targetBER; upper=cfg.targetBER;
for s=1:3
    x=sortrows(pooled(string(pooled.scheme)==names(s),:),'k');
    observed=x.error_bits>0;
    if any(observed)
        errorbar(ax,x.frequency_Hz(observed)/1e6,x.BER(observed), ...
            x.BER(observed)-x.CI_low(observed),x.CI_high(observed)-x.BER(observed), ...
            'LineStyle','none','Marker',markers{s},'Color',colors(s,:), ...
            'MarkerSize',4,'LineWidth',1,'HandleVisibility','off');
        lower=[lower;x.CI_low(observed)]; %#ok<AGROW>
    end
    if any(~observed)
        plot(ax,x.frequency_Hz(~observed)/1e6,x.CI_high(~observed),'v', ...
            'Color',colors(s,:),'MarkerSize',4+s/3,'LineStyle','none','HandleVisibility','off');
        lower=[lower;x.CI_high(~observed)]; %#ok<AGROW>
    end
    upper=[upper;x.CI_high]; %#ok<AGROW>
    plot(ax,NaN,NaN,markers{s},'Color',colors(s,:),'DisplayName',char(names(s)));
end
plot(ax,NaN,NaN,'vk','DisplayName','Zero errors: upper endpoint');
yline(ax,cfg.targetBER,':k','BER target','HandleVisibility','off');
lower=lower(lower>0 & isfinite(lower));
set(ax,'YScale','log'); ylim(ax,[10^floor(log10(min(lower)))/1.3 min(1,10^ceil(log10(max(upper)))*1.3)]);
xlabel(ax,'Subcarrier frequency (MHz)'); ylabel(ax,'Observed uncoded BER');
title(ax,[scopeName(phase) ': linear calibration 1; approximate pointwise 95% intervals']);
styleAxes(ax); styleLegend(legend(ax,'Location','southoutside','NumColumns',2));
saveFigure(fig,outDir,'linear_calibration_1_detailed_BER');
end

function drawIMDD(cfg,tables,outDir,phase)
fig=makeFigure([6.7 7]); cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
layout=tiledlayout(fig,3,1,'TileSpacing','compact','Padding','compact');
colors=palette(); styles={'-o','--s','-.d'}; names=["Uniform" "Loaded" "Fixed16"];
ax1=nexttile(layout); hold(ax1,'on'); ax2=nexttile(layout); hold(ax2,'on'); ax3=nexttile(layout); hold(ax3,'on');
for s=1:3
    clip=nan(3,1); med=clip; lo=clip; hi=clip; supported=clip; completed=zeros(3,1);
    for q=1:3
        power=tables.power(tables.power.scenario_idx==q & string(tables.power.scheme)==names(s),:);
        if ~isempty(power)
            clip(q)=sum(power.lower_clip_count+power.upper_clip_count)/sum(power.sample_count);
        end
        data=tables.summary(tables.summary.scenario_idx==q & tables.summary.scheme==names(s),:);
        b=data.B(isfinite(data.B));
        if ~isempty(b), lo(q)=min(b); med(q)=median(b); hi(q)=max(b); end
        complete=data.status=="supported" | data.status=="failed" | data.status=="inconclusive";
        completed(q)=sum(complete);
        if completed(q)>0, supported(q)=sum(data.status=="supported"); end
    end
    plot(ax1,1:3,clip,styles{s},'Color',colors(s,:),'LineWidth',1.1,'DisplayName',char(names(s)));
    errorbar(ax2,1:3,med,med-lo,hi-med,styles{s},'Color',colors(s,:), ...
        'LineWidth',1.1,'MarkerSize',4,'DisplayName',char(names(s)));
    plot(ax3,1:3,supported,styles{s},'Color',colors(s,:),'LineWidth',1.1,'DisplayName',char(names(s)));
    for q=1:3
        if completed(q)>0
            text(ax3,q+0.025,supported(q)+0.15*s,sprintf('%d/%d',supported(q),completed(q)), ...
                'FontSize',7,'Color',colors(s,:));
        end
    end
end
ylabel(ax1,'Observed clipped samples / samples');
title(ax1,'(a) Discrete-time clipping across completed groups');
ylabel(ax2,'Allocated bits / DMT symbol');
title(ax2,'(b) Calibration median and min-max range, not a confidence band');
ylabel(ax3,'Supported calibration rounds');
title(ax3,'(c) Pointwise criterion; labels supported / complete rounds');
ylim(ax3,[-0.25 cfg.calibrationCount+1.3]);
for ax=[ax1 ax2 ax3]
    xticks(ax,1:3); xticklabels(ax,{'4','2.5','1.5'}); xlim(ax,[0.75 3.35]);
    xlabel(ax,'rho: AC drive/clipping condition; P_0 = 1 and P_{max} = 2 fixed');
    styleAxes(ax);
end
styleLegend(legend(ax1,'Location','southoutside','Orientation','horizontal'));
title(layout,[scopeName(phase) ': normalized discrete-time IM/DD equivalent model'],'Color','k','FontSize',10);
saveFigure(fig,outDir,'imdd_summary');
end

function drawPAPR(data,outDir,phase)
fig=makeFigure([6.7 4.5]); cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
ax=axes(fig); hold(ax,'on'); colors=lines(12); index=0;
for q=0:3
    for name=["Uniform" "Loaded" "Fixed16"]
        x=data(data.scenario_idx==q & string(data.scheme)==name,:);
        if isempty(x), continue; end
        thresholds=unique(x.threshold_dB); probability=zeros(size(thresholds)); n=0;
        for k=1:numel(thresholds)
            rows=x(x.threshold_dB==thresholds(k),:);
            denominator=sum(rows.tested_symbols); n=denominator;
            probability(k)=sum(rows.exceed_count)/denominator;
        end
        index=index+1; positive=probability>0;
        style={'-','--','-.'}; marker={'o','s','d','^'};
        s=find(["Uniform" "Loaded" "Fixed16"]==name);
        plot(ax,thresholds(positive),probability(positive),'LineStyle',style{s}, ...
            'Marker',marker{q+1},'MarkerSize',2.5,'LineWidth',1,'Color',colors(index,:), ...
            'DisplayName',sprintf('%s / %s, N=%d',char(x.scenario_id(1)),char(name),n));
    end
end
set(ax,'YScale','log'); ylim(ax,[minPositive(data.observed_exceedance)/1.3 1.05]);
xlabel(ax,'Sampled AC PAPR before bias/clipping (dB)'); ylabel(ax,'Observed exceedance count / symbols');
title(ax,[scopeName(phase) ': preselected calibration 1']); styleAxes(ax);
styleLegend(legend(ax,'Location','southoutside','NumColumns',3));
text(ax,0.02,0.04,'Zero exceedances are retained as 0/N in CSV; omitted on log axis.', ...
    'Units','normalized','Color','k','FontSize',7,'BackgroundColor','w');
saveFigure(fig,outDir,'papr_calibration_1');
end

function drawProbe(cfg,data,outDir,phase)
fig=makeFigure([6.7 5.3]); cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
layout=tiledlayout(fig,2,2,'TileSpacing','compact','Padding','compact');
colors=palette(); styles={'-o','--s','-.d'}; names=["Uniform" "Loaded" "Fixed16"];
for q=0:3
    ax=nexttile(layout); hold(ax,'on');
    for s=1:3
        x=sortrows(data(data.scenario_idx==q & data.scheme==names(s),:),'k');
        if isempty(x), continue; end
        plot(ax,x.k*cfg.Fs/cfg.NFFT/1e6,x.delta_dB,styles{s}, ...
            'Color',colors(s,:),'MarkerSize',2.4,'LineWidth',1,'DisplayName',char(names(s)));
    end
    yline(ax,0,':k','HandleVisibility','off');
    title(ax,sprintf('%s, calibration 1',cfg.scenarios(q+1).scenario_id),'Interpreter','none');
    xlabel(ax,'Frequency (MHz)'); ylabel(ax,'Quality C - B (dB)'); styleAxes(ax);
    styleLegend(legend(ax,'Location','southoutside','Orientation','horizontal'));
end
title(layout,[scopeName(phase) ': independent configuration-specific C probe'],'Color','k','FontSize',10);
saveFigure(fig,outDir,'quality_B_C_calibration_1');
end

function drawDiagram(outDir)
fig=makeFigure([6.7 3.8]); cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
boxes={[0.02 .66 .19 .19],sprintf('Known A/B; C/payload\nTx QAM / IFFT / CP');[.27 .66 .20 .19], ...
    sprintf('Linear bypass or\nP_0 + g x, clip [0,2]');[.54 .66 .17 .19], ...
    sprintf('Causal FIR h\n+ real receiver noise');[.78 .66 .20 .19], ...
    sprintf('Rx FFT / ZF\naccepted-table demap');[.77 .30 .21 .17], ...
    sprintf('Rx A/B estimate\nH stays at receiver');[.49 .30 .21 .17], ...
    sprintf('Ideal SNR feedback\nquality only');[.20 .30 .21 .17], ...
    sprintf('Tx allocation\nfinite QAM, fixed E_s');[.20 .03 .49 .16], ...
    sprintf('Separate Tx/Rx configuration copies; validation and ideal ACK\nC probe diagnoses frozen table; independent payload follows')};
for j=1:size(boxes,1)
    annotation(fig,'textbox',boxes{j,1},'String',boxes{j,2},'Color','k', ...
        'EdgeColor',[.3 .3 .3],'BackgroundColor','w','HorizontalAlignment','center', ...
        'VerticalAlignment','middle','FontSize',7.8,'FitBoxToText','off');
end
arrow(fig,[.21 .27],[.755 .755],false); arrow(fig,[.47 .54],[.755 .755],false);
arrow(fig,[.71 .78],[.755 .755],false); arrow(fig,[.88 .88],[.66 .47],true);
arrow(fig,[.77 .70],[.385 .385],true); arrow(fig,[.49 .41],[.385 .385],true);
arrow(fig,[.30 .30],[.30 .19],true); arrow(fig,[.20 .12],[.12 .66],true);
arrow(fig,[.69 .88],[.11 .66],true);
annotation(fig,'textbox',[.02 .89 .96 .09],'String', ...
    'Solid: forward samples. Dashed: ideal control; signaling overhead not modeled.', ...
    'EdgeColor','none','Color','k','FontSize',8,'HorizontalAlignment','center');
saveFigure(fig,outDir,'closed_loop_transceiver');
end

function arrow(fig,x,y,control)
style='-'; if control, style='--'; end
annotation(fig,'arrow',x,y,'Color','k','LineStyle',style,'LineWidth',1);
end

function fig=makeFigure(sizeInches)
fig=figure('Visible','off','Units','inches','Position',[1 1 sizeInches]);
if isprop(fig,'Theme'), fig.Theme='light'; end
set(fig,'Color','w','InvertHardcopy','off','PaperPositionMode','auto');
end

function styleAxes(ax)
set(ax,'Color','w','XColor','k','YColor','k','FontSize',8,'Box','on', ...
    'GridColor',[.8 .8 .8],'MinorGridColor',[.9 .9 .9]); grid(ax,'on');
ax.Title.Color='k'; ax.XLabel.Color='k'; ax.YLabel.Color='k';
end

function styleLegend(leg)
set(leg,'Color','w','TextColor','k','FontSize',6.8,'Box','off');
end

function saveFigure(fig,outDir,name)
drawnow;
exportgraphics(fig,fullfile(outDir,[name '.png']),'Resolution',300,'BackgroundColor','white');
exportgraphics(fig,fullfile(outDir,[name '.pdf']),'ContentType','vector','BackgroundColor','white');
savefig(fig,fullfile(outDir,[name '.fig']));
try
    exportgraphics(fig,fullfile(outDir,[name '.svg']),'ContentType','vector','BackgroundColor','white');
catch ME
    fid=fopen(fullfile(outDir,'optional_svg_status.txt'),'a');
    if fid>=0, fprintf(fid,'%s: %s\n',name,ME.message); fclose(fid); end
end
end

function colors=palette()
colors=[0 .28 .55;.72 .23 .03;.12 .12 .12];
end

function name=scopeName(phase)
name='Formal'; if strcmp(phase,'preflight'), name='Preflight only'; end
end

function value=minPositive(x)
x=x(isfinite(x) & x>0); assert(~isempty(x)); value=min(x);
end
