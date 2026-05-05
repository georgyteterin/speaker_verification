classdef voiceVerifier < handle
    % voiceVerifier — голосовой верификатор на основе MFCC-признаков.
    %
    % Пример использования:
    %   vv = voiceVerifier();
    %   vv.Configure(ref_data, ref_fs);
    %   score = vv.Process(test_data, test_fs);
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
    %                     threshold_k  (по умолч. 1)
    %                     log          (по умолч. 0) -- Вывод текста
    %
    %   score = Process(test_data, test_fs)
    %   score = Process(test_data, test_fs)
    %       Извлекает признаки из тестовой записи и возвращает меру
    %       расстояния до эталона.

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
        RefWeights      % Веса для разных реф. записей, чем больше расстояние
                        % какая-то реф записи до остальных, тем меньше она
                        % учитывается
        IndividualThresholds
    end

    % ------------------------------------------------------------------ %
    %  Публичные методы
    % ------------------------------------------------------------------ %
    methods (Access = public)

        function Configure(obj, ref_data, ref_fs, params)
            % --- Параметры по умолчанию --------------------------------
            default_params.frame_len_s  = 0.025; 
            default_params.hop_size_s   = 0.010; 
            default_params.nfft         = 1024;   
            default_params.n_filters    = 20;    
            default_params.n_coeffs     = 13;    
            default_params.pre_emph     = 0.97;  
            default_params.threshold_k  = 1;
            default_params.log          = 0;
            % --- Слияние с пользовательскими параметрами ---------------
            if nargin < 4 || isempty(params)
                obj.Params = default_params;
            else
                obj.Params = obj.mergeParams(default_params, params);
            end

            % Извлечение признаков
            num_ref_data = numel(ref_data);
            for j_ref = 1 : num_ref_data
                obj.RefFeatures{j_ref} = obj.extractSimpleMFCC(ref_data{j_ref}, ref_fs{j_ref});
            end
        
            % Матрица взаимного сходства (Оптимизированная симметрия)
            distMatrix = zeros(num_ref_data, num_ref_data);
            for i = 1:num_ref_data
                for j = i+1:num_ref_data
                    s = obj.compareFrameStep(obj.RefFeatures{i}, obj.RefFeatures{j});
                    distMatrix(i,j) = s;
                    distMatrix(j,i) = s; 
                end
            end
        
            % 1. Расчет весов (RefWeights)
            % Считаем среднее сходство каждого рефа с остальными
            meanSimPerRef = sum(distMatrix, 2) / (num_ref_data - 1);
            % Чем выше среднее сходство, тем выше вес (типичность)
            obj.RefWeights = (meanSimPerRef' / sum(meanSimPerRef));
        
            % 2. Расчет индивидуальных порогов (IndividualThresholds)
            obj.IndividualThresholds = zeros(1, num_ref_data);
            for i = 1 : num_ref_data
                rowValues = distMatrix(i, [1:i-1, i+1:num_ref_data]);
                avg_i = mean(rowValues);
                std_i = std(rowValues);
            
                % НОВАЯ ЛОГИКА: Порог чуть НИЖЕ среднего сходства.
                % Чем больше k, тем "мягче" порог (больше допускаем отклонений).
                ti = avg_i - (obj.Params.threshold_k * std_i);
            
                % ПРЕДОХРАНИТЕЛЬ: чтобы порог не ушел в пол или в бесконечность
                obj.IndividualThresholds(i) = min(max(ti, 0.70), 0.98);
            end

            obj.isConfigured = true;
            if obj.Params.log
                fprintf('Результаты конфигурации:\n');
                fprintf('Веса:   [%s]\n', num2str(obj.RefWeights, ' %.3f'));
                fprintf('Пороги: [%s]\n', num2str(obj.IndividualThresholds, ' %.3f'));
            end
        end


        % --------------------------------------------------------------- %

        function [scores, decision] = Process(obj, test_data, test_fs)
            % 1. Проверка конфигурации
            if ~obj.isConfigured
                error('voiceVerifier:Process', 'Сначала вызовите Configure.');
            end
        
            % 2. Извлечение признаков тестовой записи
            test_features = obj.extractSimpleMFCC(test_data, test_fs);
            
            % 3. Расчет сходства (scores) с каждым из N референсов
            num_ref_data = numel(obj.RefFeatures);
            scores = zeros(1, num_ref_data);
            for j_ref = 1 : num_ref_data
                scores(j_ref) = obj.compareFrameStep(test_features, obj.RefFeatures{j_ref});
            end
        
            % 4. Нелинейное преобразование и голосование
            % Степень 10 — золотая середина: достаточно острая для сепарации 0.005, 
            % но не превращает всё в шум.
            power_val = 6; 
            
            % Сравниваем текущее сходство в степени с индивидуальным порогом в степени
            % Это создает крутой "обрыв" для тех, кто чуть-чуть не дотягивает.
            votes = (scores.^power_val) >= (obj.IndividualThresholds.^power_val);
        
            % 5. Взвешенное суммирование голосов
            % Референсы, которые "признали" голос, вносят вклад согласно своему весу (RefWeights)
            final_weighted_vote = sum(votes .* obj.RefWeights);
        
            % 6. Принятие решения
            % Порог 0.5 означает "мажоритарное" решение: доступ разрешен, если 
            % сумма весов проголосовавших "ЗА" превышает половину.
            decision = final_weighted_vote > 0.35;
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

        function resampled = manualResample(~, data, new_len)
            [old_len, n_coeffs] = size(data);
            resampled = zeros(new_len, n_coeffs);
            
            if old_len < 2
                if old_len == 1
                    resampled = repmat(data, new_len, 1);
                end
                return; 
            end
            
            % Шаг прохода
            step = (old_len - 1) / (new_len - 1);
            
            for i = 1:new_len
                pos = (i-1) * step + 1;
                
                low = floor(pos);
                high = ceil(pos);
                
                % Жесткое ограничение индексов (защита от выхода за границы)
                low = max(1, min(low, old_len));
                high = max(1, min(high, old_len));
                
                if low == high
                    resampled(i, :) = data(low, :);
                else
                    frac = pos - low;
                    % Интерполяция
                    resampled(i, :) = (1 - frac) * data(low, :) + frac * data(high, :);
                end
            end
        end

        % --------------------------------------------------------------- %
        function score = compareFrameStep(obj, features_test, features_ref)
            
            % Приводим к одной длине (100 кадров)
            target_len = 100;
            f_test = obj.manualResample(features_test, target_len);
            f_ref = obj.manualResample(features_ref, target_len);
            
            frame_scores = zeros(target_len, 1);
            for i = 1:target_len
                v1 = f_test(i, 2:end); 
                v2 = f_ref(i, 2:end);
                norm_p = sqrt(sum(v1.^2)) * sqrt(sum(v2.^2));
                if norm_p > 1e-10
                    frame_scores(i) = sum(v1 .* v2) / norm_p;
                else
                    frame_scores(i) = 0;
                end
            end
            
            % Возвращаем среднее БЕЗ степени. Теперь score всегда в районе 0.8-0.95
            score = mean(frame_scores);
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
