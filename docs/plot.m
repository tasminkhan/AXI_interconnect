%% plot_xbar.m
% Four figures from xbar_results_all.xlsx:
%   Fig 1  m0 avg_tot vs load   - the pixel
%   Fig 2  m1 avg_tot vs load   - 1-beat bulk master
%   Fig 3  m2 avg_tot vs load   - 16-beat bulk master   (all case 1: RR/QoS/QoS+DRR)
%   Fig 4  m1:m2 beat ratio vs load                      (case 2: RR/QoS/QoS+DRR)
%
% x-axis = offered load per master = (Load %)/100 in txn/cycle, LOG scale.
% QoS+DRR shown for the 1,6,6 weight only. Dense 90-100 band thinned to 90/97/98/100.
% Figures are forced to a fixed 3:1 (width:height) aspect ratio.
clear; close all; clc;
%% ---- load ----------------------------------------------------------------
file = 'C:\Education\VLSI\AXI\axi_xbar\reports\xbar_results_all.xlsx';
T   = readtable(file, 'VariableNamingRule', 'preserve');
sch = string(T.("Scheme"));
% loads to show: full 1-90 sweep, then only 97/98/100 from the top band
keepLoads = [1 2 3 5 8 10 15 20 30 40 50 60 70 80 90 97 98 100];
%% ---- figure 1: m0 latency (case 1) --------------------------------------
matchC1 = ["RR", "QoS", "DRR(1,6,6)"];    % labels as stored in the sheet
dispC1  = ["RR", "QoS", "QoS+DRR"];       % labels shown in the legend
plotPanel(T, sch, 1, matchC1, dispC1, keepLoads, "AvgTot m0", ...
'm0 (pixel) latency vs load', 'm0 avg total latency (cycles)');
%% ---- figure 2: m1 latency (case 1) --------------------------------------
plotPanel(T, sch, 1, matchC1, dispC1, keepLoads, "AvgTot m1", ...
'm1 (1-beat bulk) latency vs load', 'm1 avg total latency (cycles)');
%% ---- figure 3: m2 latency (case 1) --------------------------------------
plotPanel(T, sch, 1, matchC1, dispC1, keepLoads, "AvgTot m2", ...
'm2 (16-beat bulk) latency vs load', 'm2 avg total latency (cycles)');
%% ---- figure 4: m1:m2 bandwidth ratio (case 2) ---------------------------
schC2disp = ["RR", "QoS", "QoS+DRR"];
schC2match = ["RR", "QoS", "DRR"];
ax = plotPanel(T, sch, 2, schC2match, schC2disp, keepLoads, "Ratio m1/m2", ...
'm1:m2 bandwidth fairness vs load', 'm1:m2 beat ratio');
ylim(ax, [0 1.1]);
% reference lines in BLACK, with movable text labels (draggable) --------
xr = xlim(ax);
plot(ax, xr, [1.0 1.0],       'k--', 'HandleVisibility','off');
plot(ax, xr, [0.0625 0.0625], 'k:',  'HandleVisibility','off');
t1 = text(ax, xr(1)*1.2, 1.0,    ' ideal (1.0)', 'Color','k', ...
    'VerticalAlignment','bottom', 'FontSize',10);
t2 = text(ax, xr(1)*1.2, 0.0625, ' per-request (0.0625)', 'Color','k', ...
    'VerticalAlignment','bottom', 'FontSize',10);
makeDraggable(t1); makeDraggable(t2);
%% ---- optional: save all four as PNG next to the data --------------------
outdir = 'C:\Education\VLSI\AXI\axi_xbar\reports';
names  = {'fig1_m0_latency','fig2_m1_latency','fig3_m2_latency','fig4_ratio'};
figs   = flipud(findobj('Type','figure'));   % oldest (Fig 1) first
for k = 1:numel(figs)
    exportgraphics(figs(k), fullfile(outdir, [names{k} '.png']), 'Resolution', 200);
end
%% ========================================================================
function ax = plotPanel(T, sch, caseNum, matchList, dispList, keepLoads, ...
                        metricName, ttl, ylab)
% One figure: metricName vs (Load%/100) on a log x-axis, one plain line per scheme.
% Figure canvas is forced to 3:1 width:height.
    W = 600; H = 300;                                   % 3:1 aspect
    figure('Color','w', 'Position',[100 100 W H]);
    ax = axes; hold(ax,'on'); box(ax,'on');
    cmap = lines(numel(matchList));
    for i = 1:numel(matchList)
        mask = (T.("Case") == caseNum) & (sch == matchList(i));
        if ~any(mask)
            warning('No rows for "%s" in case %d - skipped.', matchList(i), caseNum);
            continue;
        end
        L = T.("Load %")(mask);
        y = T.(metricName)(mask);
        keep = ismember(L, keepLoads);          % thin the high-load band
        L = L(keep);  y = y(keep);
        [L, idx] = sort(L);  y = y(idx);
        semilogx(ax, L/100, y, '-', 'Color', cmap(i,:), 'LineWidth', 1.5, ...
            'DisplayName', dispList(i));
    end
    set(ax, 'XScale', 'log');
    grid(ax, 'on'); ax.GridAlpha = 0.25;
    xlabel(ax, 'offered bulk transaction load per cycle');
    ylabel(ax, ylab);
    lg = legend(ax, 'Location','best', 'Interpreter','none');
    set(lg, 'AutoUpdate','off');                 % draggable by default; frozen contents
    xlim(ax, [0.008 1.2]);
    % lock the on-screen box to 3:1 so exported PNG keeps the ratio
    set(ax, 'Units','normalized');
end
%% ---- make a text object draggable with the mouse ------------------------
function makeDraggable(h)
    set(h, 'ButtonDownFcn', @(src,~) startDrag(src));
    function startDrag(src)
        fig = ancestor(src,'figure');
        set(fig, 'WindowButtonMotionFcn', @(~,~) moveIt(src), ...
                 'WindowButtonUpFcn',     @(~,~) stopDrag(fig));
    end
    function moveIt(src)
        ax = ancestor(src,'axes');
        cp = ax.CurrentPoint;
        src.Position(1:2) = cp(1,1:2);
    end
    function stopDrag(fig)
        set(fig, 'WindowButtonMotionFcn','', 'WindowButtonUpFcn','');
    end
end