function manifest=dmt_to_plot(cfg,tables,outDir)
%DMT_TO_PLOT Read-only plots of reconstructed records, never new transmissions.
if ~isfolder(outDir),mkdir(outDir);end
stems={'rate_vs_actual_power','required_tested_power','nominal_vs_cycle_rate', ...
    'BER_vs_actual_power','representative_loading_BER'};
draw={@()ratePower(cfg,tables),@()requiredPower(cfg,tables), ...
    @()nominalCycle(cfg,tables),@()berPower(cfg,tables),@()representative(cfg,tables)};
rows=cell(numel(stems),1);
for j=1:numel(stems)
    rows{j}=struct('figure',string(stems{j}),'status',"not_available", ...
        'reason',"No actual design or payload records; no scientific curve inferred.");
end
manifest=struct2table([rows{:}]);
manifest.data_hash=repmat(string(dmt_v13_hash(tables)),height(manifest),1);
for j=1:numel(stems)
    if tables.design_cases_processed==0 && tables.completed_groups==0,continue;end
    fig=[];
    try
        fig=draw{j}();
        saveAll(fig,outDir,stems{j});close(fig);
        manifest.status(j)="written";
        manifest.reason(j)="Actual-data plot or explicit observed missing/rejected status; see captions.";
    catch ME
        if ~isempty(fig)&&isgraphics(fig),close(fig);end
        manifest.status(j)="failed";manifest.reason(j)=string(ME.message);
        writetable(manifest,fullfile(outDir,'figure_manifest.csv'));
        rethrow(ME);
    end
end
writetable(manifest,fullfile(outDir,'figure_manifest.csv'));
writeCaptions(cfg,tables,outDir);
end

function fig=ratePower(cfg,t)
fig=makeFigure([6.7 5.1]);layout=tiledlayout(fig,2,1,'Padding','compact','TileSpacing','compact');
colors=lines(numel(cfg.adc_bits));styles={'-','--'};
metrics={'R_nominal','R_cycle'};labels={'Nominal data-segment rate (Mbit/s)','Cycle payload rate (Mbit/s)'};
for p=1:numel(metrics)
    ax=nexttile(layout);hold(ax,'on');anyPoint=false;
    for qi=1:numel(cfg.adc_bits)
        q=cfg.adc_bits(qi);
        for si=1:numel(cfg.scheme_names)
            x=t.scenario(t.scenario.q==q & t.scenario.scheme==string(cfg.scheme_names{si}),:);
            x=sortrows(x,'P_target');m=metrics{p};
            % A partially run condition cannot assign unmeasured profiles a
            % payload-power coordinate. Preserve its statuses/allocated
            % rates in CSV, but wait for every calibration to be resolved.
            valid=x.scan_point_resolved & isfinite(x.P_actual_median)&isfinite(x.([m '_median']));
            x=x(valid,:);
            if isempty(x)
                plot(ax,NaN,NaN,'Color',colors(qi,:),'LineStyle',styles{si}, ...
                    'DisplayName',sprintf('q=%d, %s (NA)',q,shortScheme(si)));continue;
            end
            anyPoint=true;
            xx=x.P_actual_median;yy=x.([m '_median'])/1e6;
            errorbar(ax,xx,yy,yy-x.([m '_min'])/1e6,x.([m '_max'])/1e6-yy, ...
                'Color',colors(qi,:),'LineStyle',styles{si},'LineWidth',1.0,'CapSize',4, ...
                'DisplayName',sprintf('q=%d, %s',q,shortScheme(si)));
            for k=1:height(x)
                plot(ax,[x.P_actual_min(k) x.P_actual_max(k)],[yy(k) yy(k)],'-', ...
                    'Color',colors(qi,:),'HandleVisibility','off','LineWidth',0.7);
                fillColor='white';
                if x.all_rounds_supported(k),fillColor=colors(qi,:);end
                marker='o';if si==2,marker='s';end
                plot(ax,xx(k),yy(k),marker,'Color',colors(qi,:), ...
                    'MarkerFaceColor',fillColor,'MarkerSize',4.5,'HandleVisibility','off');
                if ~x.all_rounds_supported(k)
                    text(ax,xx(k),yy(k),sprintf(' %d/%d',x.supported_rounds(k),x.planned_calibrations(k)), ...
                        'FontSize',7.2,'Color',colors(qi,:),'VerticalAlignment','bottom');
                end
            end
        end
    end
    xlabel(ax,'Actual average optical power (normalized units)');ylabel(ax,labels{p});
    title(ax,sprintf('%s: min-median-max, filled = all rounds supported',scope(t)));
    style(ax);
    legendStyle(legend(ax,'Location','southoutside','NumColumns',3));
    if ~anyPoint,statusText(ax,t,'No completed payload power measurements are available.');end
