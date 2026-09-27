%% plot_ppa.m
% Three PPA figures for the paper, read from Comparison_all.xlsx:
%   Fig 1  cost-vs-benefit scatter  (area overhead vs fairness achieved)
%   Fig 2  power grouped bar         (leakage / switching / internal x 3 arms)
%   Fig 3  1x4 PPA row               (cell area, cell count, wire length, CP delay)
%
% Reads absolute + ratio metrics by name, so row order in the sheet can move.
% Requires R2019b+ (bar XEndPoints/YEndPoints, exportgraphics).

clear; close all; clc;

repdir   = 'C:\Education\VLSI\AXI\axi_xbar\reports';
compFile = fullfile(repdir, 'Comparison_all.xlsx');

%% ---- read the comparison sheet -----------------------------------------
raw = readcell(compFile);
lab = string(raw(:,1));
lab(ismissing(lab)) = "";
splitRow = find(lab == "Ratio vs RR", 1);     % divides absolute / ratio sections

arms   = {'RR','QoS','QoS+DRR'};
cRR    = [0.00 0.447 0.741];
cQoS   = [0.850 0.325 0.098];
cDRR   = [0.466 0.674 0.188];
colors = [cRR; cQoS; cDRR];                    % one row per arm, used everywhere

%% =========================================================================
%% FIGURE 1 - cost vs benefit scatter  (the headline figure)
%% =========================================================================
areaOv = pick(raw, lab, splitRow, "Cell area", "ratio");   % [1.00 1.47 1.59]

% these two come from the SIMULATION sweep, not the PPA files - edit if needed
fair  = [0.0625, 0.0625, 1.004];          % m1:m2 fairness ratio at full load
m0lat = [94.98,  67.07,  34.74];          % m0 avg_tot at full load (cycles)

figure('Color','w','Position',[100 100 620 480]); hold on; box on;
yline(1.0,    '--', 'ideal fairness',      'Color',[.5 .5 .5], 'FontSize',10, 'LabelHorizontalAlignment','left');
yline(0.0625, ':',  'per-request baseline','Color',[.5 .5 .5], 'FontSize',10, 'LabelHorizontalAlignment','left');
for i = 1:3
    scatter(areaOv(i), fair(i), 130, colors(i,:), 'filled', ...
        'MarkerEdgeColor','k', 'LineWidth',0.5);
end
% annotate each point: arm name + what its area actually bought
lbl = { sprintf('  RR\n  m0 %.0f cyc',  m0lat(1)), ...
        sprintf('  QoS\n  m0 %.0f cyc', m0lat(2)), ...
        sprintf('  QoS+DRR\n  m0 %.0f cyc', m0lat(3)) };
va  = {'bottom','bottom','top'};      % DRR label below its point to avoid the top edge
dy  = [ 0.03, 0.03, -0.03];
for i = 1:3
    text(areaOv(i)+0.015, fair(i)+dy(i), lbl{i}, 'Color',colors(i,:), ...
        'FontSize',11, 'FontWeight','bold', 'VerticalAlignment',va{i});
end
xlabel('area overhead  (\times RR cell area)');
ylabel('m1:m2 bandwidth fairness at full load');
xlim([0.9 1.75]); ylim([-0.05 1.15]); grid on; ax = gca; ax.GridAlpha = 0.15;

%% =========================================================================
%% FIGURE 2 - power grouped bar (independent image)
%% =========================================================================
P = [ pick(raw, lab, splitRow, "Leakage power",   "abs");
      pick(raw, lab, splitRow, "Switching power", "abs");
      pick(raw, lab, splitRow, "Internal power",  "abs") ];   % rows=category, cols=arm
cats = {'Leakage','Switching','Internal'};

figure('Color','w','Position',[100 100 620 460]); hold on; box on;
b = bar(P, 'grouped', 'BarWidth', 0.85);
for k = 1:3, b(k).FaceColor = colors(k,:); b(k).EdgeColor = 'none'; end
set(gca, 'XTick', 1:3, 'XTickLabel', cats);
ylabel('Power (mW)');
legend(arms, 'Location','northwest'); grid on; ax = gca; ax.GridAlpha = 0.15;
ylim([0 max(P(:))*1.15]);
for k = 1:3                                   % value labels above each bar
    for g = 1:3
        v = b(k).YEndPoints(g);
        text(b(k).XEndPoints(g), v, sprintf(' %.4f', P(g,k)), ...
            'HorizontalAlignment','left', 'VerticalAlignment','middle', ...
            'Rotation',90, 'FontSize',9, 'Color',[.4 .4 .4]);
    end
end
% NOTE: leakage is ~1000x smaller than internal, so it reads as ~0 here.
% For a version where all three categories are visible, uncomment:
% set(gca,'YScale','log'); ylim([1e-4 max(P(:))*2]);

%% =========================================================================
%% FIGURE 3 - 1x4 PPA row (area / cell count / wire length / CP delay)
%% =========================================================================
figure('Color','w','Position',[80 80 1280 320]);
barPanel(1, pick(raw,lab,splitRow,"Cell area","abs"),         'Cell area',     '\mum^2', arms, colors, '%.0f');
barPanel(2, pick(raw,lab,splitRow,"Instance count","abs"),    'Cell count',    'cells',  arms, colors, '%.0f');
barPanel(3, pick(raw,lab,splitRow,"Total wire length","abs"), 'Wire length',   '\mum',   arms, colors, '%.0f');
barPanel(4, pick(raw,lab,splitRow,"Critical-path delay","abs"),'Critical-path delay','ps',arms, colors, '%.0f');

%% ---- save all three ------------------------------------------------------
figs  = flipud(findobj('Type','figure'));
names = {'fig_cost_benefit','fig_power','fig_ppa_row'};
for k = 1:numel(figs)
    exportgraphics(figs(k), fullfile(repdir, [names{k} '.png']), 'Resolution', 600);
end

%% =========================================================================
function v = pick(raw, lab, splitRow, name, section)
% Return [RR QoS DRR] for a metric, choosing the absolute or ratio section.
    idx = find(lab == name);
    if section == "abs", idx = idx(idx < splitRow); else, idx = idx(idx > splitRow); end
    v = cell2mat(raw(idx(1), 2:4));
end

function barPanel(pos, vals, ttl, ylab, arms, colors, fmt)
% One subplot in the 1x4 row: three arm bars, colored, with value labels.
    subplot(1,4,pos); hold on; box on;
    b = bar(1:3, vals, 0.7, 'FaceColor','flat', 'EdgeColor','none');
    b.CData = colors;
    set(gca, 'XTick', 1:3, 'XTickLabel', arms);
    ylabel(ylab); title(ttl); grid on; ax = gca; ax.GridAlpha = 0.15;
    ylim([0 max(vals)*1.18]);
    for i = 1:3
        text(b.XEndPoints(i), b.YEndPoints(i), sprintf(fmt, vals(i)), ...
            'HorizontalAlignment','center', 'VerticalAlignment','bottom', 'FontSize',9);
    end
end