function dmt_vm_graphics_rate(fig,data)
%DMT_VM_GRAPHICS_RATE Render formal capacity, rate and measured setup.
keys=["UniformValidated" "PerToneValidated"];
labels={'Uniform validated','Per-tone validated'};
colors=[.10 .36 .68;.80 .29 .12];
markers={'o','s'};
points=unique(data.scenario(:,{'case_id','swing'}),'rows','sorted');
assert(isequal(points{:,:},[1 .25;1 .50;1 .75;2 .25;2 .50;2 .75]), ...
    'DMT:VMPostFigurePoints','Figure A requires the six formal work points.');
n=height(points);
focus=find((points.case_id==1 & points.swing==.25) | ...
    (points.case_id==2 & points.swing==.50));
workLabels=compose('C%d / %.2f',points.case_id,points.swing);
workLabels(focus)=workLabels(focus)+" *";
panel=makePanels(fig,workLabels,data.payload_symbols);
summary=data.summary;
complete=summary.payload_slots_completed==2;
bitsMax=max([1;summary.bits_per_symbol(complete)]);
ratesMax=max([1;summary.R_nominal(complete)/1e9]);
attempted=ismember(summary.design_state,["accepted","design_rejected"]);
setupMax=max([1;summary.T_setup_s(attempted)*1e6]);
attemptMax=max([1;summary.attempts(attempted)]);
y=[1.22*bitsMax 1.34*ratesMax 1.16*setupMax attemptMax+.43];
for j=1:numel(panel)
    highlight(panel(j),focus,y(j));
    ylim(panel(j),[0 y(j)]);
end
offset=[-.16 .16];
for c=1:n
    for strategy=1:numel(keys)
        design=matching(summary,points(c,:),keys(strategy));
        outcome=matching(data.scenario,points(c,:),keys(strategy));
        assert(height(design)==5 && height(outcome)==1 && outcome.planned_calibrations==5 && ...
            all(design.phase=="formal") && all(design.q==8));
        sent=design(design.payload_slots_completed==2,:);
        x=c+offset(strategy);
        color=colors(strategy,:);
        marker=markers{strategy};
        drawCapacity(panel(1),sent,x,color,marker);
        drawRates(panel(2),outcome,sent,x,color,marker);
        configured=design(ismember(design.design_state,["accepted","design_rejected"]),:);
        drawSetup(panel(3),configured,configured.T_setup_s*1e6,x,color,marker);
        drawSetup(panel(4),configured,configured.attempts,x,color,marker);
        text(panel(2),x,ratesMax*(1.20+.075*(strategy-1)),rateStatus(outcome,sent,strategy), ...
            'HorizontalAlignment','center','FontSize',7.1,'Interpreter','none','Color',color);
    end
end
if ~any(complete)
    noPayload(panel(1));
    noPayload(panel(2));
end
if isfield(data,'pairs')
    for j=reshape(focus,1,[])
        pair=data.pairs(data.pairs.case_id==points.case_id(j) & ...
            data.pairs.swing==points.swing(j) & data.pairs.pair_qualified,:);
        value='No supported pair';
        if ~isempty(pair)
            delta=pair.pertone_bits_per_symbol-pair.uniform_bits_per_symbol;
            assert(all(isfinite(delta)));
            value=sprintf('P−U %+.0f bit (%d/5)',median(delta),height(pair));
        end
        text(panel(1),j,1.13*bitsMax,value,'HorizontalAlignment','center','FontSize',7.4, ...
            'Color',[.16 .16 .16],'Interpreter','none');
    end
end
styleLegend(panel(1),keys,labels,colors,markers);
rateLegend(panel(2));
setupLegend(panel(3));
yticks(panel(4),0:attemptMax);
end

function panel=makePanels(fig,workLabels,payloadSymbols)
layout=tiledlayout(fig,2,2,'TileSpacing','compact','Padding','compact');
title(layout,'DMT Payload Capacity, Cycle Rate and Configuration Cost','Color','black');
subtitle(layout,sprintf(['Normalized 50 m VCSEL–MMF | 8-bit ADC | L = %d DMT symbols | ' ...
    '* Focus points'],payloadSymbols),'Color','black');
metrics={'Bits per DMT symbol','Payload and qualified cycle rates', ...
    'Actual forward-link setup time','Actual candidate validations'};
units={'bit/DMT symbol','Rate (Gbit/s)','Setup time (µs)','Verification attempts'};
panel=gobjects(1,numel(metrics));
for j=1:numel(metrics)
    ax=nexttile(layout);hold(ax,'on');
    title(ax,metrics{j},'Color','black');
    set(ax,'Color','white','XColor','black','YColor','black','FontSize',8.8, ...
        'Box','on','GridColor',[.84 .84 .84],'Layer','top','XGrid','off','YGrid','on');
    xlim(ax,[.53 numel(workLabels)+.47]);
    xticks(ax,1:numel(workLabels));xticklabels(ax,workLabels);
    ylabel(ax,units{j},'Color','black');
    if j>2,xlabel(ax,'Channel case and commanded swing','Color','black');end
    panel(j)=ax;
end
end