end
end

function fig=requiredPower(cfg,t)
fig=makeFigure([6.7 3.6]);ax=axes(fig);hold(ax,'on');colors=lines(numel(cfg.adc_bits));styles={'-o','--s'};
found=false;
for qi=1:numel(cfg.adc_bits)
    for si=1:numel(cfg.scheme_names)
        x=t.requirements(t.requirements.q==cfg.adc_bits(qi) & ...
            t.requirements.scheme==string(cfg.scheme_names{si}) & t.requirements.metric=="R_cycle",:);
        x=sortrows(x,'R_required');x=x(x.status=="found",:);
        if isempty(x)
            plot(ax,NaN,NaN,styles{si},'Color',colors(qi,:), ...
                'DisplayName',sprintf('q=%d, %s (NA)',cfg.adc_bits(qi),shortScheme(si)));continue;
        end
        found=true;
        errorbar(ax,x.R_required/1e6,x.P_actual_median, ...
            x.P_actual_median-x.P_actual_min,x.P_actual_max-x.P_actual_median,styles{si}, ...
            'Color',colors(qi,:),'MarkerFaceColor',colors(qi,:),'LineWidth',1.05,'CapSize',4, ...
            'DisplayName',sprintf('q=%d, %s',cfg.adc_bits(qi),shortScheme(si)));
    end
end
xlabel(ax,'Minimum required cycle payload rate (Mbit/s)');
ylabel(ax,'Lowest tested supported power (normalized units)');
xticks(ax,cfg.R_req/1e6);xlim(ax,[min(cfg.R_req)/1e6-5 max(cfg.R_req)/1e6+5]);
title(ax,[scope(t) ': requirements are lower bounds, not equal achieved rates']);style(ax);
legendStyle(legend(ax,'Location','southoutside','NumColumns',3));
if ~found
    statuses=unique(t.requirements.status);
    text(ax,0.5,0.56,{'No supported minimum tested power can be shown.', ...
        char(strjoin(statuses,', ')),'Full q/strategy/requirement statuses: rate_requirements.csv'}, ...
        'Units','normalized','HorizontalAlignment','center','FontSize',9,'Interpreter','none');
end
end

function fig=nominalCycle(cfg,t)
fig=makeFigure([6.7 3.8]);ax=axes(fig);hold(ax,'on');colors=lines(numel(cfg.adc_bits));markers={'o','s'};
anyPoint=false;limits=[];
for qi=1:numel(cfg.adc_bits)
    for si=1:numel(cfg.scheme_names)
        x=t.summary(t.summary.q==cfg.adc_bits(qi) & t.summary.scheme==string(cfg.scheme_names{si}) & ...
            t.summary.design_accepted,:);
        x=x(isfinite(x.R_nominal)&isfinite(x.R_cycle),:);if isempty(x),continue;end
        anyPoint=true;limits=[limits;x.R_nominal/1e6;x.R_cycle/1e6]; %#ok<AGROW>
        plot(ax,NaN,NaN,markers{si},'Color',colors(qi,:),'MarkerFaceColor','white', ...
            'DisplayName',sprintf('q=%d, %s',cfg.adc_bits(qi),shortScheme(si)));
        for k=1:height(x)
            condition=t.scenario(t.scenario.condition_id==x.condition_id(k) & ...
                t.scenario.scheme==x.scheme(k),:);
            assert(height(condition)==1);
            fill='white';if condition.all_rounds_supported,fill=colors(qi,:);end
            plot(ax,x.R_nominal(k)/1e6,x.R_cycle(k)/1e6,markers{si}, ...
                'Color',colors(qi,:),'MarkerFaceColor',fill,'MarkerSize',4.5,'HandleVisibility','off');
        end
    end
