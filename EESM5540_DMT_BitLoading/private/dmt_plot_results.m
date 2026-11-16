function dmt_plot_results(cfg, calibration, profiles, perCarrier, outDir, mode)
%DMT_PLOT_RESULTS Plot measured pooled results; analytical curves are diagnostics.
% Zero-error BER has no positive point estimate on a logarithmic axis. Its
% Wilson upper limit is shown with a downward triangle instead of a fake BER.
fig = figure('Visible', 'off', 'Color', 'w', 'Units', 'inches', ...
    'Position', [1 1 6.8 7.4], 'Name', 'Simplified DMT bit loading');
closeFigure = onCleanup(@() close(fig));
layout = tiledlayout(fig, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
freq = cfg.k(:) * cfg.Fs / cfg.NFFT / 1e6;
colors = [0 0.28 0.55; 0.70 0.23 0.03];
markers = {'o', 's'};
styles = {'-', '--'};

ax = nexttile(layout);
plot(ax, freq, calibration.gamma_hat_dB(:), '-o', 'MarkerSize', 3.2, ...
    'LineWidth', 1.1, 'Color', colors(1, :), 'DisplayName', 'Probe-B estimate');
hold(ax, 'on');
plot(ax, freq, calibration.gamma_true_dB(:), '--', 'LineWidth', 1.1, ...
    'Color', [0.25 0.25 0.25], 'DisplayName', 'FIR analytical diagnostic');
ylabel(ax, 'Electrical symbol SNR (dB)');
title(ax, '(a) Independent-probe quality estimate, E_s/N_0 convention');
legend(ax, 'Location', 'southwest', 'FontSize', 8);
xlim(ax, [0.5 24.5]); grid(ax, 'on');

ax = nexttile(layout); hold(ax, 'on');
for s = 1:numel(profiles)
    plot(ax, freq, profiles(s).bits_per_symbol(:), ...
        'LineStyle', styles{s}, 'Marker', markers{s}, 'MarkerSize', 3.8, ...
        'LineWidth', 1.1, 'Color', colors(s, :), 'DisplayName', profiles(s).name);
end
ylabel(ax, 'Bits / subcarrier symbol');
title(ax, '(b) Bit loading only; every active subcarrier has mean E_s = 1');
yticks(ax, [2 4 6]); ylim(ax, [1.5 6.5]); xlim(ax, [0.5 24.5]);
grid(ax, 'on'); legend(ax, 'Location', 'southwest', 'FontSize', 8);

ax = nexttile(layout); hold(ax, 'on');
positiveLimits = cfg.targetBER;
for s = 1:numel(profiles)
    rows = perCarrier.scheme == string(profiles(s).name) & perCarrier.seed == "pooled";
    data = sortrows(perCarrier(rows, :), 'k');
    assert(height(data) == numel(cfg.k), 'DMT:MissingPooledRows', ...
        'Each scheme must have exactly one pooled row per active subcarrier.');
    observed = data.error_bits > 0;
    if any(observed)
        errorbar(ax, data.frequency_Hz(observed)/1e6, data.BER(observed), ...
            data.BER(observed)-data.CI_low(observed), ...
            data.CI_high(observed)-data.BER(observed), ...
            'LineStyle', 'none', 'Marker', markers{s}, 'MarkerSize', 4, ...
            'LineWidth', 1, 'Color', colors(s, :), 'CapSize', 3, ...
            'HandleVisibility', 'off');
        positiveLimits = [positiveLimits; data.CI_low(observed)]; %#ok<AGROW>
    end
    if any(~observed)
        if s == 1
            zeroFace = 'none';
        else
            zeroFace = colors(s, :);
        end
        plot(ax, data.frequency_Hz(~observed)/1e6, data.CI_high(~observed), ...
            'LineStyle', 'none', 'Marker', 'v', 'MarkerSize', 4.5, ...
            'Color', colors(s, :), 'MarkerFaceColor', zeroFace, ...
            'DisplayName', [profiles(s).name ' zero errors: 95% upper limit']);
        positiveLimits = [positiveLimits; data.CI_high(~observed)]; %#ok<AGROW>
    end
    % Legend proxies preserve the scheme's marker even when all errors are zero.
    plot(ax, NaN, NaN, 'LineStyle', 'none', 'Marker', markers{s}, ...
        'MarkerSize', 4, 'Color', colors(s, :), ...
        'DisplayName', [profiles(s).name ' (95% pointwise CI)']);
end
yline(ax, cfg.targetBER, ':k', 'Target 10^{-3}', 'LineWidth', 1, ...
    'LabelHorizontalAlignment', 'left', 'HandleVisibility', 'off');
set(ax, 'YScale', 'log');
positiveLimits = positiveLimits(isfinite(positiveLimits) & positiveLimits > 0);
lower = 10^floor(log10(min(positiveLimits)));
upper = max(1e-2, 10^ceil(log10(max(perCarrier.CI_high))));
ylim(ax, [lower/1.5 min(1, upper*1.5)]);
xlim(ax, [0.5 24.5]); grid(ax, 'on');
xlabel(ax, 'Subcarrier frequency (MHz)'); ylabel(ax, 'Uncoded bit error rate');
if strcmpi(mode, 'smoke')
    title(ax, '(c) Smoke run only; excluded from formal BER statistics');
else
    title(ax, '(c) Three-seed pooled measurements; shared frozen calibration');
end
legend(ax, 'Location', 'southwest', 'FontSize', 7.5);
axesList = findall(fig, 'Type', 'axes');
set(axesList, 'FontName', 'Helvetica', 'FontSize', 8.5, 'Box', 'on');
set(fig, 'PaperPositionMode', 'auto', 'Renderer', 'painters');
drawnow;
exportgraphics(fig, fullfile(outDir, 'dmt_comparison.png'), 'Resolution', 300);
exportgraphics(fig, fullfile(outDir, 'dmt_comparison.pdf'), 'ContentType', 'vector');
savefig(fig, fullfile(outDir, 'dmt_comparison.fig'));
end
