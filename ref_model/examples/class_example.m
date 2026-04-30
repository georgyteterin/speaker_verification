% class_example.m — пример использования класса voiceVerifier
clear, clc, close all

addpath ../source

% -----------------------------------------------------------------------
% Загрузка всех записей в один массив
% Первая запись становится референсом, остальные для расчёта порога
% -----------------------------------------------------------------------
rec_folder = '../audio/actual';
rec_files  = dir(fullfile(rec_folder, '*.wav'));

rec_data = cell(numel(rec_files), 1);
for k = 1:numel(rec_files)
    [rec_data{k}, rec_fs] = audioread(fullfile(rec_folder, rec_files(k).name));
end

fprintf('Загружено записей: %d  (референс: %s)\n\n', ...
    numel(rec_files), strtrim(rec_files(1).name));

% -----------------------------------------------------------------------
% Создание и настройка верификатора
% -----------------------------------------------------------------------
vv = voiceVerifier();
vv.Configure(rec_data, rec_fs);

fprintf('Порог верификации: %.4f\n', vv.Threshold);
fprintf('CalibScores: min=%.4f  mean=%.4f  max=%.4f\n\n', ...
    min(vv.CalibScores), mean(vv.CalibScores), max(vv.CalibScores));

% -----------------------------------------------------------------------
% Верификация: свои записи
% -----------------------------------------------------------------------
fprintf('=== Свои (Authorized) ===\n');
scores_own_euc = zeros(1, numel(rec_files) - 1);
scores_own_dtw = zeros(1, numel(rec_files) - 1);

for k = 2:numel(rec_files)
    [test_data, test_fs] = audioread(fullfile(rec_folder, rec_files(k).name));
    [scores_own_euc(k-1), decision] = vv.Process(test_data, test_fs, 'euclidean');
    scores_own_dtw(k-1)             = vv.Process(test_data, test_fs, 'dtw');
    filename = strtrim(rec_files(k).name);
    if decision
        verdict = 'ПРИНЯТ';
    else
        verdict = 'ОТКЛОНЁН';
    end
    fprintf('  %s  |  Euc: %.4f  |  DTW: %.4f  |  %s\n', ...
        filename, scores_own_euc(k-1), scores_own_dtw(k-1), verdict);
end

% -----------------------------------------------------------------------
% Верификация: чужие записи
% -----------------------------------------------------------------------
fprintf('\n=== Чужие (Impostors) ===\n');
imp_folder = '../audio/imposters';
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
