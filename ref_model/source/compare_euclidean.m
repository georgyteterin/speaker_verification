function score = compare_euclidean(features_test, features_ref)
    % Усредняем признаки по времени (получаем вектор 1x13)
    mean_test = mean(features_test, 1);
    mean_ref = mean(features_ref, 1);
    
    % Вычисляем обычное расстояние между векторами
    % Чем меньше score, тем больше похожи голоса
    score = sqrt(sum((mean_test - mean_ref).^2));
end