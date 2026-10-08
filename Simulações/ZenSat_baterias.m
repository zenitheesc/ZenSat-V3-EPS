% =========================================================================
%  ZenSat V3 — Análise Térmica do Compartimento de Baterias
%  Grupo Zenith EESC USP — Divisão Power Supply
% =========================================================================
%
%  MODELO: Capacitância Concentrada (Lumped Capacitance)
%  Baseado na metodologia do Ribatski Module — USPSat AE1 (2019),
%  seção 2.3.1 do relatório oficial do grupo.
%
%  EQUAÇÃO DE GOVERNO (Euler explícito):
%
%    m·Cp · dT/dt = P_heater + P_interno - (T - T_ext) / R_th
%
%  T_{i+1} = T_i + (dt / m·Cp) · [ P_heater + P_int - (T_i - T_ext)/R_th ]
%
%  Em estado estacionário (dT/dt = 0):
%
%    P_heater_min = (T_alvo - T_ext) / R_th  -  P_interno
%
%  RESISTÊNCIA TÉRMICA (camadas em série):
%
%    R_i = L_i / (k_i × A_superfície)        [°C/W]
%
% =========================================================================
%  CENÁRIOS INCLUÍDOS:
%    1. Sem aquecedor        — detecta se o eclipse é seguro passivamente
%    2. Aquecedor constante  — P_heater dimensionado para estado estacionário
%    3. Termostato on/off    — liga em T_on, desliga em T_on + histerese
%
%  SAÍDAS:
%    - Resumo numérico no console
%    - Figura 1: curvas de temperatura vs. tempo (3 cenários)
%    - Figura 2: análise de sensibilidade (P_heater em função de T_ext)
%    - Arquivo CSV com os dados das curvas (opcional — ver seção EXPORT)
% =========================================================================
%  MATLAB R2016b+   (não requer toolboxes adicionais)
% =========================================================================

clear; clc; close all;

%% ========================================================================
%  SEÇÃO 1 — PARÂMETROS DE ENTRADA
%  Altere os valores aqui para adaptar ao seu design.
% =========================================================================

% ── Geometria interna do compartimento de baterias ──────────────────────
box_L = 75;    % comprimento interno  [mm]
box_W = 50;    % largura interna      [mm]
box_H = 40;    % altura interna       [mm]

% ── Espessuras das camadas de isolamento ─────────────────────────────────
%    (camadas em série: de dentro para fora)
wall_ABS   = 3.0;   % parede da caixa ABS   [mm]
wall_glass = 3.0;   % fibra de vidro (ext.) [mm]
% Se adicionar mais camadas, repita o padrão abaixo e some em R_th.

% ── Condutividades térmicas ───────────────────────────────────────────────
k_ABS   = 0.17;   % ABS                    [W/(m·K)]
k_glass = 0.04;   % fibra de vidro         [W/(m·K)]
% Ref: k_carbono ≈ 0.5–1 W/m·K (placa externa do satélite)

% ── Condições de temperatura ─────────────────────────────────────────────
T_ext    = -10;   % temperatura externa: eclipse (órbita) ou câmara (teste)  [°C]
T_target =   2;   % temperatura mínima ALVO da bateria (margem acima de 0°C) [°C]
T_init   =  20;   % temperatura inicial das baterias no início do eclipse     [°C]

% ── Propriedades das baterias (2S2P — 4 células 18650) ───────────────────
m_bat    = 184e-3;   % massa total das células [kg]   (4 × ~46 g típico)
Cp_bat   = 900;      % capacidade calorífica   [J/(kg·K)]  (Li-ion: 830–1000)

% ── Fontes de calor internas (eletrônica dentro da caixa) ────────────────
P_int = 0.30;   % calor gerado por MCU, sensores etc. dentro da caixa [W]

% ── Parâmetros de simulação ───────────────────────────────────────────────
t_eclipse  = 36;    % duração do eclipse ou ensaio  [min]
dt         = 1;     % passo de tempo (Euler)         [s]

% ── Termostato (Cenário 3) ────────────────────────────────────────────────
T_hyst = 2.0;   % histerese: desliga quando T > T_target + T_hyst  [°C]
%   Liga:    T ≤ T_target
%   Desliga: T ≥ T_target + T_hyst

