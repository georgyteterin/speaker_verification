clear, clc

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
% -----------------------------------------

fprintf("[%s] Заверешна настройка параллельных вычислений\n", datetime);

% Настройки эксперимента

fft_values = 1024; 
num_ffts = numel(fft_values);
min_refs = 2; 
max_refs = 5; % Например, до 5
num_refs = numel(min_refs, max_refs);
num_trials = 10; % Сколько раз пересобираем базу для каждого N

% Заранее готовим плоские матрицы
tmp_FRR = zeros(num_refs, num_trials, num_ffts);
tmp_FAR = zeros(num_refs, num_trials, num_ffts);
tmp_Acc = zeros(num_refs, num_trials, num_ffts);

for j_fft = 1 : num_ffts
    current_fft = fft_values(j_fft);
    fprintf("\t --- Тестирование для NFFT = %i ---\n", current_fft);
    
    for j_num_ref = min_refs : max_refs
        fprintf("[%s] Запуск тестов для %i реф. записей\n", datetime, j_num_ref);
        
        parfor j_trial = 1 : num_trials
            % Уникальный сид (добавляем FFT в формулу, чтобы выборки не дублировались)
            rng(j_fft * 10000 + j_num_ref * 1000 + j_trial, 'twister');
            
            % Передаем размер FFT в тестовую функцию
            % Убедитесь, что run_simple_test принимает этот параметр
            [f_rate, a_rate, acc] = run_simple_test(j_num_ref, current_fft);
            
            % Запись в 3D матрицу
            tmp_FRR(j_num_ref, j_trial, j_fft) = f_rate;
            tmp_FAR(j_num_ref, j_trial, j_fft) = a_rate;
            tmp_Acc(j_num_ref, j_trial, j_fft) = acc;
        end
    end
end
fprintf("[%s] Тестирование завершено\n", datetime);

% Сохранение в общую структуру
stats.FFT_Labels = fft_values;
stats.FRR = tmp_FRR;
stats.FAR = tmp_FAR;
stats.Accuracy = tmp_Acc;


% Перенос в структуру
stats.FRR = tmp_FRR;
stats.FAR = tmp_FAR;
stats.Accuracy = tmp_Acc;

%% Отрисовка

x_axis = min_refs:max_refs;
metrics_names = {'FAR (Ложный доступ)', 'FRR (Ложный отказ)', 'Accuracy (Общая точность)'};
data_to_plot = {stats.FAR, stats.FRR, stats.Accuracy};
line_styles = {'-o', '-s', '-^', '-d'}; 

figure('Name', 'Сравнительный анализ метрик по FFT');

for m = 1:3 
    subplot(1, 3, m); hold on;
    
    current_metric_3d = data_to_plot{m};
    
    for k = 1:numel(stats.FFT_Labels)
        % Усредняем по испытаниям (dim=2)
        y_all_n = mean(current_metric_3d, 2); 
        % Вырезаем нужный диапазон для текущего FFT (dim=3)
        y_plot = y_all_n(min_refs:max_refs, 1, k);
        
        plot(x_axis, y_plot, line_styles{mod(k-1,4)+1}, ...
            'LineWidth', 1.5, ...
            'DisplayName', ['FFT ' num2str(stats.FFT_Labels(k))]);
    end
    
    grid on;
    title(metrics_names{m});
    xlabel('Кол-во референсов (N)');
    ylabel('Процент (%)');
    
    % Настройка лимитов для наглядности
    if m < 3
        ylim([0 100]); 
    else
        % Находим минимальное значение в текущей метрике для масштаба
        min_val = min(current_metric_3d(:));
        ylim([max(0, min_val - 5), 100]);
    end
    
    % Легенда теперь вызывается для каждого подграфика
    legend('Location', 'best', 'FontSize', 8); 
end

%% Отрисовка 2 (все метрики сразу)

x_axis = min_refs:max_refs;
metrics_names = {'FAR (Ложный доступ)', 'FRR (Ложный отказ)', 'Accuracy (Общая точность)'};
colors = [0.85 0.33 0.1;  % Оранжевый для FAR
          0 0.45 0.74;   % Синий для FRR
          0.47 0.67 0.19]; % Зеленый для Accuracy

for k = 1:numel(stats.FFT_Labels)
    % Создаем новое окно для каждого FFT
    figure('Name', ['Анализ метрик для FFT ' num2str(stats.FFT_Labels(k))], 'Position', [100 100 800 500]);
    hold on;
    
    % 1. Извлекаем и усредняем FAR
    m_FAR = mean(stats.FAR(min_refs:max_refs, :, k), 2);
    % 2. Извлекаем и усредняем FRR
    m_FRR = mean(stats.FRR(min_refs:max_refs, :, k), 2);
    % 3. Извлекаем и усредняем Accuracy
    m_Acc = mean(stats.Accuracy(min_refs:max_refs, :, k), 2);
    
    % Отрисовка
    plot(x_axis, m_FAR, '-o', 'Color', colors(1,:), 'LineWidth', 2, 'DisplayName', metrics_names{1});
    plot(x_axis, m_FRR, '-s', 'Color', colors(2,:), 'LineWidth', 2, 'DisplayName', metrics_names{2});
    plot(x_axis, m_Acc, '-d', 'Color', colors(3,:), 'LineWidth', 2.5, 'DisplayName', metrics_names{3});
    
    % Оформление
    grid on;
    title(['Комплексный отчет: FFT = ' num2str(stats.FFT_Labels(k))]);
    xlabel('Количество референсов (N)');
    ylabel('Процент (%)');
    ylim([0 105]); % С запасом для легенды
    legend('Location', 'best');
    
    % Добавим текстовые подсказки над точками Accuracy для наглядности
    for i = 1:numel(x_axis)
        text(x_axis(i), m_Acc(i)+3, [num2str(m_Acc(i), '%.1f') '%'], ...
            'HorizontalAlignment', 'center', 'FontWeight', 'bold', 'Color', colors(3,:));
    end
end

