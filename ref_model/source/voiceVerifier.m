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
    %                     n_fft        (по умолч. 512)
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
        RefFeatures     % MFCC эталонной записи  [num_frames × n_coeffs]
        isConfigured    % Флаг готовности
    end

    % ------------------------------------------------------------------ %
    %  Публичные методы
    % ------------------------------------------------------------------ %
    methods (Access = public)

        function Configure(obj, ref_data, ref_fs, params)
            % --- Параметры по умолчанию --------------------------------
            default_params.frame_len_s = 0.025;  % Длина окна, с
            default_params.hop_size_s  = 0.010;  % Шаг кадра, с
            default_params.n_fft       = 512;    % Размер FFT
            default_params.n_filters   = 20;     % Количество Мел-фильтров
            default_params.n_coeffs    = 13;     % Количество MFCC-коэффициентов
            default_params.pre_emph    = 0.97;   % Коэффициент пре-акцента

            % --- Слияние с пользовательскими параметрами ---------------
            if nargin < 4 || isempty(params)
                obj.Params = default_params;
            else
                obj.Params = obj.mergeParams(default_params, params);
            end

            % --- Признаки референсной записи ---------------------------
            obj.RefFeatures = obj.extractSimpleMFCC(ref_data, ref_fs);

            obj.isConfigured = true;
        end

        % --------------------------------------------------------------- %

        function score = Process(obj, test_data, test_fs, method)

            if ~obj.isConfigured
                error('voiceVerifier:Process', ...
                    'Сначала вызовите Configure.');
            end

            if nargin < 4 || isempty(method)
                method = 'euclidean';
            end

            % Извлечение признаков тестовой записи
            test_features = obj.extractSimpleMFCC(test_data, test_fs);

            % Вычисление расстояния
            switch lower(method)
                case 'euclidean'
                    score = obj.compareEuclidean(test_features, obj.RefFeatures);
                case 'dtw'
                    score = obj.compareDTW(test_features, obj.RefFeatures);
                otherwise
                    error('voiceVerifier:Process', ...
                        'Неизвестный метод ''%s''. Используйте ''euclidean'' или ''dtw''.', method);
            end
        end

    end % methods (public)

    % ------------------------------------------------------------------ %
    %  Приватные методы
    % ------------------------------------------------------------------ %
    methods (Access = private)

        % --------------------------------------------------------------- %
        function mfcc_features = extractSimpleMFCC(obj, signal, fs)
            % Вычисление MFCC-признаков сигнала.

            p = obj.Params;
            frame_len = round(p.frame_len_s * fs);
            hop_size  = round(p.hop_size_s  * fs);

            % 1. Пре-акцент: y[n] = x[n] - alpha * x[n-1]
            emphasized_signal = filter([1, -p.pre_emph], 1, signal);

            % 2. Разбиение на кадры
            num_frames   = floor((length(emphasized_signal) - frame_len) / hop_size) + 1;
            mfcc_features = zeros(num_frames, p.n_coeffs);

            % 3. Окно Хэмминга
            h_window = 0.54 - 0.46 * cos(2 * pi * (0:frame_len-1)' / (frame_len-1));

            % 4. Набор фильтров
            mel_bank = obj.createMelBank(p.n_filters, p.n_fft, fs);

            % 5. Цикл по кадрам
            for i = 1:num_frames
                start_idx = (i-1) * hop_size + 1;
                frame     = emphasized_signal(start_idx : start_idx + frame_len - 1);

                % Оконная функция + FFT + спектр мощности
                windowed_frame = frame .* h_window;
                spec       = abs(fft(windowed_frame, p.n_fft));
                power_spec = (1/p.n_fft) * (spec(1:p.n_fft/2+1).^2);
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
        function bank = createMelBank(~, n_filters, n_fft, fs)
            % createMelBank  Формирование треугольного Мел-фильтрового банка.

            f_min = 0;
            f_max = fs / 2;
            m_min = 1127 * log(1 + f_min/700);
            m_max = 1127 * log(1 + f_max/700);

            m_pts = linspace(m_min, m_max, n_filters + 2);
            f_pts = 700 * (exp(m_pts / 1127) - 1);

            bins = floor((n_fft + 1) * f_pts / fs);
            bank = zeros(n_filters, n_fft/2 + 1);

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
