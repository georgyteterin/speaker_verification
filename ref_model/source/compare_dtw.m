function score = compare_dtw(features_test, features_ref)
    % N и M - количество кадров в записях
    N = size(features_test, 1);
    M = size(features_ref, 1);
    
    % Матрица накопленных расстояний (в МК это будет массив в RAM)
    D = zeros(N, M);
    
    % Инициализация первой ячейки
    D(1,1) = sqrt(sum((features_test(1,:) - features_ref(1,:)).^2));
    
    % Заполнение первой колонки и первой строки
    for i = 2:N
        dist = sqrt(sum((features_test(i,:) - features_ref(1,:)).^2));
        D(i,1) = D(i-1,1) + dist;
    end
    for j = 2:M
        dist = sqrt(sum((features_test(1,:) - features_ref(j,:)).^2));
        D(1,j) = D(1,j-1) + dist;
    end
    
    % Основной цикл DTW (Динамическое программирование)
    for i = 2:N
        for j = 2:M
            dist = sqrt(sum((features_test(i,:) - features_ref(j,:)).^2));
            % Выбираем минимальный путь из трех возможных направлений
            D(i,j) = dist + min([D(i-1, j), D(i, j-1), D(i-1, j-1)]);
        end
    end
    
    % Итоговая мера схожести (нормализованная на длину пути)
    score = D(N, M) / (N + M);
end