function files=dmt_vm_three_order_figure(folder,evidence)
%DMT_VM_THREE_ORDER_FIGURE Plot one freeze-verified, three-order formal profile.
assert(isscalar(evidence) && isstruct(evidence),'DMT:ThreeOrderFigureInput', ...
    'A scalar audited figure evidence structure is required.');
f=column(evidence,'frequency_GHz');
snr=column(evidence,'snr_dB');
order=column(evidence,'order');
errors=column(evidence,'errors');
bits=column(evidence,'bits');
lower=column(evidence,'ci_low');
upper=column(evidence,'ci_high');
assert(all([numel(snr) numel(order) numel(errors) numel(bits) numel(lower) numel(upper)]==numel(f)), ...
    'DMT:ThreeOrderFigureSize','SNR, modulation and BER evidence must cover the same ordered carriers.');
target=scalar(evidence,'target_ber');
bandEnd=scalar(evidence,'band_end_GHz');
notch=scalar(evidence,'notch_GHz');
sourceNotch=scalar(evidence,'source_notch_GHz');
swing=scalar(evidence,'swing');
assert(target>0 && target<1 && swing>0 && f(1)>0 && all(diff(f)>0) && ...
    f(end)<=bandEnd+1e-10 && all([notch sourceNotch]>=f(1) & [notch sourceNotch]<=f(end)), ...
    'DMT:ThreeOrderFigureAxes','Invalid BER target, swing or active frequency band.');
counts=arrayfun(@(M)sum(order==M),[4 16 64]);
assert(all(counts>=5) && sum(counts)==numel(order),'DMT:ThreeOrderFigureAllocation', ...
    'The frozen profile requires at least five active tones at each of QPSK, 16-QAM and 64-QAM.');
assert(all(errors==fix(errors) & bits==fix(bits) & bits>0 & errors>=0 & errors<=bits), ...
    'DMT:ThreeOrderFigureCounts','The plotted BER must use integer formal payload counts.');
bitsPerSymbol=log2(order);
symbols=bits./bitsPerSymbol;
assert(all(symbols==symbols(1) & symbols==fix(symbols)), ...
    'DMT:ThreeOrderFigureCounts','Per-tone bit denominators must agree on payload symbol count.');
ber=errors./bits;
[checkLower,checkUpper]=wilson(ber,bits);
assert(all(abs(lower-checkLower)<2e-12 & abs(upper-checkUpper)<2e-12) && ...
    all(lower>=0 & upper<=1 & lower<=ber+2*eps & ber<=upper+2*eps), ...
    'DMT:ThreeOrderFigureWilson','Saved plotted bounds must match the pointwise 95%% Wilson calculation.');
assert(all(checkUpper<target & upper<target & upper>0),'DMT:ThreeOrderFigureBERGate', ...
    'Every carrier must satisfy the strict formal BER upper-bound criterion.');
candidate=string(evidence.candidate_id);
profileHash=string(evidence.profile_hash);
assert(isscalar(candidate) && ~ismissing(candidate) && strlength(candidate)>0 && ...
    isscalar(profileHash) && ~ismissing(profileHash) && ...
    ~isempty(regexp(char(profileHash),'^[a-fA-F0-9]{64}$','once')), ...
    'DMT:ThreeOrderFigureIdentity','A candidate ID and frozen profile SHA-256 are required.');
candidate=char(candidate);
profileHash=char(profileHash);

if ~isfolder(folder),mkdir(folder);end
stem='Figure_1_three_order_DMT';
files=struct('png',fullfile(folder,[stem '.png']),'pdf',fullfile(folder,[stem '.pdf']), ...
    'caption',fullfile(folder,[stem '_caption_en.txt']));
fig=figure('Visible','off','Color','white','Units','inches','Position',[1 1 8.5 7.1], ...
    'InvertHardcopy','off','PaperPositionMode','auto');
cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
layout=tiledlayout(fig,3,1,'TileSpacing','compact','Padding','compact');
title(layout,'Three-order DMT on the VCSEL–MMF Case 2 model','Color','black');
subtitle(layout,sprintf('Commanded modulation swing %.3g | Profile %s',swing,profileHash(1:12)), ...
    'Color','black','Interpreter','none');
snrAx=nexttile(layout);hold(snrAx,'on');
allocationAx=nexttile(layout);hold(allocationAx,'on');
berAx=nexttile(layout);hold(berAx,'on');

curve=[.12 .39 .68];
plot(snrAx,f,snr,'-','Color',curve,'LineWidth',1.42);
title(snrAx,sprintf('(a) Independent B0 probe SNR | Case 2 FIR notch near %.2f GHz',notch), ...
    'Color','black');
ylabel(snrAx,'SNR (dB)');
stairs(allocationAx,f,bitsPerSymbol,'-','Color',curve,'LineWidth',1.4);
title(allocationAx,'(b) Frozen bit allocation','Color','black');
ylabel(allocationAx,'Bits per subcarrier');
yticks(allocationAx,[2 4 6]);
yticklabels(allocationAx,{'2 / QPSK','4 / 16-QAM','6 / 64-QAM'});
ylim(allocationAx,[1.5 6.5]);

