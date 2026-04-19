% example_usage.m — пример использования класса VoiceVerifier
clear, clc, close all

% -----------------------------------------------------------------------
% 1. Чтение референсной записи
% -----------------------------------------------------------------------
[ref_data, ref_fs] = audioread('audio/ref.wav');

% -----------------------------------------------------------------------
% 2. Сборка обучающих записей в cell-массив
% -----------------------------------------------------------------------
train_folder = 'audio/actual';
train_files  = dir(fullfile(train_folder, '*.wav'));

train_data = cell(numel(train_files), 1);
for k = 1:numel(train_files)
    [train_data{k}, ~] = audioread(fullfile(train_folder, train_files(k).name));
end
train_fs = ref_fs;  % Предполагаем единую fs

% -----------------------------------------------------------------------
% 3. Создание и настройка верификатора
% -----------------------------------------------------------------------
vv = VoiceVerifier();

% Параметры по умолчанию (можно не передавать)
custom_params.n_coeffs  = 13;
custom_params.n_filters = 20;

vv.Configure(ref_data, ref_fs, train_data, train_fs, custom_params);

% -----------------------------------------------------------------------
% 4. Верификация: свои записи
% -----------------------------------------------------------------------
fprintf('\n=== Свои (Authorized) ===\n');
scores_own_euc = zeros(1, numel(train_files));  
scores_own_dtw = zeros(1, numel(train_files)); 

for k = 1:numel(train_files)
    [test_data, test_fs] = audioread(fullfile(train_folder, train_files(k).name));
    scores_own_euc(k) = vv.Process(test_data, test_fs, 'euclidean');  
    scores_own_dtw(k) = vv.Process(test_data, test_fs, 'dtw');
    fprintf('  %s  |  Euclidean: %.4f  |  DTW: %.4f\n', ...
        train_files(k).name, scores_own_euc(k), scores_own_dtw(k));
end

% -----------------------------------------------------------------------
% 5. Верификация: чужие записи
% -----------------------------------------------------------------------
fprintf('\n=== Чужие (Impostors) ===\n');
imposter_folder = 'audio/imposters';
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
