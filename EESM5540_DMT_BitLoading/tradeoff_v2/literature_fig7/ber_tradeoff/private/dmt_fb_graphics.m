function manifest = dmt_fb_graphics(folder,study,cfg,tables,action)
%DMT_FB_GRAPHICS Draw or audit figures from reconstructed formal tables.
if nargin<5,action='draw';end
assert(any(strcmp(action,{'draw','verify'})),'DMT:FBGraphicsAction','Unknown graphics action.');
switch study
    case 'promotion'
        figureName='fig_A_promotion_subcarrier';
        data=representative(cfg,tables);
        caption=['Fig. A. Experiment 2, formal calibration 1, with the normalized Fig. 7 ' ...
            'channel (Zhong et al., 2015, doi:10.1364/OE.23.001176), target mean transmit ' ...
            'optical power 1.0 and 8-bit ADC. ' ...
            'The B0 estimate is shared. Selected profiles and payload BER are shown separately ' ...
            'for original verified loading and promotion-first loading. Counts are pooled only ' ...
            'over the two slots within this calibration. Bars indicate pointwise 95% Wilson ' ...
            'intervals. Downward triangles mark upper bounds for zero observed errors.'];
    case 'scan'
        figureName='fig_B_qualified_cycle_payload_rate';
        [points,requirements,pairs]=dmt_fb_graphics_scan(cfg,tables);
        data=struct('points',points,'requirements',requirements,'adc_comparisons',pairs);
        caption=['Fig. B. Experiment 1 with the normalized Fig. 7 channel ' ...
            '(Zhong et al., 2015, doi:10.1364/OE.23.001176). A point shows the ' ...
            'maximum measured mean transmit optical power over all ten payload slots and ' ...
            'the median qualified cycle payload rate. Bars span the minimum and maximum rates ' ...
            'across the five calibrations. Qualification requires all five calibrations to ' ...
            'satisfy the pointwise BER criterion and power matching. The status grid shows ' ...
            'supported calibration counts and the states of other calibrations.'];
    otherwise
        error('DMT:FBGraphicsStudy','Unknown formal study %s.',study);
end
png=string(figureName)+".png";
pdf=string(figureName)+".pdf";
manifestPath=fullfile(folder,'figure_manifest.csv');
dataHash=string(dmt_v13_hash(data));
names={'figure','png_file','pdf_file','data_sha256','png_sha256','pdf_sha256'};
if strcmp(action,'verify')
    manifest=figureManifest();
    dmt_fb_audit_csv(manifestPath,manifest);
    dmt_fb_audit_csv(fullfile(folder,'report_manifest.csv'),reportManifest(folder,study));
    if strcmp(study,'scan')
        dmt_fb_audit_csv(fullfile(folder,'scan_condition_results.csv'),points);
        dmt_fb_audit_csv(fullfile(folder,'scan_75Mbps_min_power.csv'),requirements);
        dmt_fb_audit_csv(fullfile(folder,'scan_adc_comparisons.csv'),pairs);
    end
    return;
end
if ~isfolder(folder),mkdir(folder);end
fig=figure('Visible','off','Color','white','Units','inches','Position',[1 1 8.8 7.6], ...
    'InvertHardcopy','off','PaperPositionMode','auto');
closeFigure=onCleanup(@()close(fig)); %#ok<NASGU>
switch study
    case 'promotion'
        drawPromotion(fig,data);
    case 'scan'
        drawScan(fig,points);
        writetable(points,fullfile(folder,'scan_condition_results.csv'),'Encoding','UTF-8');
        writetable(requirements,fullfile(folder,'scan_75Mbps_min_power.csv'),'Encoding','UTF-8');
        writetable(pairs,fullfile(folder,'scan_adc_comparisons.csv'),'Encoding','UTF-8');
end
exportgraphics(fig,fullfile(folder,png),'Resolution',300,'BackgroundColor','white');
exportgraphics(fig,fullfile(folder,pdf),'ContentType','vector','BackgroundColor','white');
writeCaption(folder,caption);
dmt_fb_graphics_notes(folder,study,cfg,tables,data);
writetable(reportManifest(folder,study),fullfile(folder,'report_manifest.csv'),'Encoding','UTF-8');
manifest=figureManifest();
writetable(manifest,manifestPath,'Encoding','UTF-8');

    function record=figureManifest()
        record=table(string(figureName),png,pdf,dataHash,fileHash(fullfile(folder,png)), ...
            fileHash(fullfile(folder,pdf)),'VariableNames',names);
    end