% ── Opções de exportação ─────────────────────────────────────────────────
export_csv    = true;   % true → grava CSV com as curvas de temperatura
export_fig    = false;  % true → salva figuras como PNG (requer caminho válido)
output_folder = '.';    % pasta de saída (padrão: diretório corrente)

%% ========================================================================
%  SEÇÃO 2 — CÁLCULOS GEOMÉTRICOS E RESISTÊNCIA TÉRMICA
% =========================================================================

% Converter mm → m
L = box_L * 1e-3;
W = box_W * 1e-3;
H = box_H * 1e-3;

% Área superficial total da caixa (6 faces)
A_surf = 2 * (L*W + L*H + W*H);   % [m²]

% Resistências térmicas individuais por camada
R_ABS   = (wall_ABS   * 1e-3) / (k_ABS   * A_surf);   % [°C/W]
R_glass = (wall_glass * 1e-3) / (k_glass * A_surf);   % [°C/W]

% Resistência total (série)
R_th = R_ABS + R_glass;   % [°C/W]

%% ========================================================================
%  SEÇÃO 3 — DIMENSIONAMENTO DO AQUECEDOR (Estado Estacionário)
% =========================================================================

% Fluxo de calor perdido pelo isolamento em estado estacionário
% quando a bateria está na temperatura mínima alvo
Q_loss = (T_target - T_ext) / R_th;   % [W]

% Potência mínima necessária do aquecedor
% (desconta o calor já gerado internamente pela eletrônica)
P_heater_min = max(0, Q_loss - P_int);   % [W]

%% ========================================================================
%  SEÇÃO 4 — DINÂMICA TÉRMICA
% =========================================================================

% Capacitância térmica total do sistema
C_th = m_bat * Cp_bat;   % [J/°C]

% Constante de tempo do sistema
tau_s   = R_th * C_th;   % [s]
tau_min = tau_s / 60;    % [min]

% Temperatura de equilíbrio sem aquecedor
%   (definida por: P_int = (T_eq - T_ext) / R_th)
T_eq_no_heater = T_ext + P_int * R_th;   % [°C]

% Temperatura de equilíbrio com aquecedor dimensionado
T_eq_heater = T_ext + (P_heater_min + P_int) * R_th;   % [°C] ≈ T_target

% Tempo para atingir T_target sem aquecedor (solução analítica)
if (T_init > T_target) && (T_eq_no_heater < T_target)
    t_to_target_min = -tau_min * log( ...
        (T_target - T_eq_no_heater) / (T_init - T_eq_no_heater) );
else
    t_to_target_min = Inf;   % nunca atinge T_target (ou já está abaixo)
end

%% ========================================================================
%  SEÇÃO 5 — SIMULAÇÃO NUMÉRICA (Euler explícito)
% =========================================================================

t_total_s = t_eclipse * 60;
t_vec     = (0:dt:t_total_s)';   % vetor de tempo [s]
N         = length(t_vec);

% Pré-alocar vetores
T_no_heater   = zeros(N, 1);
T_with_heater = zeros(N, 1);
T_thermostat  = zeros(N, 1);
P_thermostat  = zeros(N, 1);   % histórico do controle on/off

% Condições iniciais
T_no_heater(1)   = T_init;
T_with_heater(1) = T_init;
T_thermostat(1)  = T_init;
heater_on        = false;

for i = 1:N-1

    % — Cenário 1: Sem aquecedor ─────────────────────────────────────────
    dT = dt / C_th * (P_int - (T_no_heater(i) - T_ext) / R_th);
    T_no_heater(i+1) = T_no_heater(i) + dT;

    % — Cenário 2: Aquecedor a P_heater_min constante ────────────────────
    dT = dt / C_th * (P_heater_min + P_int - (T_with_heater(i) - T_ext) / R_th);
    T_with_heater(i+1) = T_with_heater(i) + dT;

    % — Cenário 3: Termostato on/off ─────────────────────────────────────
    if T_thermostat(i) <= T_target
        heater_on = true;
    elseif T_thermostat(i) >= T_target + T_hyst
        heater_on = false;
    end
    P_now = heater_on * P_heater_min;
    P_thermostat(i) = P_now;
    dT = dt / C_th * (P_now + P_int - (T_thermostat(i) - T_ext) / R_th);
    T_thermostat(i+1) = T_thermostat(i) + dT;

