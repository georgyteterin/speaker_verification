% example_usage.m — пример использования класса VoiceVerifier
clear, clc, close all

addpath ../source

[ref_data, ref_fs] = audioread('../audio/ref.wav');

vv = voiceVerifier();

% Параметры по умолчанию (можно не передавать)
custom_params.n_coeffs  = 13;
custom_params.n_filters = 20;

vv.Configure(ref_data, ref_fs, custom_params);

% -----------------------------------------------------------------------
% Верификация: свои записи
% -----------------------------------------------------------------------
fprintf('\n=== Свои (Authorized) ===\n');
auth_folder = '../audio/actual';
auth_files  = dir(fullfile(auth_folder, '*.wav'));
scores_own_euc = zeros(1, numel(auth_files));  
scores_own_dtw = zeros(1, numel(auth_files)); 

for k = 1:numel(auth_files)
    [test_data, test_fs] = audioread(fullfile(auth_folder, auth_files(k).name));
    scores_own_euc(k) = vv.Process(test_data, test_fs, 'euclidean');  
    scores_own_dtw(k) = vv.Process(test_data, test_fs, 'dtw');
    fprintf('  %s  |  Euclidean: %.4f  |  DTW: %.4f\n', ...
        auth_files(k).name, scores_own_euc(k), scores_own_dtw(k));
end

% -----------------------------------------------------------------------
% Верификация: чужие записи
% -----------------------------------------------------------------------
fprintf('\n=== Чужие (Impostors) ===\n');
imposter_folder = '../audio/imposters';
imposter_files  = dir(fullfile(imposter_folder, '*.wav'));
scores_imp_euc = zeros(1, numel(imposter_files));   % <-- добавить
scores_imp_dtw = zeros(1, numel(imposter_files)); 

for k = 1:numel(imposter_files)
    [test_data, test_fs] = audioread(fullfile(imposter_folder, imposter_files(k).name));
    scores_imp_euc(k) = vv.Process(test_data, test_fs, 'euclidean');  
    scores_imp_dtw(k) = vv.Process(test_data, test_fs, 'dtw'); 
    fprintf('  %s  |  Euclidean: %.4f  |  DTW: %.4f\n', ...
        imposter_files(k).name, scores_imp_euc(k), scores_imp_dtw(k));
end

% -----------------------------------------------------------------------
% 6. Отрисовка гистограммм
% -----------------------------------------------------------------------
plot_verification_results(scores_own_euc, scores_imp_euc, 'Euclidean');
plot_verification_results(scores_own_dtw,  scores_imp_dtw,  'DTW');
