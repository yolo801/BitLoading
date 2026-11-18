function dmt_vm_graphics_subcarrier(fig,data)
%DMT_VM_GRAPHICS_SUBCARRIER Report the frozen representative calibration.
ref=data.ref;
layout=tiledlayout(fig,3,1,'TileSpacing','compact','Padding','compact');
title(layout,'How Frequency Selectivity Changes Bit Allocation','Color','black');
subtitle(layout,sprintf('Case %d | Commanded swing %.2f | %d-bit ADC | Calibration %d', ...
    ref.case_id,ref.swing,ref.q,ref.calibration_id),'Color','black');
probe=nexttile(layout);
bits=nexttile(layout);
ber=nexttile(layout);
hold(probe,'on');hold(bits,'on');hold(ber,'on');
strategy={'Uniform validated','Per-tone validated'};
colors=[.12 .39 .67;.83 .31 .11];
lines={'-','--'};
f=data.frequency_GHz;
q=plot(probe,f,data.snr.SNR_dB,'-','Color',[.14 .20 .28],'LineWidth',1.27);
q.DisplayName='Shared B0 probe';
legendStyle(legend(probe,'Location','southwest'));
ylabel(probe,'Effective SNR (dB)');
title(probe,'Shared probe quality','Color','black');

missingProfile=strings(0,1);
missingBER=strings(0,1);
seenProfile=false;
seenBER=false;
range=data.targetBER;
for j=1:numel(strategy)
    missing=string(strategy{j})+" ("+replace(data.state(j),"_"," ")+")";
    p=data.profile{j};
    if isempty(p)
        missingProfile(end+1,1)=missing; %#ok<AGROW>
    else
        assert(isequal(p.k,data.snr.k) && all(abs(p.frequency_GHz-f)<1e-10) && ...
            all(ismember(p.bits_k,[2 4 6])),'DMT:VMFigureProfile','Invalid saved profile.');
        seenProfile=true;
        stairs(bits,f,p.bits_k,lines{j},'Color',colors(j,:),'LineWidth',1.52, ...
            'DisplayName',strategy{j});
    end
    counted=data.pool{j};
    if isempty(counted)
        missingBER(end+1,1)=missing; %#ok<AGROW>
    else
        assert(isequal(counted.k,data.snr.k) && all(abs(counted.frequency_GHz-f)<1e-10), ...
            'DMT:VMFigureBER','Observed BER must cover the complete active frequency band.');
        seenBER=true;
        measured=counted.error_bits>0;
        if any(measured)
            y=counted.BER(measured);
            lo=counted.CI_low(measured);
            hi=counted.CI_high(measured);
            assert(all(lo>0 & lo<=y & y<=hi));
            errorbar(ber,f(measured),y,y-lo,hi-y,'LineStyle','none','Color',colors(j,:), ...
                'Marker','o','MarkerSize',3.4-.45*j,'CapSize',2,'LineWidth',.72, ...
                'DisplayName',strategy{j});
            range=[range;lo;hi]; %#ok<AGROW>
        end
        zero=~measured;
        if any(zero)
            y=counted.CI_high(zero);
            assert(all(counted.BER(zero)==0 & y>0));
            plot(ber,f(zero),y,'v','Color',colors(j,:), ...
                'MarkerSize',5.15-.8*j,'MarkerFaceColor','white', ...
                'DisplayName',[strategy{j} ' (zero errors)']);
            range=[range;y]; %#ok<AGROW>
        end
    end
end
ylabel(bits,'Bits per subcarrier');yticks(bits,[2 4 6]);ylim(bits,[1.5 6.5]);
title(bits,'Frozen profiles','Color','black');
if seenProfile,legendStyle(legend(bits,'Location','best','NumColumns',2));end
annotate(bits,missingProfile,'No saved profile');
ylabel(ber,'Observed BER');
title(ber,'Formal payload counts pooled within calibration','Color','black');
set(ber,'YScale','log');
ylim(ber,[.7*min(range) 1.62*max(range)]);
yline(ber,data.targetBER,':k',sprintf('BER target %.0e',data.targetBER), ...
    'LabelHorizontalAlignment','left','HandleVisibility','off');
if seenBER,legendStyle(legend(ber,'Location','best','NumColumns',2));end
annotate(ber,missingBER,'No formal payload BER');
for ax=[probe bits ber]
    style(ax);
    xline(ax,data.notch_GHz,'--','Color',[.45 .45 .45],'HandleVisibility','off');
end
notchLabel=sprintf('Source-curve notch %.2f GHz',data.notch_GHz);
subtitle(probe,notchLabel,'Color',[.17 .17 .17],'FontSize',8);
linkaxes([probe bits ber],'x');
spacing=min(diff(f));
xlim(probe,[min(f)-.5*spacing max(f)+.5*spacing]);
xlabel(layout,'Physical frequency (GHz)','Color','black');
end

function annotate(ax,missing,heading)
if ~isempty(missing)
    subtitle(ax,string(heading)+" | "+strjoin(missing," | "), ...
        'Color',[.19 .19 .19],'FontSize',8,'Interpreter','none');
end
end

function style(ax)
set(ax,'Color','white','XColor','black','YColor','black','FontSize',9, ...
    'GridColor',[.84 .84 .84],'LineWidth',.8,'Box','on','Layer','top');
grid(ax,'on');
end

function legendStyle(handle)
set(handle,'Color','white','TextColor','black','FontSize',8,'Interpreter','none');
end