end
P_thermostat(end) = heater_on * P_heater_min;

t_min_vec = t_vec / 60;   % eixo de tempo em minutos

%% ========================================================================
%  SEÇÃO 6 — ANÁLISE DE SENSIBILIDADE: P_heater vs T_ext
% =========================================================================

T_ext_range    = (-50:1:10)';           % faixa de temperaturas externas [°C]
P_heater_range = max(0, (T_target - T_ext_range) / R_th - P_int);   % [W]

%% ========================================================================
%  SEÇÃO 7 — RESUMO NO CONSOLE
% =========================================================================

div = repmat('─', 1, 54);
fprintf('\n%s\n', div);
fprintf('  ZenSat V3 — Análise Térmica das Baterias\n');
fprintf('%s\n', div);

fprintf('\n  ▸ GEOMETRIA DO COMPARTIMENTO\n');
fprintf('    Dimensões internas : %d × %d × %d mm\n', box_L, box_W, box_H);
fprintf('    Área superficial   : %.1f cm²  (%.4f m²)\n', A_surf*1e4, A_surf);

fprintf('\n  ▸ RESISTÊNCIA TÉRMICA\n');
fprintf('    R_ABS              : %.3f °C/W  (%g mm, k=%.2f W/m·K)\n', R_ABS, wall_ABS, k_ABS);
fprintf('    R_fibra de vidro   : %.3f °C/W  (%g mm, k=%.2f W/m·K)\n', R_glass, wall_glass, k_glass);
fprintf('    R_total            : %.3f °C/W\n', R_th);

fprintf('\n  ▸ DIMENSIONAMENTO DO AQUECEDOR (estado estacionário)\n');
fprintf('    Condições: T_bat = %d°C, T_ext = %d°C\n', T_target, T_ext);
fprintf('    Q_loss             : %.3f W  (fluxo pelo isolamento)\n', Q_loss);
fprintf('    P_interno          : %.3f W  (desconto da eletrônica)\n', P_int);
fprintf('    P_heater_min       : %.3f W  ← DIMENSIONAR O AQUECEDOR\n', P_heater_min);

fprintf('\n  ▸ DINÂMICA TÉRMICA\n');
fprintf('    Massa baterias     : %.0f g\n', m_bat*1000);
fprintf('    C_th = m·Cp        : %.1f J/°C\n', C_th);
fprintf('    τ = R_th · C_th    : %.1f s  (%.2f min)\n', tau_s, tau_min);
fprintf('    T_equil. s/aquec.  : %.2f °C\n', T_eq_no_heater);

fprintf('\n  ▸ VERIFICAÇÃO DE SEGURANÇA\n');
if isfinite(t_to_target_min)
    fprintf('    Sem aquecedor: T_alvo (%d°C) atingida em %.1f min\n', T_target, t_to_target_min);
    if t_to_target_min < t_eclipse
        fprintf('    *** FALHA: eclipse dura %d min — AQUECEDOR NECESSÁRIO ***\n', t_eclipse);
    else
        fprintf('    Eclipse de %d min termina antes — passivamente seguro.\n', t_eclipse);
    end
else
    fprintf('    T_alvo nunca atingida sem aquecedor (T_eq = %.1f°C)\n', T_eq_no_heater);
    if T_eq_no_heater >= T_target
        fprintf('    Isolamento passivo suficiente para este cenário.\n');
    end
end

T_min_nh = min(T_no_heater);
T_min_wh = min(T_with_heater);
T_min_ts = min(T_thermostat);
fprintf('\n    T_min sem aquecedor   : %+.2f °C  %s\n', T_min_nh, status_str(T_min_nh >= 0));
fprintf('    T_min c/ aquecedor    : %+.2f °C  %s\n', T_min_wh, status_str(T_min_wh >= T_target));
fprintf('    T_min c/ termostato   : %+.2f °C  %s\n', T_min_ts, status_str(T_min_ts >= T_target));

