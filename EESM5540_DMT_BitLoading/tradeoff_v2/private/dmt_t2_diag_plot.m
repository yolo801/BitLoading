function [manifest, caption] = dmt_t2_diag_plot(settings,summary,outDir)
%DMT_T2_DIAG_PLOT Render independent diagnostic measurements only.
stem = 'fig4_separating_tx_clipping_and_adc_quantization';
label = 'Separating Transmitter Clipping and ADC Quantization';
assert(height(summary)==4*settings.calibration_count && ...
    all(summary.phase==settings.phase));
fig = figure('Visible','off','Color','w','Units','inches','Position',[1 1 10 6]);
closer = onCleanup(@()close(fig)); %#ok<NASGU>
layout = tiledlayout(fig,2,2,'Padding','compact','TileSpacing','compact');
title(layout,label,'Color','k','FontWeight','bold');
xlabel(layout,sprintf(['Independent 2-by-2 diagnostic at target mean optical power %.1f (normalized)\n' ...
    'Gray lines pair random realizations. Open markers indicate unmatched measured power.'], ...
    settings.P_target),'Color','k');
variables = {'tx_clip_rate','Umax_over_target','adc_out_of_range_rate','P_measured_mean'};
labels = {'Transmitter clipping (%)','Worst-carrier Wilson upper bound / target', ...
    'ADC input outside range (%)','Mean measured optical power (normalized)'};
colors = [0.04 0.37 0.67; 0.13 0.56 0.50; 0.74 0.28 0.13; 0.56 0.33 0.72];
markers = {'o','s','^','d'};
shortLabels = {'Peak 2: 6-bit','Peak 2: continuous','Peak 3: 6-bit','Peak 3: continuous'};
for k = 1:numel(variables)
    ax = nexttile(layout);
    hold(ax,'on');
    for c = 1:settings.calibration_count
        rows = sortrows(summary(summary.calibration_id==c,:),'treatment_id');
        y = rows.(variables{k});
        if k==1 || k==3, y=100*y; end
        x = (1:4).'+.05*(c-(settings.calibration_count+1)/2);
        plot(ax,x,y,'-','Color',[.72 .72 .72],'LineWidth',.65,'HandleVisibility','off');
        for arm = 1:4
            face = 'none';
            if rows.paired_power_match(arm), face=colors(arm,:); end
            plot(ax,x(arm),y(arm),'LineStyle','none','Marker',markers{arm}, ...
                'MarkerSize',6,'Color',colors(arm,:),'MarkerFaceColor',face,'LineWidth',1);
        end
    end
    if k==2
        set(ax,'YScale','log');
        yline(ax,1,'--k','BER target','LabelHorizontalAlignment','left');
    elseif k==4
        yline(ax,settings.P_target,'--k','Power target','LabelHorizontalAlignment','left');
    end
    xlim(ax,[.65 4.35]);
    xticks(ax,1:4);
    xticklabels(ax,shortLabels);
    set(ax,'Color','w','XColor','k','YColor','k','FontSize',9,'TickLabelInterpreter','none');
    ylabel(ax,labels{k});
    grid(ax,'on');
    box(ax,'on');
end
drawnow;
pngPath = fullfile(outDir,[stem '.png']);
pdfPath = fullfile(outDir,[stem '.pdf']);
svgPath = fullfile(outDir,[stem '.svg']);
exportgraphics(fig,pngPath,'Resolution',300,'BackgroundColor','white');
exportgraphics(fig,pdfPath,'ContentType','vector','BackgroundColor','white');
print(fig,svgPath,'-dsvg','-painters');
manifest = table(string(stem),string(settings.phase),"written", ...
    string(dmt_v13_hash(summary)),dmt_t2_diag_file_hash(fullfile(outDir,'summary.csv')), ...
    dmt_t2_diag_file_hash(pngPath),dmt_t2_diag_file_hash(pdfPath),dmt_t2_diag_file_hash(svgPath), ...
    'VariableNames',{'figure','phase','status','data_hash','source_csv_sha256', ...
    'png_sha256','pdf_sha256','svg_sha256'});
caption = ['Separating Transmitter Clipping and ADC Quantization. The plot uses independent ' ...
    'paired diagnostic transmissions with a fixed loading table. The two transmitter caps share ' ...
    'AC gain and separately fitted DC offsets. Both receiver modes saturate at the same ADC ' ...
    'input limits. Each calibration pools integer counters from two diagnostic payloads. ' ...
    'Gray lines identify shared random realizations. Open markers indicate incomplete power ' ...
    'matching across the four treatments. The worst-carrier bound uses the maximum of 24 ' ...
    'pointwise Wilson upper endpoints. No main-scan payload enters this figure.'];
end
