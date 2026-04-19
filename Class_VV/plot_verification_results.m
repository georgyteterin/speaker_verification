function plot_verification_results(scores_own, scores_alien, method_name)
    figure('Color', 'w', 'Name', ['Анализ метода: ' method_name]);
    hold on;
    all_scores = [scores_own(:); scores_alien(:)];
    bins = linspace(min(all_scores), max(all_scores), 20);
    histogram(scores_own,   bins, 'FaceColor', [0.2 0.8 0.2], 'FaceAlpha', 0.5, 'DisplayName', 'Свои (Authorized)');
    histogram(scores_alien, bins, 'FaceColor', [0.8 0.2 0.2], 'FaceAlpha', 0.5, 'DisplayName', 'Чужие (Impostors)');
    grid on;
    xlabel(['Расстояние - ' method_name]);
    ylabel('Количество тестов');
    title(['Разделительная способность: ' method_name]);
    legend('show');
    threshold = (mean(scores_own) + mean(scores_alien)) / 2;
    xline(threshold, '--r', 'LineWidth', 2, 'Label', 'Возможный порог');
    hold off;
end