fprintf('\n%s\n\n', div);

%% ========================================================================
%  SEÇÃO 8 — FIGURA 1: Curvas de temperatura
% =========================================================================

fig1 = figure('Name', 'ZenSat V3 — Transiente Térmico', ...
              'NumberTitle', 'off', ...
              'Color', [1 1 1], ...
              'Position', [80 80 1050 520]);

% ── Subplot 1: Temperatura vs. tempo ─────────────────────────────────────
ax1 = subplot(1, 2, 1);
hold on; box on;

% Zona de perigo (T < 0°C)
y_min_plot = min(-6, T_ext - 3);
fill([0, t_eclipse, t_eclipse, 0], [y_min_plot, y_min_plot, 0, 0], ...
     [1.0 0.90 0.90], 'EdgeColor', 'none', 'FaceAlpha', 0.5);
text(t_eclipse * 0.03, -1.5, 'Zona de perigo (T < 0°C)', ...
     'FontSize', 8, 'Color', [0.75 0.2 0.2], 'FontAngle', 'italic');

% Curvas
h1 = plot(t_min_vec, T_no_heater,   'r--',  'LineWidth', 2.0);
h2 = plot(t_min_vec, T_with_heater, 'b-',   'LineWidth', 2.5);
h3 = plot(t_min_vec, T_thermostat,  '-',    'LineWidth', 1.8, 'Color', [0.08 0.52 0.20]);

% Linhas de referência
plot([0, t_eclipse], [0, 0],        'r:',  'LineWidth', 1.2);
plot([0, t_eclipse], [T_target, T_target], 'b:',  'LineWidth', 1.0);
plot([0, t_eclipse], [T_init, T_init],     'k:',  'LineWidth', 0.8, 'Color', [0.6 0.6 0.6]);

% Anotações das linhas de referência
text(t_eclipse + 0.3, 0,        '0°C',       'FontSize', 8, 'Color', [0.80 0.10 0.10]);
text(t_eclipse + 0.3, T_target, sprintf('%d°C (alvo)', T_target), 'FontSize', 8, 'Color', [0.10 0.35 0.80]);

% Marcador: tempo crítico sem aquecedor
if isfinite(t_to_target_min) && t_to_target_min < t_eclipse
    plot(t_to_target_min, T_target, 'rv', 'MarkerSize', 9, 'MarkerFaceColor', 'r');
    text(t_to_target_min, T_target - 2.5, ...
         sprintf('t_{crit} = %.1f min', t_to_target_min), ...
         'FontSize', 8.5, 'Color', [0.8 0.1 0.1], ...
         'HorizontalAlignment', 'center');
end

xlabel('Tempo (min)', 'FontSize', 11);
ylabel('Temperatura (°C)', 'FontSize', 11);
title('Transiente térmico durante o eclipse', 'FontSize', 11, 'FontWeight', 'bold');
legend([h1 h2 h3], {'Sem aquecedor', ...
                     sprintf('Aquecedor fixo (%.2f W)', P_heater_min), ...
                     sprintf('Termostato on/off (±%.0f°C)', T_hyst/2)}, ...
       'Location', 'southwest', 'FontSize', 9.5);
xlim([0 t_eclipse]);
ylim([y_min_plot, max(T_init + 5, 30)]);
grid on; grid minor;
set(ax1, 'FontSize', 10);
hold off;

% ── Subplot 2: Tabela de parâmetros e resultados ──────────────────────────
ax2 = subplot(1, 2, 2);
axis off;