end
if ~isempty(limits)
    lo=0.9*min(limits);hi=1.05*max(limits);
    plot(ax,[lo hi],[lo hi],':','Color',[.4 .4 .4],'DisplayName','No-overhead reference');
    xlim(ax,[lo hi]);ylim(ax,[lo hi]);
end
xlabel(ax,'Nominal data-segment rate, R_{nominal} (Mbit/s)');
ylabel(ax,'Cycle payload rate, R_{cycle} (Mbit/s)');
title(ax,[scope(t) ': each table; fill requires its whole condition supported']);style(ax);
if anyPoint,legendStyle(legend(ax,'Location','southoutside','NumColumns',3));
else,statusText(ax,t,'No accepted loading table is available.');end
end

function fig=berPower(cfg,t)
fig=makeFigure([6.7 3.9]);ax=axes(fig);hold(ax,'on');colors=lines(numel(cfg.adc_bits));markers={'o','s'};
positive=[];anyPoint=false;
for qi=1:numel(cfg.adc_bits)
    for si=1:numel(cfg.scheme_names)
        x=t.summary(t.summary.q==cfg.adc_bits(qi) & t.summary.scheme==string(cfg.scheme_names{si}) & ...
            t.summary.payload_state=="completed",:);
        if isempty(x),continue;end
        anyPoint=true;
        plot(ax,NaN,NaN,markers{si},'Color',colors(qi,:),'DisplayName',sprintf('q=%d, %s',cfg.adc_bits(qi),shortScheme(si)));
        for k=1:height(x)
            [lo,hi]=dmt_wilson(x.total_error_bits(k),x.total_tested_bits(k));
            if x.total_error_bits(k)>0
                y=x.overall_BER(k);
                errorbar(ax,x.P_actual_median(k),y,y-lo,hi-y,'LineStyle','none', ...
                    'Marker',markers{si},'Color',colors(qi,:),'MarkerSize',4,'CapSize',3,'HandleVisibility','off');
                positive=[positive;lo;hi]; %#ok<AGROW>
            else
                plot(ax,x.P_actual_median(k),hi,'v','Color',colors(qi,:),'MarkerSize',4.5,'HandleVisibility','off');
                positive=[positive;hi]; %#ok<AGROW>
            end
        end
    end
end
if anyPoint
    plot(ax,NaN,NaN,'vk','DisplayName','Zero errors: upper endpoint');
    positive=positive(positive>0&isfinite(positive));
    yline(ax,cfg.targetBER,':k','Per-carrier target (reference)','HandleVisibility','off');
    set(ax,'YScale','log');ylim(ax,[10^floor(log10(min([positive;cfg.targetBER])))/1.5 min(1,10^ceil(log10(max([positive;cfg.targetBER])))*1.5)]);
    legendStyle(legend(ax,'Location','southoutside','NumColumns',3));
else,statusText(ax,t,'No complete per-calibration payload BER is available.');end
xlabel(ax,'Actual average optical power (normalized units)');ylabel(ax,'Overall observed BER / pointwise interval');
title(ax,[scope(t) ': unsmoothed counts; overall BER is not the per-carrier criterion']);style(ax);
end