end

function manifest=reportManifest(folder,study)
files=["figure_caption_en.txt";"results_zh.md"];
if strcmp(study,'scan')
    files=[files;"scan_condition_results.csv";"scan_75Mbps_min_power.csv"; ...
        "scan_adc_comparisons.csv"];
end
hashes=strings(size(files));
for j=1:numel(files),hashes(j)=fileHash(fullfile(folder,files(j)));end
manifest=table(files,hashes,'VariableNames',{'report_file','sha256'});
end

function data=representative(cfg,tables)
branch={tables.original,tables.promotion};
ref=cfg.representative;
assert(ref.calibration_id==1 && ref.P_target==1 && ref.q==8,'DMT:FBGraphicsPoint', ...
    'Fig. A uses the predeclared calibration 1 at 1.0 and 8-bit ADC.');
data=struct('k',cfg.k(:),'target',cfg.targetBER,'snr',[], ...
    'profile',{{[],[]}},'pool',{{[],[]}},'state',strings(1,2));
for b=1:2
    t=branch{b};
    summary=select(t.summary,ref);
    assert(height(summary)==1 && ~summary.test_only && summary.phase=="formal");
    snr=sortrows(select(t.snr,ref),'k');
    assert(isequal(snr.k,data.k),'DMT:FBGraphicsSNR','Missing representative SNR rows.');
    if b==1
        data.snr=snr;
    else
        keep={'k','SNR_dB','data_seed','noise_seed'};
        assert(isequaln(data.snr(:,keep),snr(:,keep)),'DMT:FBGraphicsSNR', ...
            'The two branches must use the same probe evidence.');
    end
    data.profile{b}=sortrows(select(t.profiles,ref),'k');
    data.pool{b}=sortrows(select(t.pool,ref),'k');
    data.state(b)=summary.state;
end
end

function selected=select(t,ref)
selected=t(t.P_target==ref.P_target & t.q==ref.q & ...
    t.calibration_id==ref.calibration_id,:);
end

function drawPromotion(fig,data)
layout=tiledlayout(fig,3,1,'TileSpacing','compact','Padding','compact');
title(layout,'Per-subcarrier SNR, Bit Loading and Observed BER','Color','black');
subtitle(layout,'Fig. 7 channel | Experiment 2, calibration 1 | Power 1.0, 8-bit ADC', ...
    'Color','black','Interpreter','none');
axesSNR=nexttile(layout);
axesBits=nexttile(layout);
axesBER=nexttile(layout);
hold(axesSNR,'on');hold(axesBits,'on');hold(axesBER,'on');
colors=[.12 .37 .68;.85 .32 .1];
labels={'Original verified loading','Promotion-first loading'};
styles={'-','--'};
markers={'o','s'};
k=data.k;
snr=data.snr;
plot(axesSNR,k,snr.SNR_dB,'-o','Color',colors(1,:),'LineWidth',1.3, ...
    'MarkerSize',3.5,'DisplayName','Shared B0 estimate');
thresholdNames={'threshold_M4_dB','threshold_M16_dB','threshold_M64_dB'};
thresholdLabels={'QPSK','16-QAM','64-QAM'};
for j=1:numel(thresholdNames)
    values=snr.(thresholdNames{j});
    assert(all(values==values(1)),'DMT:FBGraphicsThreshold','SNR threshold varies by carrier.');
    yline(axesSNR,values(1),':',thresholdLabels{j},'Color',[.34 .34 .34], ...
        'FontSize',8,'HandleVisibility','off','LabelHorizontalAlignment','left');
