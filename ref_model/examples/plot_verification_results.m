function plot_verification_results(scores_own, scores_alien, method_name, threshold)
% plot_verification_results  Гистограмма разделительной способности верификатора.
%
% Аргументы:
%   scores_own   — вектор scores для своих записей
%   scores_alien — вектор scores для чужих записей
%   method_name  — строка с названием метода (для заголовка)
%   threshold    — (необязательно) порог верификации

    figure('Color', 'w', 'Name', ['Анализ метода: ' method_name]);
    hold on;

    all_scores = [scores_own(:); scores_alien(:)];
    bins = linspace(min(all_scores), max(all_scores), 20);

    histogram(scores_own,   bins, 'FaceColor', [0.2 0.8 0.2], 'FaceAlpha', 0.6, ...
        'DisplayName', 'Свои (Authorized)');
    histogram(scores_alien, bins, 'FaceColor', [0.8 0.2 0.2], 'FaceAlpha', 0.6, ...
        'DisplayName', 'Чужие (Impostors)');

    % Отрисовка порога, если он передан
    if nargin >= 4 && ~isempty(threshold)
        xline(threshold, '--k', 'LineWidth', 2, 'Label', ...
            sprintf('Порог = %.2f', threshold), 'LabelVerticalAlignment', 'bottom');
    end

    grid on;
    xlabel(['Расстояние - ' method_name]);
    ylabel('Количество записей');
    title(['Разделительная способность: ' method_name]);
    legend('show', 'Location', 'northwest');
    hold off;
end