title(berAx,'(c) Observed BER from the independent formal payload','Color','black');
ylabel(berAx,'Observed BER');
set(berAx,'YScale','log');
positive=errors>0;
if any(positive)
    assert(all(lower(positive)>0),'DMT:ThreeOrderFigureLog','Positive observed BER needs a positive lower bound.');
    errorbar(berAx,f(positive),ber(positive),max(0,ber(positive)-lower(positive)), ...
        max(0,upper(positive)-ber(positive)),'LineStyle','none','Color',curve,'Marker','o', ...
        'MarkerSize',3,'CapSize',2,'LineWidth',.76,'DisplayName','Observed BER and 95% Wilson interval');
end
zero=~positive;
if any(zero)
    plot(berAx,f(zero),upper(zero),'v','Color',[.76 .27 .12],'MarkerFaceColor','white', ...
        'MarkerSize',4.1,'DisplayName','Zero errors (Wilson upper bound)');
end
yline(berAx,target,'--',sprintf('Target BER %.0e',target),'Color',[.20 .20 .20], ...
    'LabelHorizontalAlignment','left','HandleVisibility','off');
lowest=min([lower(positive);upper(zero)]);
ylim(berAx,[.69*lowest 1.9*target]);
legend(berAx,'Location','best','NumColumns',2,'Color','white','TextColor','black','FontSize',8);

panels=[snrAx allocationAx berAx];
for ax=panels
    set(ax,'Color','white','XColor','black','YColor','black','FontSize',9,'Box','on', ...
        'GridColor',[.84 .84 .84],'LineWidth',.75,'Layer','top');
    grid(ax,'on');
    xline(ax,notch,':','Color',[.4 .4 .4],'LineWidth',1.1,'HandleVisibility','off');
end
linkaxes(panels,'x');
margin=.5*min(diff(f));
xlim(snrAx,[0 bandEnd+margin]);
ticks=0:10:bandEnd;
if isempty(ticks) || ticks(end)<bandEnd,ticks=[ticks bandEnd];end
for ax=panels,xticks(ax,ticks);end
xlabel(layout,'Physical subcarrier frequency (GHz)','Color','black');
exportgraphics(fig,files.png,'Resolution',300,'BackgroundColor','white');
exportgraphics(fig,files.pdf,'ContentType','vector','BackgroundColor','white');
writeCaption(files.caption,candidate,profileHash,counts,evidence,bandEnd,notch,swing,target);
end

function values=column(evidence,name)
assert(isfield(evidence,name),'DMT:ThreeOrderFigureInput','Missing figure input %s.',name);
v=evidence.(name);
assert(isnumeric(v) && isreal(v) && isvector(v) && ~isempty(v) && all(isfinite(v(:))), ...
    'DMT:ThreeOrderFigureInput','Figure input %s must be a finite real vector.',name);
values=double(v(:));
end

function value=scalar(evidence,name)
assert(isfield(evidence,name),'DMT:ThreeOrderFigureInput','Missing figure input %s.',name);
value=evidence.(name);
assert(isnumeric(value) && isscalar(value) && isreal(value) && isfinite(value), ...
    'DMT:ThreeOrderFigureInput','Figure input %s must be a finite real scalar.',name);
value=double(value);
end

function [lower,upper]=wilson(p,n)
z=1.96;
d=1+z^2./n;
center=(p+z^2./(2*n))./d;
radius=z*sqrt(p.*(1-p)./n+z^2./(4*n.^2))./d;
lower=max(0,center-radius);
upper=min(1,center+radius);
end

function writeCaption(path,candidate,profileHash,counts,evidence,bandEnd,notch,swing,target)
fid=fopen(path,'wt','n','UTF-8');
assert(fid>=0,'DMT:ThreeOrderFigureCaption','Cannot write English figure caption.');
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,['Figure 1. Estimated subcarrier SNR, frozen bit allocation, and observed payload BER ' ...
    'for candidate %s in the normalized 50 m VCSEL–MMF Case 2 model at a commanded modulation ' ...
    'swing of %.3g. The active frequency band spans %.3g–%.3g GHz. The vertical dotted line ' ...
    'marks the simulated FIR notch at %.2f GHz. The digitized source-curve notch is near %.2f GHz ' ...
    '(A. M. Rosa Brusin et al., ' ...
    'SPPCom 2025, doi:10.1364/SPPCOM.2025.SpTh3E.4). The frozen profile allocates QPSK, 16-QAM ' ...
    'and 64-QAM to %d, %d and %d active tones, respectively. Panel (c) pools raw integer counts ' ...
    'from two independently seeded formal payload slots transmitted after validation and profile freeze ' ...
    'at this single work point. Positive observations carry approximate pointwise 95%% Wilson intervals. ' ...
    'Downward triangles indicate Wilson upper bounds for tones with zero observed errors. ' ...
    'All pointwise upper bounds are below the %.0e target. Frozen profile SHA-256: %s.\n'], ...
    candidate,swing,evidence.frequency_GHz(1),bandEnd,notch,evidence.source_notch_GHz, ...
    counts(1),counts(2),counts(3),target,profileHash);
end
