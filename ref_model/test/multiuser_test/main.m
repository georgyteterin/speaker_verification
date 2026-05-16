clear, clc

% =====================================================================
%  Запускатор мультипользовательского теста голосового верификатора.
%  Запускать из папки test/multiuser_test/ 
%
%  По сетке (nfft x U x n x trials) вызывается run_multiuser_test и
%  собираются метрики FRR / FAR / Accuracy.
%    U — число реф-голосов (зарегистрированных пользователей)
%    n — число реф-записей на каждый голос
% =====================================================================

fprintf("[%s] Начата настройка параллельных вычислений\n", datetime);
% --- Настройка параллельных вычислений ---
desired_workers = 4; % Укажите нужное кол-во ядер (например, 2 или 4)

current_pool = gcp('nocreate'); % Проверяем, запущен ли уже пул
if isempty(current_pool)
    parpool('local', desired_workers);
elseif current_pool.NumWorkers ~= desired_workers
    delete(current_pool); % Если запущен пул с другим кол-вом ядер — пересоздаем
    parpool('local', desired_workers);
end
fprintf("[%s] Завершена настройка параллельных вычислений\n", datetime);

% ---------------------------------------------------------------------
%  Настройки эксперимента
% ---------------------------------------------------------------------
fft_values        = 1024;   % Размеры FFT
ref_voices_values = 1:4;    % U — число реф-голосов
ref_data_values   = 2:4;    % n — число реф-записей на каждый голос
num_trials        = 10;     % Сколько раз пересобираем базу для каждой точки

num_ffts = numel(fft_values);
num_U    = numel(ref_voices_values);
num_n    = numel(ref_data_values);

% 4D-матрицы результатов: [U, n, trial, fft]
tmp_FRR = zeros(num_U, num_n, num_trials, num_ffts);
tmp_FAR = zeros(num_U, num_n, num_trials, num_ffts);
tmp_Acc = zeros(num_U, num_n, num_trials, num_ffts);

for j_fft = 1 : num_ffts
    current_fft = fft_values(j_fft);
    fprintf("\t --- Тестирование для NFFT = %i ---\n", current_fft);

    for j_U = 1 : num_U
        U = ref_voices_values(j_U);

        for j_n = 1 : num_n
            n = ref_data_values(j_n);
            fprintf("[%s] Запуск тестов: U = %i реф-голосов, n = %i реф-записей\n", ...
                    datetime, U, n);

            % Локальные срезы для parfor (нарезаемые переменные)
            slice_FRR = zeros(1, num_trials);
            slice_FAR = zeros(1, num_trials);
            slice_Acc = zeros(1, num_trials);

            parfor j_trial = 1 : num_trials
                % Уникальный сид для каждой точки сетки
                rng(j_fft*1e6 + j_U*1e5 + j_n*1e4 + j_trial, 'twister');

                [f_rate, a_rate, acc] = run_multiuser_test(U, n, current_fft);

                slice_FRR(j_trial) = f_rate;
                slice_FAR(j_trial) = a_rate;
                slice_Acc(j_trial) = acc;
            end

            tmp_FRR(j_U, j_n, :, j_fft) = slice_FRR;
            tmp_FAR(j_U, j_n, :, j_fft) = slice_FAR;
            tmp_Acc(j_U, j_n, :, j_fft) = slice_Acc;
        end
    end
end
fprintf("[%s] Тестирование завершено\n", datetime);

% Сохранение в общую структуру
stats.FFT_Labels = fft_values;
stats.U_Labels   = ref_voices_values;
stats.n_Labels   = ref_data_values;
stats.FRR        = tmp_FRR;
stats.FAR        = tmp_FAR;
stats.Accuracy   = tmp_Acc;

%% Отрисовка: метрики в зависимости от числа реф-голосов U
% Для каждого NFFT — отдельное окно, 3 подграфика (FAR / FRR / Accuracy).
% На каждом подграфике — по линии для каждого значения n.

metrics_names = {'FAR (Ложный доступ)', 'FRR (Ложный отказ)', 'Accuracy (Общая точность)'};
data_to_plot  = {stats.FAR, stats.FRR, stats.Accuracy};
line_styles   = {'-o', '-s', '-^', '-d'};
x_axis        = ref_voices_values;

for j_fft = 1 : num_ffts
    figure('Name', sprintf('Мультипольз. тест: NFFT = %i', fft_values(j_fft)), ...
           'Position', [100 100 1200 400]);

    for m = 1 : 3
        subplot(1, 3, m); hold on; grid on;

        metric_4d   = data_to_plot{m};                  % [U, n, trial, fft]
        % Усреднение по испытаниям (dim = 3)
        metric_mean = mean(metric_4d(:, :, :, j_fft), 3); % -> [U, n]

        for j_n = 1 : num_n
            plot(x_axis, metric_mean(:, j_n), line_styles{mod(j_n-1,4)+1}, ...
                 'LineWidth', 1.5, ...
                 'DisplayName', sprintf('n = %i реф-записей', ref_data_values(j_n)));
        end

        title(metrics_names{m});
        xlabel('Число реф-голосов U');
        ylabel('Процент (%)');
        xticks(x_axis);

        if m < 3
            ylim([0 100]);
        else
            min_val = min(metric_mean(:));
            ylim([max(0, min_val - 5), 100]);
        end

        legend('Location', 'best', 'FontSize', 8);
    end
end

%% (Опционально) Детальная разбивка по верификаторам
% run_multiuser_test возвращает 4-й аргумент details с метриками по
% каждому реф-голосу. Пример одиночного прогона для анализа разброса
% между пользователями:
%
%   rng(42, 'twister');
%   [FRR, FAR, Acc, details] = run_multiuser_test(4, 3, 1024);
%   fprintf('Команда: %s\n', details.task);
%   for v = 1:numel(details.per_verifier)
%       pv = details.per_verifier(v);
%       fprintf('  %s: FRR=%.1f%% FAR=%.1f%% Acc=%.1f%% (auth=%d, imp=%d)\n', ...
%               pv.voice, pv.FRR, pv.FAR, pv.Accuracy, pv.num_auth, pv.num_imp);
%   end