rows = {
    'GEOMETRIA',             '';
    '  L × W × H',          sprintf('%d × %d × %d mm', box_L, box_W, box_H);
    '  Área superficial',    sprintf('%.1f cm²', A_surf * 1e4);
    '',                      '';
    'ISOLAMENTO',            '';
    '  R_{ABS}',               sprintf('%.3f °C/W', R_ABS);
    '  R_{fibra de vidro}',    sprintf('%.3f °C/W', R_glass);
    '  R_{total}',             sprintf('%.3f °C/W', R_th);
    '',                      '';
    'AQUECEDOR (est. est.)',  '';
    '  Q_{loss}',              sprintf('%.3f W', Q_loss);
    '  P_{interno}',           sprintf('%.3f W', P_int);
    '  ► P_{heater min}',      sprintf('%.3f W', P_heater_min);
    '',                      '';
    'DINÂMICA',              '';
    '  C_{th} = m·Cp',         sprintf('%.1f J/°C', C_th);
    '  τ (constante tempo)', sprintf('%.1f s  /  %.2f min', tau_s, tau_min);
    '  T_{equil. s/ aquec.}',  sprintf('%.2f °C', T_eq_no_heater);
    '',                      '';
    'CONDIÇÕES',             '';
    '  T_{ext}',               sprintf('%d °C', T_ext);
    '  T_{alvo}',              sprintf('%d °C', T_target);
    '  T_{inicial}',           sprintf('%d °C', T_init);
    '  Duração eclipse',     sprintf('%d min', t_eclipse);
};

y_pos = 1;
dy    = 0.046;

for k = 1:size(rows, 1)
    lbl = rows{k, 1};
    val = rows{k, 2};
    if isempty(lbl); continue; end

    is_header  = strcmp(lbl, strtrim(lbl)) && isempty(val);
    is_result  = startsWith(lbl, '  ►');

    if is_header
        text(0.02, y_pos - k*dy, lbl, 'Units', 'normalized', ...
             'FontSize', 9, 'FontWeight', 'bold', 'Color', [0.2 0.2 0.2]);
    elseif is_result
        text(0.04, y_pos - k*dy, lbl, 'Units', 'normalized', ...
             'FontSize', 10, 'FontWeight', 'bold', 'Color', [0.05 0.30 0.72]);
        text(0.98, y_pos - k*dy, val, 'Units', 'normalized', ...
             'FontSize', 10, 'FontWeight', 'bold', 'Color', [0.05 0.30 0.72], ...
             'HorizontalAlignment', 'right');
        % Retângulo de destaque
        
    else
        text(0.04, y_pos - k*dy, lbl, 'Units', 'normalized', ...
             'FontSize', 9, 'Color', [0.35 0.35 0.35]);
        text(0.98, y_pos - k*dy, val, 'Units', 'normalized', ...
             'FontSize', 9, 'Color', [0.15 0.15 0.15], ...
             'HorizontalAlignment', 'right');
    end
end

title(ax2, 'Parâmetros e resultados', 'FontSize', 11, 'FontWeight', 'bold');

sgtitle(sprintf('ZenSat V3 Power Supply — Análise Térmica (T_{ext} = %d°C, eclipse = %d min)', ...
        T_ext, t_eclipse), 'FontSize', 12, 'FontWeight', 'bold');

%% ========================================================================
%  SEÇÃO 9 — FIGURA 2: Análise de Sensibilidade
% =========================================================================

fig2 = figure('Name', 'ZenSat V3 — Sensibilidade: P_heater vs T_ext', ...
              'NumberTitle', 'off', ...
              'Color', [1 1 1], ...
              'Position', [140 130 780 430]);

% ── Subplot 1: P_heater em função de T_ext ───────────────────────────────
ax3 = subplot(1, 2, 1);
hold on; box on;

area(T_ext_range, P_heater_range, 'FaceColor', [0.78 0.87 0.97], 'EdgeColor', 'none');
plot(T_ext_range, P_heater_range, 'b-', 'LineWidth', 2.5);

% Ponto de operação atual
plot(T_ext, P_heater_min, 'ro', 'MarkerSize', 9, 'MarkerFaceColor', 'r');
text(T_ext - 1, P_heater_min + 0.05 * max(P_heater_range), ...
     sprintf('  T_{ext}=%d°C\n  P=%.2fW', T_ext, P_heater_min), ...
     'FontSize', 8.5, 'Color', [0.8 0.1 0.1], 'HorizontalAlignment', 'left');

% Linha P = 0 (isolamento passivo suficiente)
plot(xlim, [0 0], 'k--', 'LineWidth', 0.8);
text(max(T_ext_range) - 1, 0.05 * max(P_heater_range), ...
     'P = 0 (passivo suficiente)', 'FontSize', 8, 'Color', [0.4 0.4 0.4], ...
     'HorizontalAlignment', 'right');