function fig=representative(cfg,t)
fig=makeFigure([6.7 4.8]);layout=tiledlayout(fig,2,1,'Padding','compact','TileSpacing','compact');
ax1=nexttile(layout);hold(ax1,'on');ax2=nexttile(layout);hold(ax2,'on');colors=lines(numel(cfg.scheme_names));styles={'-o','--s'};markers={'o','s'};
chosen=cfg.representative;
base=t.summary(t.summary.P_target==chosen.P_target & t.summary.q==chosen.q & t.summary.calibration_id==chosen.calibration_id,:);
haveBits=false;haveBER=false;limits=[];
for si=1:numel(cfg.scheme_names)
    name=string(cfg.scheme_names{si});s=base(base.scheme==name,:);
    x=t.profiles(t.profiles.P_target==chosen.P_target & t.profiles.q==chosen.q & t.profiles.calibration_id==chosen.calibration_id & t.profiles.scheme==name,:);
    if ~isempty(x)
        x=sortrows(x,'k');haveBits=true;
        plot(ax1,x.k,x.bits_k,styles{si},'Color',colors(si,:),'MarkerSize',3.5, ...
            'LineWidth',1.0,'DisplayName',shortScheme(si));
    elseif ~isempty(s)
        text(ax1,0.02,0.90-0.17*(si-1),sprintf('%s: %s',shortScheme(si),char(s.design_status)), ...
            'Units','normalized','FontSize',8.5,'Color',colors(si,:),'Interpreter','none');
    end
    p=t.pooled(t.pooled.P_target==chosen.P_target & t.pooled.q==chosen.q & t.pooled.calibration_id==chosen.calibration_id & t.pooled.scheme==name,:);
    if isempty(p),continue;end
    p=sortrows(p,'k');haveBER=true;observed=p.error_bits>0;
    if any(observed)
        errorbar(ax2,p.k(observed),p.BER(observed),p.BER(observed)-p.CI_low(observed), ...
            p.CI_high(observed)-p.BER(observed),'LineStyle','none','Marker',markers{si}, ...
            'Color',colors(si,:),'MarkerSize',4,'CapSize',3,'HandleVisibility','off');
        limits=[limits;p.CI_low(observed)]; %#ok<AGROW>
    end
    if any(~observed)
        plot(ax2,p.k(~observed),p.CI_high(~observed),'v','Color',colors(si,:), ...
            'MarkerSize',4.5,'LineStyle','none','HandleVisibility','off');
        limits=[limits;p.CI_high(~observed)]; %#ok<AGROW>
    end
    limits=[limits;p.CI_high]; %#ok<AGROW>
    plot(ax2,NaN,NaN,markers{si},'Color',colors(si,:),'DisplayName',shortScheme(si));
end
title(ax1,sprintf('%s: predeclared P_{target}=%.3g, q=%d, calibration %d', ...
    scope(t),chosen.P_target,chosen.q,chosen.calibration_id));
xlabel(ax1,'Independent subcarrier k');ylabel(ax1,'Bits / DMT subcarrier');yticks(ax1,log2(cfg.Mset));
xlim(ax1,[min(cfg.k)-.5 max(cfg.k)+.5]);ylim(ax1,[1.5 6.5]);style(ax1);
if haveBits,legendStyle(legend(ax1,'Location','eastoutside'));end
xlabel(ax2,'Independent subcarrier k');ylabel(ax2,'Observed BER / 95% pointwise interval');style(ax2);
xlim(ax2,[min(cfg.k)-.5 max(cfg.k)+.5]);
if haveBER
    limits=limits(limits>0&isfinite(limits));
    yline(ax2,cfg.targetBER,':k','Target','HandleVisibility','off');set(ax2,'YScale','log');
    ylim(ax2,[10^floor(log10(min([limits;cfg.targetBER])))/1.5 min(1,10^ceil(log10(max([limits;cfg.targetBER])))*1.5)]);
    plot(ax2,NaN,NaN,'vk','DisplayName','Zero errors: upper endpoint');
    legendStyle(legend(ax2,'Location','eastoutside'));
else
    text(ax2,.5,.55,{'No complete payload BER for this predeclared example.', ...
        'No replacement calibration or seed has been selected.'},'Units','normalized', ...
        'HorizontalAlignment','center','FontSize',9);
end
end

function statusText(ax,t,message)
text(ax,.5,.60,{message,sprintf('Actual design cases processed: %d/%d; accepted: %d', ...
    t.design_cases_processed,t.design_cases_planned,t.design_cases_accepted), ...
    sprintf('Payload completed / rejected / incomplete: %d / %d / %d', ...
    t.completed_groups,t.rejected_groups,t.incomplete_groups)},'Units','normalized', ...
    'HorizontalAlignment','center','FontSize',9,'Interpreter','none');
end

function label=shortScheme(si)
names={'Uniform adaptive','Validated bit loading'};label=names{si};
end

function name=scope(t)
name='Formal tradeoff';if strcmp(t.phase,'preflight'),name='Preflight diagnostics only';end
end

function fig=makeFigure(sizeInches)
fig=figure('Visible','off','Color','w','Units','inches','Position',[1 1 sizeInches], ...
    'PaperUnits','inches','PaperPosition',[0 0 sizeInches],'PaperSize',sizeInches);
