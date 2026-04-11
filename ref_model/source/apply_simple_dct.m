function coeffs = apply_simple_dct(data, n_out)
    % Упрощенное DCT-II
    N = length(data);
    coeffs = zeros(1, n_out);
    for k = 1:n_out
        sum_val = 0;
        for n = 1:N
            sum_val = sum_val + data(n) * cos(pi * (k-1) * (n - 0.5) / N);
        end
        coeffs(k) = sum_val;
    end
end