xlabel('T externo (°C)', 'FontSize', 11);
ylabel('P_{heater} mínima (W)', 'FontSize', 11);
title('P_{heater} necessária vs. T_{ext}', 'FontSize', 11, 'FontWeight', 'bold');
grid on;
xlim([min(T_ext_range) max(T_ext_range)]);
ylim([-0.1, max(P_heater_range) * 1.1]);
set(ax3, 'FontSize', 10);
hold off;

% ── Subplot 2: T_min sem aquecedor vs. T_ext ─────────────────────────────
ax4 = subplot(1, 2, 2);
hold on; box on;

T_min_curve = zeros(size(T_ext_range));
for j = 1:length(T_ext_range)
    Te = T_ext_range(j);
    T_eq_j = Te + P_int * R_th;
    % Temperatura mínima atingida ao fim do eclipse sem aquecedor
    T_min_curve(j) = T_eq_j + (T_init - T_eq_j) * exp(-(t_eclipse) / tau_min);
end

% Zona de perigo
fill([min(T_ext_range), max(T_ext_range), max(T_ext_range), min(T_ext_range)], ...
     [-30, -30, 0, 0], [1.0 0.90 0.90], 'EdgeColor', 'none', 'FaceAlpha', 0.5);

plot(T_ext_range, T_min_curve, 'r-', 'LineWidth', 2.5);
plot([min(T_ext_range), max(T_ext_range)], [0, 0], 'r:', 'LineWidth', 1.5);

% Ponto de operação atual
T_min_atual = T_eq_no_heater + (T_init - T_eq_no_heater) * exp(-(t_eclipse) / tau_min);
plot(T_ext, T_min_atual, 'ro', 'MarkerSize', 9, 'MarkerFaceColor', 'r');
text(T_ext - 1, T_min_atual + 0.5, ...
     sprintf('  T_{ext}=%d°C\n  T_{min}=%.1f°C', T_ext, T_min_atual), ...
     'FontSize', 8.5, 'Color', [0.8 0.1 0.1]);

xlabel('T externo (°C)', 'FontSize', 11);
ylabel('T_{min} bateria sem aquecedor (°C)', 'FontSize', 11);
title('T_{min} da bateria no fim do eclipse', 'FontSize', 11, 'FontWeight', 'bold');
grid on;
xlim([min(T_ext_range) max(T_ext_range)]);
ylim([min(T_min_curve) - 3, T_init + 2]);
set(ax4, 'FontSize', 10);
hold off;

sgtitle('Análise de Sensibilidade — T_{alvo} = 2°C, isolamento fixo', ...
        'FontSize', 12, 'FontWeight', 'bold');

%% ========================================================================
%  SEÇÃO 10 — EXPORTAÇÃO DE DADOS
% =========================================================================

if export_csv
    csv_file = fullfile(output_folder, 'ZenSat_V3_ThermalAnalysis_curves.csv');

    % Cabeçalho e dados
    header = {'tempo_min', 'T_sem_aquecedor_C', 'T_aquecedor_fixo_C', 'T_termostato_C', 'P_termostato_W'};
    data   = [t_min_vec, T_no_heater, T_with_heater, T_thermostat, P_thermostat];

    % Gravar arquivo
    fid = fopen(csv_file, 'w');
    fprintf(fid, '%s,%s,%s,%s,%s\n', header{:});
    fprintf(fid, '%.2f,%.4f,%.4f,%.4f,%.4f\n', data');
    fclose(fid);

    fprintf('  CSV exportado: %s\n', csv_file);
end

if export_fig
    exportgraphics(fig1, fullfile(output_folder, 'ZenSat_V3_Thermal_Transiente.png'), 'Resolution', 200);
    exportgraphics(fig2, fullfile(output_folder, 'ZenSat_V3_Thermal_Sensibilidade.png'), 'Resolution', 200);
    fprintf('  Figuras salvas em: %s\n', output_folder);
end

%% ========================================================================
%  FUNÇÕES LOCAIS
% =========================================================================

function s = status_str(ok)
%STATUS_STR  Retorna string de status para o console.
    if ok
        s = '[OK]';
    else
        s = '[FALHA]';
    end
end