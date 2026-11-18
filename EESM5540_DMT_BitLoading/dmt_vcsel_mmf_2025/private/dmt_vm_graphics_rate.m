function dmt_vm_graphics_rate(fig,data)
%DMT_VM_GRAPHICS_RATE Show supported rates and paired length sensitivity.
keys=["UniformValidated" "PerToneValidated"];
labels=["Uniform validated" "Per-tone validated"];
colors=[.12 .39 .67;.83 .31 .11];
lines={'-o','--s'};
layout=tiledlayout(fig,2,2,'TileSpacing','compact','Padding','compact');
title(layout,'Qualified Cycle Rate and Setup Trade-off','Color','black');
subtitle(layout,sprintf('Normalized 50 m VCSEL–MMF response | 8-bit ADC | Main L = %d symbols', ...
    data.payload_symbols),'Color','black');
command=unique(data.scenario.swing).';
assert(isequal(command,[.25 .50 .75]) && height(data.scenario)==12);
eligible=data.scenario.qualified;
maximum=max([1;data.scenario.R_cycle_max(eligible)/1e9]);
for c=1:2
    ax=nexttile(layout);hold(ax,'on');
    caseRows=data.scenario(data.scenario.case_id==c,:);
    byStrategy=cell(1,numel(keys));
    for j=1:numel(keys)
        rows=sortrows(caseRows(caseRows.strategy==keys(j),:),'swing');
        assert(isequal(rows.swing,command.') && all(rows.planned_calibrations==5));
        byStrategy{j}=rows;
        good=rows.qualified;
        y=nan(height(rows),1);
        y(good)=rows.R_cycle_median(good)/1e9;
        plot(ax,rows.swing,y,lines{j},'Color',colors(j,:), ...
            'LineWidth',1.45,'MarkerSize',5,'DisplayName',char(labels(j)));
        if any(good)
            low=rows.R_cycle_min(good)/1e9;
            high=rows.R_cycle_max(good)/1e9;
            assert(all(low<=y(good) & y(good)<=high));
            errorbar(ax,rows.swing(good),y(good),y(good)-low,high-y(good), ...
                'LineStyle','none','Color',colors(j,:),'CapSize',6,'HandleVisibility','off');
        end
    end
    for j=1:numel(command)
        U=pointText(byStrategy{1}(j,:),data.summary,"U",numel(data.k));
        P=pointText(byStrategy{2}(j,:),data.summary,"P",numel(data.k));
        text(ax,command(j),1.13*maximum,sprintf('%s\n%s',U,P), ...
            'FontSize',7.6,'HorizontalAlignment','center','Color',[.17 .17 .17], ...
            'Interpreter','none');
    end
    title(ax,sprintf('Case %d',c),'Color','black');
    xlim(ax,[.13 .87]);ylim(ax,[0 1.29*maximum]);
    xticks(ax,command);
    xlabel(ax,'Commanded modulation swing','Color','black');
    if c==1,ylabel(ax,'Qualified cycle rate (Gbit/s)','Color','black');end
    if ~any(caseRows.qualified)
        text(ax,.5,.48,'No condition supported in all five calibrations', ...
            'Units','normalized','HorizontalAlignment','center','Color',[.25 .25 .25]);
    else
        legend(ax,'Location','best','Color','white','TextColor','black','FontSize',8);
    end
    style(ax);
end
ax=nexttile(layout,[1 2]);
drawSensitivity(ax,data,labels,colors,lines);
end

function value=pointText(point,summary,short,toneCount)
items=summary(summary.case_id==point.case_id & summary.swing==point.swing & ...
    summary.strategy==point.strategy,:);
assert(height(items)==point.planned_calibrations);
value=short+" "+string(point.supported_count)+"/"+string(point.planned_calibrations);
states=["design_rejected" "ber_failed" "inconclusive" "power_mismatch" ...
    "power_error" "execution_error" "incomplete"];
codes=["D" "B" "I" "W" "E" "E" "?"];
for j=1:numel(states)
    n=sum(items.state==states(j));
    if n>0,value=value+" "+codes(j)+string(n);end
end
if short=="U"
    bits=items.bits_per_symbol(isfinite(items.bits_per_symbol));
    M=unique(round(2.^(bits/toneCount)));
    if ~isempty(M),value=value+" (M "+strjoin(string(M.') ,"/")+")";end
end
end

function drawSensitivity(ax,data,labels,colors,lines)
hold(ax,'on');
ref=data.representative;
s=data.sensitivity;
assert(~any(isfinite(s.uniform_R_cycle(~s.pair_qualified))) && ...
    ~any(isfinite(s.pertone_R_cycle(~s.pair_qualified))), ...
    'DMT:VMFigurePair','A nonqualified calibration cannot supply a plotted rate pair.');
paired=s(s.pair_qualified,:);
title(ax,sprintf('Payload-length sensitivity | Case %d, swing %.2f',ref.case_id,ref.swing),'Color','black');
set(ax,'XScale','log');
xlim(ax,[1e3 1e5]);
xlabel(ax,'Payload symbols per configuration, L','Color','black');
ylabel(ax,'Cycle rate (Gbit/s)','Color','black');
xline(ax,data.payload_symbols,':','Main L','Color',[.2 .2 .2], ...
    'LabelHorizontalAlignment','left','HandleVisibility','off');
if isempty(paired)
    text(ax,.5,.51,'No supported, resource-matched pair at the representative point', ...
        'Units','normalized','HorizontalAlignment','center','Color',[.19 .19 .19]);
    style(ax);
    return;
end
L=unique(paired.L);
[cals,first]=unique(paired.calibration_id,'stable');
values={'uniform_R_cycle','pertone_R_cycle'};
for j=1:numel(values)
    lo=zeros(size(L));middle=lo;hi=lo;
    for i=1:numel(L)
        y=paired.(values{j})(paired.L==L(i))/1e9;
        assert(numel(y)==numel(cals) && all(isfinite(y)));
        lo(i)=min(y);middle(i)=median(y);hi(i)=max(y);
    end
    fill(ax,[L;flipud(L)],[lo;flipud(hi)],colors(j,:),'FaceAlpha',.13, ...
        'EdgeColor','none','HandleVisibility','off');
    plot(ax,L,middle,lines{j}(1:end-1),'Color',colors(j,:), ...
        'LineWidth',1.6,'DisplayName',char(labels(j)));
end
cross=paired.cross_over_L(first);
coincident=sum(paired.cross_over_status(first)=="identical_cycle_rates");
cross=cross(isfinite(cross) & cross>0);
inside=unique(cross(cross>=1e3 & cross<=1e5));
for j=1:numel(inside)
    xline(ax,inside(j),'--','Color',[.50 .50 .50],'HandleVisibility','off');
end
n=numel(cals);
if isempty(cross)
    note=sprintf('%d/5 qualified pairs | No isolated positive crossover',n);
else
    note=sprintf('%d/5 qualified pairs | %d positive crossover(s), L = %.0f–%.0f', ...
        n,numel(cross),min(cross),max(cross));
end
if coincident>0,note=sprintf('%s | %d coincident',note,coincident);end
subtitle(ax,note,'FontSize',8,'Color',[.20 .20 .20]);
legend(ax,'Location','best','Color','white','TextColor','black','FontSize',8);
style(ax);
end

function style(ax)
set(ax,'Color','white','XColor','black','YColor','black','FontSize',9, ...
    'Box','on','GridColor',[.83 .83 .83],'Layer','top');
grid(ax,'on');
end
