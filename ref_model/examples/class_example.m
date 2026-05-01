% class_example.m — пример использования класса voiceVerifier
clear, clc, close all

addpath ../source

% Кол-во реф записей для обработки, бует вынесено в настройки теста
num_ref_data = 4;

% -----------------------------------------------------------------------
% Загрузка всех записей в один массив
% Первая запись становится референсом, остальные для расчёта порога
% -----------------------------------------------------------------------
ref_folder = '../audio/ref';
ref_files_full  = dir(fullfile(ref_folder, '*.wav'));
ref_data_inds = randperm(numel(ref_files_full), num_ref_data);

[ref_data, ref_fs] = deal(cell(num_ref_data, 1));
for j_test = 1 : num_ref_data
    [ref_data{j_test}, ref_fs{j_test}] = audioread(fullfile(ref_folder, ref_files_full(ref_data_inds(j_test)).name));
end

% fprintf('Загружено записей: %d \n\n', num_ref_data);

% -----------------------------------------------------------------------
% Создание и настройка верификатора
% -----------------------------------------------------------------------
% fprintf('Началась конфигурация \n\n');

params.Method = 'frames';

vv = voiceVerifier();
vv.Configure(ref_data, ref_fs, params);

% -----------------------------------------------------------------------
% Верификация: свои записи
% -----------------------------------------------------------------------
% fprintf('=== Свои (Authorized) ===\n');
auth_folder = '../audio/auth';
auth_files  = dir(fullfile(auth_folder, '*.wav'));
scores_auth = zeros(numel(auth_files), num_ref_data);

for j_test = 1:numel(auth_files)
    [test_data, test_fs] = audioread(fullfile(auth_folder, auth_files(j_test).name));
    [scores_auth(j_test, :), decision] = vv.Process(test_data, test_fs);
    if decision
        verdict = 'ПРИНЯТ';
    else
        verdict = 'ОТКЛОНЁН';
    end
end

% -----------------------------------------------------------------------
% Верификация: чужие записи
% -----------------------------------------------------------------------
% fprintf('\n=== Чужие (Impostors) ===\n');
imp_folder = '../audio/imposters';
imp_files  = dir(fullfile(imp_folder, '*.wav'));
scores_imp = zeros(numel(imp_files), num_ref_data);

for j_test = 1:numel(imp_files)
    [test_data, test_fs] = audioread(fullfile(imp_folder, imp_files(j_test).name));
    [scores_imp(j_test, :), decision] = vv.Process(test_data, test_fs);
    if decision
        verdict = 'ПРИНЯТ';
    else
        verdict = 'ОТКЛОНЁН';
    end
end
fprintf("Кол-во строк, где порог превышается 2 раза ('свои'): %d\n", sum(sum(scores_auth > vv.Threshold, 2) > 2));
fprintf("Кол-во строк, где порог превышается 2 раза ('чужие'): %d\n", sum(sum(scores_imp > vv.Threshold, 2) > 2));

% -----------------------------------------------------------------------
% Гистограммы
% -----------------------------------------------------------------------
% plot_verification_results(scores_auth, scores_imp, vv.Params.Method, vv.Threshold);