function highlight(ax,focus,upper)
for x=reshape(focus,1,[])
    patch(ax,x+[-.45 .45 .45 -.45],[0 0 upper upper],[.98 .956 .885], ...
        'EdgeColor','none','HandleVisibility','off');
end
end

function t=matching(t,point,strategy)
t=t(t.case_id==point.case_id & t.swing==point.swing & t.strategy==strategy,:);
end

function drawCapacity(ax,sent,x,color,marker)
if isempty(sent),return;end
v=sent.bits_per_symbol;
assert(all(isfinite(v) & v>0 & v==fix(v)), ...
    'DMT:VMPostBits','A sent payload must have a saved positive bit allocation.');
plotRange(ax,v,x,color,marker,'filled');
end

function drawRates(ax,outcome,sent,x,color,marker)
if isempty(sent)
    assert(~outcome.qualified);
    return;
end
nominal=sent.R_nominal/1e9;
assert(all(isfinite(nominal) & nominal>0));
if outcome.qualified
    cycle=sent.R_cycle/1e9;
    assert(height(sent)==5 && all(sent.state=="supported") && ...
        all(isfinite(cycle) & cycle>0 & cycle<=nominal), ...
        'DMT:VMPostRateQualification','Qualified rates require five supported calibrations.');
    % The line compares nominal and cycle medians of the same strategy and rounds.
    plot(ax,[x x],[median(cycle) median(nominal)],'-','Color',color, ...
        'LineWidth',1.4,'HandleVisibility','off');
    plotRange(ax,cycle,x,color,marker,'filled');
end
plotRange(ax,nominal,x,color,marker,'open');
end

function plotRange(ax,v,x,color,marker,kind)
at=median(v);
errorbar(ax,x,at,at-min(v),max(v)-at,'LineStyle','none','LineWidth',.9, ...
    'Color',color,'CapSize',5,'HandleVisibility','off');
face=color;
if strcmp(kind,'open'),face='white';end
plot(ax,x,at,marker,'Color',color,'MarkerFaceColor',face, ...
    'MarkerSize',5.8,'LineWidth',1.15,'HandleVisibility','off');
end

function drawSetup(ax,t,value,x,color,marker)
if isempty(t),return;end
assert(all(isfinite(value) & value>=0));
[~,order]=sort(t.calibration_id);
t=t(order,:);
value=value(order);
shift=reshape(linspace(-.055,.055,height(t)),[],1);
shift=shift-mean(shift);
rejected=t.design_state=="design_rejected";
plot(ax,x+shift(~rejected),value(~rejected),marker,'Color',color, ...
    'MarkerSize',4.7,'LineWidth',.95,'HandleVisibility','off');
plot(ax,x+shift(rejected),value(rejected),'x','Color',color, ...
    'MarkerSize',5.3,'LineWidth',1.1,'HandleVisibility','off');
c=median(value);
plot(ax,x+[-.075 .075],[c c],'-','Color',color,'LineWidth',1.35,'HandleVisibility','off');
end

function caption=rateStatus(outcome,sent,strategy)
prefix=["U" "P"];
caption=prefix(strategy)+" "+string(outcome.supported_count)+"/5";
if isempty(sent) && outcome.design_rejected_count==5
    caption=prefix(strategy)+" rejected";
elseif isempty(sent)
    caption=prefix(strategy)+" no payload";
end
end

function styleLegend(ax,keys,labels,colors,markers)
handles=gobjects(1,numel(keys));
for j=1:numel(keys)
    handles(j)=plot(ax,NaN,NaN,markers{j},'Color',colors(j,:), ...
        'MarkerFaceColor',colors(j,:),'MarkerSize',5.5);
end
legend(ax,handles,labels,'Location','southoutside','Orientation','horizontal', ...
    'Color','white','TextColor','black','FontSize',8,'Box','off');
end

function rateLegend(ax)
symbol=[.28 .28 .28];
open=plot(ax,NaN,NaN,'o','Color',symbol,'MarkerFaceColor','white','MarkerSize',5.5);
filled=plot(ax,NaN,NaN,'o','Color',symbol,'MarkerFaceColor',symbol,'MarkerSize',5.5);
legend(ax,[open filled],{'Nominal (formal payload)','Qualified cycle (5/5)'}, ...
    'Location','southoutside','Orientation','horizontal','Color','white', ...
    'TextColor','black','FontSize',8,'Box','off');
end

function setupLegend(ax)
symbol=[.29 .29 .29];
accepted=plot(ax,NaN,NaN,'o','Color',symbol,'MarkerSize',4.7);
rejected=plot(ax,NaN,NaN,'x','Color',symbol,'MarkerSize',5.3);
middle=plot(ax,NaN,NaN,'-','Color',symbol,'LineWidth',1.35);
legend(ax,[accepted rejected middle],{'Accepted design','Rejected design','Median'}, ...
    'Location','southoutside','Orientation','horizontal','Color','white', ...
    'TextColor','black','FontSize',8,'Box','off');
end

function noPayload(ax)
text(ax,.5,.49,'No complete formal payload pairs','Units','normalized', ...
    'HorizontalAlignment','center','Color',[.23 .23 .23],'FontSize',9);
end
