classdef voiceVerifier < handle
    % voiceVerifier — голосовой верификатор на основе MFCC-признаков.
    %
    % Пример использования:
    %   vv = voiceVerifier();
    %   vv.Configure(ref_data, ref_fs);
    %   score = vv.Process(test_data, test_fs);
    %   score = vv.Process(test_data, test_fs, 'dtw');
    %
    % Методы:
    %   Configure(ref_data, ref_fs, params)
    %       Инициализирует параметры и вычисляет эталонные признаки.
    %       ref_data   — вектор отсчётов референсной записи
    %       ref_fs     — частота дискретизации референсной записи
    %       params     — структура с полями:
    %                     frame_len_s  (по умолч. 0.025)
    %                     hop_size_s   (по умолч. 0.010)
    %                     nfft         (по умолч. 512)
    %                     n_filters    (по умолч. 20)
    %                     n_coeffs     (по умолч. 13)
    %                     pre_emph     (по умолч. 0.97)
    %
    %   score = Process(test_data, test_fs)
    %   score = Process(test_data, test_fs, method)
    %       Извлекает признаки из тестовой записи и возвращает меру
    %       расстояния до эталона.
    %       method — 'euclidean' (по умолч.) или 'dtw'
    %       Меньший score означает большее сходство с диктором.

    % ------------------------------------------------------------------ %
    %  Публичные свойства (доступны для чтения снаружи)
    % ------------------------------------------------------------------ %
    properties (SetAccess = private)
        Params          % Структура параметров MFCC
        RefFeatures     % Cell-массив MFCC эталонных записей 
                        % num_ref_data × [num_frames × n_coeffs]
        RefIdx          % Индекс записи, выбранной референсом
        Threshold       % Порог верификации, вычисленный по калибровочным записям
        isConfigured    % Флаг готовности
    end

    % ------------------------------------------------------------------ %
    %  Публичные методы
    % ------------------------------------------------------------------ %
    methods (Access = public)

        function Configure(obj, ref_data, ref_fs, params)
            % Configure  Инициализация верификатора.
            %
            % Аргументы:
            %   rec_data — cell-массив {N×1} записей владельца (N >= 2).
            %              rec_data{1} — референс (точка отсчёта).
            %              rec_data{2..N} — остальные записи для расчёта порога.
            %   rec_fs   — частота дискретизации (одна на все записи, Гц)
            %
            % Необязательный аргумент:
            %   params   — структура с полями (см. описание класса),
            %              также может содержать поле threshold_k (по умолч. 2.0) —
            %              коэффициент запаса при вычислении порога

            % --- Параметры по умолчанию --------------------------------
            default_params.frame_len_s  = 0.025; % Длина окна, с
            default_params.hop_size_s   = 0.010; % Шаг кадра, с
            default_params.nfft         = 512;   % Размер FFT
            default_params.n_filters    = 20;    % Количество Мел-фильтров
            default_params.n_coeffs     = 13;    % Количество MFCC-коэффициентов
            default_params.pre_emph     = 0.97;  % Коэффициент пре-акцента
            default_params.threshold_k  = 0.3;   % Параметр из формуры 
                                                 % порога (mean + k*std)
            default_params.Method       = 'Euclidean';

            % --- Слияние с пользовательскими параметрами ---------------
            if nargin < 4 || isempty(params)
                obj.Params = default_params;
            else
                obj.Params = obj.mergeParams(default_params, params);
            end


            % Вычисление метрик для всех реф записей
            num_ref_data = numel(ref_data);

            for j_ref = 1 : num_ref_data
                obj.RefFeatures{j_ref} = obj.extractSimpleMFCC(ref_data{j_ref}, ref_fs{j_ref});
            end

            % --- Вычисление порога -------------------------------------
            % порог = mean + k * std

            scores = [];
        
            % 1. Перекрестное сравнение (N*(N-1)/2 пар)
            for i = 1:num_ref_data
                for j = i+1:num_ref_data
                    score = obj.calcScore(obj.RefFeatures{i}, obj.RefFeatures{j}, obj.Params.Method);
                    scores = [scores, score];
                end
            end
        
            % 2. Статистический расчет
            avgDist = mean(scores);
            stdDist = std(scores);
        
            % 3. Вычисление порога (используем k=3 для уверенности)

            threshold = avgDist + obj.Params.threshold_k * stdDist;
            
            % --- ПРЕДОХРАНИТЕЛЬ (Safety Margin) ---
            % Если референсы слишком идеальные (std почти 0), 
            % порог станет 0.99 и не пустит тебя в другой обстановке.
            % Установим минимально допустимый порог на уровне 80% от среднего.
            minThreshold = avgDist * 0.80; 
            obj.Threshold = max(threshold, minThreshold);
            
            fprintf('Расчет завершен. Среднее расстояние: %.4f, Порог: %.4f\n', avgDist, obj.Threshold);

            obj.isConfigured = true;

            fprintf('Конфигурация закончена\n');
        end

        % --------------------------------------------------------------- %

        function [scores, decision] = Process(obj, test_data, test_fs, method)
            % Process  Верификация тестовой записи.
            %
            % Возвращает:
            %   score    — расстояние (меньше = похожее)
            %   decision — true если score < Threshold (владелец), false если чужой
            %
            % Примечание: Threshold вычисляется по Euclidean в Configure.
            % При использовании метода 'dtw' decision носит справочный характер.

            if ~obj.isConfigured
                error('voiceVerifier:Process', ...
                    'Сначала вызовите Configure.');
            end

            if nargin < 4 || isempty(method)
                method = 'euclidean';
            end

            % Извлечение признаков тестовой записи
            test_features = obj.extractSimpleMFCC(test_data, test_fs);

            % Вычисление расстояний для каждой реф записью
            num_ref_data = numel(obj.RefFeatures);
            scores = [];
            for j_ref = 1 : num_ref_data
                score = obj.calcScore(test_features, obj.RefFeatures{j_ref}, obj.Params.Method);
                scores = [scores score];
            end

            % Решение на основе порога
            decision = score < obj.Threshold;
        end

    end % methods (public)

    % ------------------------------------------------------------------ %
    %  Приватные методы
    % ------------------------------------------------------------------ %
    methods (Access = private)
       
        function clipped_signal = TrimSilence(~, signal, fs)
            % Разделяем сигнал на короткие окна для анализа энергии
            win_len = round(0.02 * fs); % Окно 20 мс
            step = round(0.01 * fs);    % Шаг 10 мс
            
            % Считаем кратковременную энергию (RMS)
            energy = [];
            for i = 1:step:(length(signal)-win_len)
                energy = [energy, sqrt(mean(signal(i:i+win_len).^2))];
            end
            
            % Порог: 5-10% от максимальной энергии
            threshold = max(energy) * 0.3; 
            
            % Находим индексы окон, где есть голос
            voice_windows = find(energy > threshold);
            
            if isempty(voice_windows)
                clipped_signal = signal; % Если голоса нет, возвращаем как есть
            else
                % Пересчитываем индексы окон обратно в индексы семплов
                start_sample = (voice_windows(1) - 1) * step + 1;
                end_sample = min(length(signal), (voice_windows(end) - 1) * step + win_len);
                clipped_signal = signal(start_sample:end_sample);
            end
        end


        % --------------------------------------------------------------- %
        function mfcc_features = extractSimpleMFCC(obj, signal, fs)
            
            clipped_signal = obj.TrimSilence(signal, fs);
            
            % Вычисление MFCC-признаков сигнала.

            p = obj.Params;
            frame_len = round(p.frame_len_s * fs);
            hop_size  = round(p.hop_size_s  * fs);

            % 1. Пре-акцент: y[n] = x[n] - alpha * x[n-1]
            emphasized_signal = filter([1, -p.pre_emph], 1, clipped_signal);

            % 2. Разбиение на кадры
            num_frames   = floor((length(emphasized_signal) - frame_len) / hop_size) + 1;
            mfcc_features = zeros(num_frames, p.n_coeffs);

            % 3. Окно Хэмминга
            h_window = 0.54 - 0.46 * cos(2 * pi * (0:frame_len-1)' / (frame_len-1));

            % 4. Набор фильтров
            mel_bank = obj.createMelBank(p.n_filters, p.nfft, fs);

            % 5. Цикл по кадрам
            for i = 1:num_frames
                start_idx = (i-1) * hop_size + 1;
                frame     = emphasized_signal(start_idx : start_idx + frame_len - 1);

                % Оконная функция + FFT + спектр мощности
                windowed_frame = frame .* h_window;
                spec       = abs(fft(windowed_frame, p.nfft));
                power_spec = (1/p.nfft) * (spec(1:p.nfft/2+1).^2);
                if size(power_spec, 1) == 1
                    power_spec = power_spec(:);  % Принудительно столбец
                end

                % Фильтрация + лог + DCT
                mel_energies     = mel_bank * power_spec;
                log_mel_energies = log(mel_energies + 1e-10);
                mfcc_features(i, :) = obj.applySimpleDCT(log_mel_energies, p.n_coeffs);
            end
            if obj.Params.Method == "DTW"
                mfcc_features = mfcc_features - mean(mfcc_features, 1);
            end
        end

        % --------------------------------------------------------------- %
        function bank = createMelBank(~, n_filters, nfft, fs)
            % createMelBank  Формирование треугольного Мел-фильтрового банка.

            f_min = 0;
            f_max = fs / 2;
            m_min = 1127 * log(1 + f_min/700);
            m_max = 1127 * log(1 + f_max/700);

            m_pts = linspace(m_min, m_max, n_filters + 2);
            f_pts = 700 * (exp(m_pts / 1127) - 1);

            bins = floor((nfft + 1) * f_pts / fs);
            bank = zeros(n_filters, nfft/2 + 1);

            for m = 2:n_filters+1
                for k = bins(m-1):bins(m)
                    bank(m-1, k+1) = (k - bins(m-1)) / (bins(m) - bins(m-1));
                end
                for k = bins(m):bins(m+1)
                    bank(m-1, k+1) = (bins(m+1) - k) / (bins(m+1) - bins(m));
                end
            end
        end

        % --------------------------------------------------------------- %
        function coeffs = applySimpleDCT(~, data, n_out)
            % Упрощённое DCT-II преобразование.

            N      = length(data);
            coeffs = zeros(1, n_out);
            for k = 1:n_out
                sum_val = 0;
                for n = 1:N
                    sum_val = sum_val + data(n) * cos(pi * (k-1) * (n - 0.5) / N);
                end
                coeffs(k) = sum_val;
            end
        end

        % --------------------------------------------------------------- %
        function score = compareEuclidean(~, features_test, features_ref)
            % Евклидово расстояние между усреднёнными MFCC.

            mean_test = mean(features_test, 1);
            mean_ref  = mean(features_ref,  1);
            score     = sqrt(sum((mean_test - mean_ref).^2));
        end

        % --------------------------------------------------------------- %
        function score = compareDTW(~, features_test, features_ref)
            % Dynamic Time Warping расстояние между MFCC-матрицами.

            N = size(features_test, 1);
            M = size(features_ref,  1);

            D = zeros(N, M);

            % Инициализация
            D(1,1) = sqrt(sum((features_test(1,:) - features_ref(1,:)).^2));
            for i = 2:N
                D(i,1) = D(i-1,1) + sqrt(sum((features_test(i,:) - features_ref(1,:)).^2));
            end
            for j = 2:M
                D(1,j) = D(1,j-1) + sqrt(sum((features_test(1,:) - features_ref(j,:)).^2));
            end

            % Основной цикл (динамическое программирование)
            for i = 2:N
                for j = 2:M
                    dist   = sqrt(sum((features_test(i,:) - features_ref(j,:)).^2));
                    D(i,j) = dist + min([D(i-1,j), D(i,j-1), D(i-1,j-1)]);
                end
            end

            % Нормализованная мера схожести
            score = D(N, M) / (N + M);
        end

        % --------------------------------------------------------------- %
        function score = compareCosine(~, features_test, features_ref)
            % features_test, features_ref - матрицы [frames x coeffs]
            
            n_segments = 3;
            n_coeffs = size(features_test, 2);
            seg_scores = zeros(1, n_segments);
            
            frames_t = size(features_test, 1);
            frames_r = size(features_ref, 1);
            
            step_t = floor(frames_t / n_segments);
            step_r = floor(frames_r / n_segments);
            
            for s = 1:n_segments
                idx_t = ((s-1)*step_t + 1) : (s*step_t);
                idx_r = ((s-1)*step_r + 1) : (s*step_r);
                
                % 1. Средний спектр (Тембр)
                v1_mean = mean(features_test(idx_t, 2:end), 1);
                v2_mean = mean(features_ref(idx_r, 2:end), 1);
                
                % 2. Динамика спектра (Ритм/Вариативность)
                v1_std = std(features_test(idx_t, 2:end), 0, 1);
                v2_std = std(features_ref(idx_r, 2:end), 0, 1);
                
                % Косинус для средних
                cos_mean = sum(v1_mean .* v2_mean) / (norm(v1_mean) * norm(v2_mean) + 1e-10);
                
                % Косинус для отклонений (сравнение "рисунка" изменения голоса)
                cos_std = sum(v1_std .* v2_std) / (norm(v1_std) * norm(v2_std) + 1e-10);
                
                % Объединяем: тембр должен совпасть И динамика должна совпасть
                % Веса 0.6 и 0.4 можно подкрутить
                seg_scores(s) = 0.6 * cos_mean + 0.4 * cos_std;
            end
            
            % Итоговый результат
            score = mean(seg_scores);
        end

        % --------------------------------------------------------------- %

        function score = compareFrameStep(~, features_test, features_ref)
            % 1. Обрезка тишины (VAD) предполагается выполненной до вызова
            
            % 2. Приводим к одной длине (100 кадров)
            target_len = 100;
            f_test = resample(features_test, target_len, size(features_test, 1));
            f_ref = resample(features_ref, target_len, size(features_ref, 1));
            
            n_coeffs = size(f_test, 2);
            frame_scores = zeros(target_len, 1);
            
            % 4. Покадровое взвешенное сравнение
            for i = 1:target_len
                v1 = f_test(i, 2:end); 
                v2 = f_ref(i, 2:end);
                
                dot_p = sum(v1 .* v2);
                norm_p = sqrt(sum(v1.^2)) * sqrt(sum(v2.^2));
                
                if norm_p > 1e-10
                    frame_scores(i) = dot_p / norm_p;
                else
                    frame_scores(i) = 0;
                end
            end
            
            % Итоговый результат с нелинейным усилением
            score = mean(frame_scores);
            score = score^20;
        end



        % --------------------------------------------------------------- %

        function score = calcScore(obj, features_test, features_ref, method)
            switch lower(method)
                case 'euclidean'
                    score = obj.compareEuclidean(features_test, features_ref);
                case 'dtw'
                    score = obj.compareDTW(features_test, features_ref);
                case 'cos'
                    score = obj.compareCosine(features_test, features_ref);
                case 'frames'
                    score = obj.compareFrameStep(features_test, features_ref);
                otherwise
                    error('voiceVerifier:Process', ...
                        'Неизвестный метод ''%s''. Используйте ''euclidean'' или ''dtw''.', method);
            end
        end

        % --------------------------------------------------------------- %
        function out = mergeParams(~, defaults, user)
            % mergeParams  Подставляет пользовательские значения поверх defaults.

            out    = defaults;
            fields = fieldnames(user);
            for k = 1:numel(fields)
                f = fields{k};
                if isfield(defaults, f)
                    out.(f) = user.(f);
                else
                    warning('voiceVerifier:Configure', ...
                        'Неизвестный параметр ''%s'' проигнорирован.', f);
                end
            end
        end

    end % methods (private)

end % classdef