end

function style(ax)
set(ax,'Color','w','XColor','k','YColor','k','FontName','Arial','FontSize',8.5, ...
    'LineWidth',.7,'Box','on','GridColor',[.75 .75 .75]);grid(ax,'on');
end

function legendStyle(value)
set(value,'TextColor','k','Color','w','EdgeColor',[.6 .6 .6],'FontSize',7.7,'Interpreter','none');
end

function saveAll(fig,folder,stem)
drawnow;
exportgraphics(fig,fullfile(folder,[stem '.png']),'Resolution',300,'BackgroundColor','white');
exportgraphics(fig,fullfile(folder,[stem '.pdf']),'ContentType','vector','BackgroundColor','white');
print(fig,fullfile(folder,[stem '.svg']),'-dsvg','-painters');
savefig(fig,fullfile(folder,[stem '.fig']));
for ext={'.png','.pdf','.svg','.fig'}
    file=dir(fullfile(folder,[stem ext{1}]));assert(~isempty(file)&&file.bytes>0);
end
end

function writeCaptions(cfg,t,outDir)
fid=fopen(fullfile(outDir,'figure_captions_en.txt'),'w','n','UTF-8');assert(fid>=0);
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s; generated only from this phase, never from old counts.\n\n',scope(t));
fprintf(fid,['rate_vs_actual_power: Actual average normalized optical power versus allocated nominal and cycle payload rates. ' ...
    'Colors identify ideal ADC bits and line styles identify the two loading strategies. Filled points require every one of the %d ' ...
    'predeclared calibration rounds to be BER-supported and every payload power-matched. Open points give the observed supported-round ' ...
    'count; all design-rejected, failed, inconclusive and incomplete rounds remain in scenario_summary.csv. ' ...
    'NA series remain in the legend; unresolved conditions and rejected points without measured payload power are not given fabricated x coordinates. ' ...
    'Ranges are minima and maxima across actual accepted tables/payloads, not confidence bands. Lines connect tested samples only.\n\n'], ...
    unique(t.scenario.planned_calibrations));
fprintf(fid,['required_tested_power: Lowest tested supported power for each minimum required cycle payload rate, using the minimum R_cycle across ' ...
    'all calibration rounds. Horizontal requirements are lower bounds, not equal achieved rates. No interpolation or untested operating point is used. ' ...
    'Missing/not-found/incomplete statuses are retained in rate_requirements.csv; ranges show actual power extrema, not confidence intervals.\n\n']);
L=cfg.payload_symbols;if strcmp(t.phase,'preflight'),L=cfg.preflight_payload_symbols;end
fprintf(fid,['nominal_vs_cycle_rate: Each accepted table before and after initialization/validation overhead. One displayed cycle has L=%d payload DMT symbols; ' ...
    'statistical repeats do not form a 2L cycle. The setup includes initial A0/B0 and every attempted A_r/D_r. Pure TX-power calibration is computation only. ' ...
    'Control delay is idealized as zero; feedback quantities are recorded separately. Each point is one calibration table, not an aggregate BER. ' ...
    'It is filled only when every calibration in the same condition/strategy is formally BER-supported and all payloads are power-matched.\n\n'],L);
fprintf(fid,['BER_vs_actual_power: Unsmoothed overall count ratios and pointwise Wilson approximations within each condition/calibration/strategy. ' ...
    'Zero-error records are triangles at their nonzero upper endpoints. The overall BER is diagnostic; the scientific requirement is per subcarrier.\n\n']);
fprintf(fid,['representative_loading_BER: The predeclared example is P_target=1, ideal q=8, calibration 1. It is never replaced by a more favorable example. ' ...
    'Accepted M tables and actual pooled payload BER are shown separately; missing/rejected states are labeled. ' ...
    'Zero errors use upper-endpoint triangles. Intervals are z=1.96 approximate pointwise 95%% Wilson intervals, not a joint guarantee.\n\n']);
fprintf(fid,['Power is normalized and includes CP; no mW/dBm calibration is implied. q is ideal quantization resolution, not ENOB, price or total ADC power. ' ...
    'The sampled IM/DD/thermal-noise model is simplified; no optical device dynamics, full dispersion, FEC or physical feedback implementation is inferred.\n']);
end
