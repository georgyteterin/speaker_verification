clear, clc, close all

actual = load("artifacts\actual.mat");
imposters = load("artifacts\imposters.mat");

plot_verification_results(...
    actual.result.euclidean,...
    imposters.result.euclidean,...
    'Euclidean');

plot_verification_results(...
    actual.result.dtw,...
    imposters.result.dtw,...
    'DTW');

function plot_verification_results(scores_own, scores_alien, method_name)
    figure('Color', 'w', 'Name', ['Анализ метода: ' method_name]);
    hold on;

    % Определяем общие границы для гистограмм
    all_scores = [scores_own(:); scores_alien(:)];
    min_val = min(all_scores);
    max_val = max(all_scores);
    bins = linspace(min_val, max_val, 20); % 20 колонок

    % Гистограмма "Свои" (Зеленая)
    histogram(scores_own, bins, 'FaceColor', [0.2 0.8 0.2], 'FaceAlpha', 0.5, ...
        'DisplayName', 'Свои (Authorized)');

    % Гистограмма "Чужие" (Красная)
    histogram(scores_alien, bins, 'FaceColor', [0.8 0.2 0.2], 'FaceAlpha', 0.5, ...
        'DisplayName', 'Чужие (Impostors)');

    % Оформление
    grid on;
    xlabel(['Расстояние (Distance) - ' method_name]);
    ylabel('Количество тестов');
    title(['Разделительная способность алгоритма: ' method_name]);
    legend('show');

    % Пример поиска "визуального" порога
    if ~isempty(scores_own) && ~isempty(scores_alien)
        threshold = (mean(scores_own) + mean(scores_alien)) / 2;
        xline(threshold, '--r', 'LineWidth', 2, 'Label', 'Возможный порог');
    end
    
    hold off;
end