end
ylabel(axesSNR,'Effective SNR (dB)');
legendStyle(legend(axesSNR,'Location','northeast'));
shownProfile=false;shownBER=false;
profileNotes=strings(0,1);BERNotes=strings(0,1);
berLimits=data.target;
for b=1:2
    p=data.profile{b};
    absent=string(labels{b})+" ("+replace(data.state(b),"_"," ")+")";
    if isempty(p)
        profileNotes(end+1,1)=absent; %#ok<AGROW>
    else
        assert(isequal(p.k,k));
        stairs(axesBits,p.k,p.bits_k,'LineStyle',styles{b},'Marker',markers{b}, ...
            'MarkerSize',3.8,'Color',colors(b,:),'LineWidth',1.45,'DisplayName',labels{b});
        shownProfile=true;
    end
    counts=data.pool{b};
    if isempty(counts)
        BERNotes(end+1,1)=absent; %#ok<AGROW>
        continue;
    end
    assert(isequal(counts.k,k) && all(counts.CI_high>0));
    % Offsets distinguish the two sets of markers at each integer carrier.
    x=counts.k+(-1)^b*.08;
    positive=counts.error_bits>0;
    if any(positive)
        y=counts.BER(positive);
        low=counts.CI_low(positive);
        high=counts.CI_high(positive);
        assert(all(low>0 & low<=y & high>=y));
        errorbar(axesBER,x(positive),y,y-low,high-y,'LineStyle','none', ...
            'Color',colors(b,:),'Marker',markers{b},'MarkerSize',4,'CapSize',3, ...
            'LineWidth',.95,'DisplayName',labels{b});
        berLimits=[berLimits;low;high]; %#ok<AGROW>
    end
    zero=~positive;
    if any(zero)
        plot(axesBER,x(zero),counts.CI_high(zero),'v','Color',colors(b,:), ...
            'MarkerSize',4,'MarkerFaceColor','white','DisplayName',[labels{b} ' (zero errors)']);
        berLimits=[berLimits;counts.CI_high(zero)]; %#ok<AGROW>
    end
    shownBER=true;
end
ylabel(axesBits,'Bits per subcarrier');
ylim(axesBits,[1.5 6.5]);yticks(axesBits,[2 4 6]);
if shownProfile,legendStyle(legend(axesBits,'Location','southwest'));end
ylabel(axesBER,'Observed BER');
set(axesBER,'YScale','log');
yline(axesBER,data.target,':k',sprintf('BER target = %.0e',data.target),'HandleVisibility','off', ...
    'LabelHorizontalAlignment','left');
ylim(axesBER,[.7*min(berLimits) 1.55*max(berLimits)]);
if shownBER,legendStyle(legend(axesBER,'Location','best','NumColumns',2));end
note(axesBits,profileNotes);
note(axesBER,BERNotes);
for ax=[axesSNR axesBits axesBER]
    for carrier=[23 24]
        xline(ax,carrier,':','Color',[.52 .52 .52],'HandleVisibility','off');
    end
    axesStyle(ax);
    xlim(ax,[.65 24.45]);xticks(ax,[1 4 8 12 16 20 23 24]);
end
linkaxes([axesSNR axesBits axesBER],'x');
xlabel(layout,'Active subcarrier index','Color','black');
end

function drawScan(fig,points)
layout=tiledlayout(fig,4,1,'TileSpacing','compact','Padding','compact');
title(layout,'Qualified Cycle Payload Rate versus Measured Mean Transmit Optical Power', ...
    'Color','black');
