% class_example.m — пример использования класса voiceVerifier
clear, clc, close all

addpath ../source

% -----------------------------------------------------------------------
% Референсная запись
% -----------------------------------------------------------------------
[ref_data, ref_fs] = audioread('../audio/testset1/ref.wav');

% -----------------------------------------------------------------------
% Калибровочные записи (свои) 
% -----------------------------------------------------------------------
calib_folder = '../audio/testset1/actual';
calib_files  = dir(fullfile(calib_folder, '*.wav'));

calib_data = cell(numel(calib_files), 1);
for k = 1:numel(calib_files)
    [calib_data{k}, ~] = audioread(fullfile(calib_folder, calib_files(k).name));
end
calib_fs = ref_fs;

% -----------------------------------------------------------------------
% Создание и настройка верификатора
% -----------------------------------------------------------------------
vv = voiceVerifier();
vv.Configure(ref_data, ref_fs, calib_data, calib_fs);

fprintf('Порог верификации: %.4f\n', vv.Threshold);
fprintf('Калибровочные scores: min=%.4f  mean=%.4f  max=%.4f\n\n', ...
    min(vv.CalibScores), mean(vv.CalibScores), max(vv.CalibScores));

% -----------------------------------------------------------------------
% Верификация: свои записи
% -----------------------------------------------------------------------
fprintf('=== Свои (Authorized) ===\n');
auth_folder = '../audio/testset1/actual';
auth_files  = dir(fullfile(auth_folder, '*.wav'));
scores_own_euc = zeros(1, numel(auth_files));
scores_own_dtw = zeros(1, numel(auth_files));

for k = 1:numel(auth_files)
    [test_data, test_fs] = audioread(fullfile(auth_folder, auth_files(k).name));
    [scores_own_euc(k), decision] = vv.Process(test_data, test_fs, 'euclidean');
    scores_own_dtw(k)             = vv.Process(test_data, test_fs, 'dtw');
    filename = strtrim(auth_files(k).name);
    if decision
        verdict = 'ПРИНЯТ';
    else
        verdict = 'ОТКЛОНЁН';
    end
    fprintf('  %s  |  Euc: %.4f  |  DTW: %.4f  |  %s\n', ...
        filename, scores_own_euc(k), scores_own_dtw(k), verdict);
end

% -----------------------------------------------------------------------
% Верификация: чужие записи
% -----------------------------------------------------------------------
fprintf('\n=== Чужие (Impostors) ===\n');
imp_folder = '../audio/testset1/imposters';
imp_files  = dir(fullfile(imp_folder, '*.wav'));
scores_imp_euc = zeros(1, numel(imp_files));
scores_imp_dtw = zeros(1, numel(imp_files));

for k = 1:numel(imp_files)
    [test_data, test_fs] = audioread(fullfile(imp_folder, imp_files(k).name));
    [scores_imp_euc(k), decision] = vv.Process(test_data, test_fs, 'euclidean');
    scores_imp_dtw(k)             = vv.Process(test_data, test_fs, 'dtw');
    filename = strtrim(imp_files(k).name);
    if decision
        verdict = 'ПРИНЯТ';
    else
        verdict = 'ОТКЛОНЁН';
    end
    fprintf('  %s  |  Euc: %.4f  |  DTW: %.4f  |  %s\n', ...
        filename, scores_imp_euc(k), scores_imp_dtw(k), verdict);
end

% -----------------------------------------------------------------------
% Гистограммы
% -----------------------------------------------------------------------
plot_verification_results(scores_own_euc, scores_imp_euc, 'Euclidean', vv.Threshold);
plot_verification_results(scores_own_dtw,  scores_imp_dtw,  'DTW');
