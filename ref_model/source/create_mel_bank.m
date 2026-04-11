function bank = create_mel_bank(n_filters, n_fft, fs)
    % Перевод частоты в Мелы и обратно
    f_min = 0;
    f_max = fs / 2;
    m_min = 1127 * log(1 + f_min/700);
    m_max = 1127 * log(1 + f_max/700);
    
    m_pts = linspace(m_min, m_max, n_filters + 2);
    f_pts = 700 * (exp(m_pts / 1127) - 1);
    
    % Индексы бинов FFT
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