subtitle(layout,'Fig. 7 channel | Experiment 1','Color','black');
ax=nexttile(layout,[3 1]);hold(ax,'on');
schemeNames=["FixedQPSK","Fixed64QAM","ValidatedLoading"];
schemeLabels=["Fixed QPSK","Fixed 64-QAM","Validated loading"];
adcs=[6 8];
colors=[.13 .42 .68;.83 .30 .08];
styles={'-','--',':'};
markers={'o','s','^'};
pTargets=unique(points.P_target,'sorted').';
for qa=1:numel(adcs)
    for si=1:numel(schemeNames)
        rows=sortrows(points(points.q==adcs(qa) & points.scheme==schemeNames(si),:),'P_target');
        assert(isequal(rows.P_target,pTargets.'));
        x=rows.qualified_power_max;
        y=rows.qualified_rate_median_Mbps;
        plot(ax,x,y,'Color',colors(qa,:),'LineStyle',styles{si},'Marker',markers{si}, ...
            'LineWidth',1.35,'MarkerSize',4.5,'DisplayName',sprintf('%d bit, %s',adcs(qa),schemeLabels(si)));
        ok=rows.qualified;
        if any(ok)
            errorbar(ax,x(ok),y(ok),y(ok)-rows.qualified_rate_min_Mbps(ok), ...
                rows.qualified_rate_max_Mbps(ok)-y(ok),'LineStyle','none','Color',colors(qa,:), ...
                'CapSize',5,'HandleVisibility','off');
        end
    end
end
yline(ax,75,':k','75 Mbit/s requirement','HandleVisibility','off', ...
    'LabelHorizontalAlignment','left');
xlabel(ax,'Maximum measured mean transmit optical power (normalized)');
ylabel(ax,'Qualified cycle payload rate (Mbit/s)');
xlim(ax,[min(pTargets)-.05 max(pTargets)+.05]);
ranges=points.qualified_rate_max_Mbps(points.qualified);
ylim(ax,[0 max([85;1.12*ranges])]);
if isempty(ranges)
    text(ax,.5,.50,'No condition qualified across all five calibrations', ...
        'Units','normalized','HorizontalAlignment','center','Color',[.19 .19 .19]);
end
legendStyle(legend(ax,'Location','northwest','NumColumns',2));
axesStyle(ax);

state=nexttile(layout);hold(state,'on');
title(state,'Supported calibrations by target power (numerator out of five)', ...
    'Color','black','FontSize',9);
set(state,'Color','white','XColor','black','YColor','black','FontSize',8,'YDir','reverse');
xlim(state,[.5 numel(pTargets)+.5]);ylim(state,[.5 6.5]);
xticks(state,1:numel(pTargets));xticklabels(state,compose('%.1f',pTargets));
yticks(state,1:6);
labels=strings(6,1);
for qa=1:2
    for si=1:3
        row=(qa-1)*3+si;
        labels(row)=sprintf('%d bit, %s',adcs(qa),schemeLabels(si));
        for p=1:numel(pTargets)
            r=points(points.q==adcs(qa) & points.scheme==schemeNames(si) & ...
                points.P_target==pTargets(p),:);
            assert(height(r)==1);
            color=[.955 .955 .955];
            if r.qualified,color=[.90 .955 .90];end
            rectangle(state,'Position',[p-.49 row-.49 .98 .98],'FaceColor',color,'EdgeColor','none');
            text(state,p,row,statusText(r),'HorizontalAlignment','center','Color','black','FontSize',8);
        end
    end
end
yticklabels(state,labels);
xlabel(state,['Target power   |   B: BER failure   I: inconclusive   R: rejected' ...
    '   P: power issue   E: execution error   U: incomplete'], ...
    'Color','black','FontSize',8);
end

function value=statusText(r)
power=r.power_mismatch_count+r.power_error_count;
counts=[r.ber_failed_count r.inconclusive_count r.design_rejected_count power ...
    r.execution_error_count r.incomplete_count];
tokens=["B" "I" "R" "P" "E" "U"];
value=string(r.supported_count)+"/"+string(r.planned_calibrations);
if any(counts>0),value=value+"   "+strjoin(tokens(counts>0)+string(counts(counts>0))," ");end
end

function note(ax,missing)
if ~isempty(missing)
    subtitle(ax,strjoin(missing," | "),'Interpreter','none','Color',[.25 .25 .25],'FontSize',8);
end
end

function axesStyle(ax)
set(ax,'Box','on','Color','white','XColor','black','YColor','black','FontSize',9, ...
    'GridColor',[.82 .82 .82],'Layer','top');
grid(ax,'on');
end

function legendStyle(handle)
set(handle,'Color','white','TextColor','black','FontSize',8,'Interpreter','none');
end

function writeCaption(folder,caption)
fid=fopen(fullfile(folder,'figure_caption_en.txt'),'wt');
assert(fid>=0,'DMT:FBGraphicsWrite','Cannot write the English figure caption.');
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',caption);
end

function value=fileHash(path)
details=dir(path);
assert(isscalar(details) && details.bytes>0,'DMT:FBGraphicsFile', ...
    'Figure file %s is missing or empty.',path);
value=string(dmt_fb_filehash(path));
end
