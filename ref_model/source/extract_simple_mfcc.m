function mfcc_features = extract_simple_mfcc(signal, fs)
    % 1. Параметры (настраиваем под ресурсы МК)
    frame_len = round(0.025 * fs); % Окно 25 мс
    hop_size = round(0.010 * fs);  % Шаг 10 мс
    n_fft = 512;                   % Ближайшая степень двойки
    n_filters = 20;                % Количество фильтров Мела
    n_coeffs = 13;                 % Сколько коэффициентов оставляем
    
    % 2. Пре-акцент (Pre-emphasis)
    % y[n] = x[n] - 0.97 * x[n-1]
    emphasized_signal = filter([1, -0.97], 1, signal);
    
    % 3. Разбиение на кадры (Framing)
    num_frames = floor((length(emphasized_signal) - frame_len) / hop_size) + 1;
    mfcc_features = zeros(num_frames, n_coeffs);
    
    % Создаем окно Хэмминга заранее
    h_window = 0.54 - 0.46 * cos(2 * pi * (0:frame_len-1)' / (frame_len-1));
    
    % Подготовка фильтров Мела (создаем один раз)
    mel_bank = create_mel_bank(n_filters, n_fft, fs);
    
    % Цикл по кадрам
    for i = 1:num_frames
        % Выделяем кадр
        start_idx = (i-1) * hop_size + 1;
        frame = emphasized_signal(start_idx : start_idx + frame_len - 1);
        
        % Окно + FFT
        windowed_frame = frame .* h_window;
        spec = abs(fft(windowed_frame, n_fft));
        power_spec = (1/n_fft) * (spec(1:n_fft/2+1).^2); % Спектр мощности
        if size(power_spec, 1) == 1
            power_spec = power_spec(:);
        end
        % Фильтрация (Mel Filter Bank)
        % На МК это просто перемножение вектора на матрицу
        mel_energies = mel_bank * power_spec;
        
        % Логарифмирование (с защитой от log(0))
        log_mel_energies = log(mel_energies + 1e-10);
        
        % Дискретное косинусное преобразование (DCT)
        % Вместо встроенной dct() используем матричное умножение
        mfcc_features(i, :) = apply_simple_dct(log_mel_energies, n_coeffs);
    end