function [FRR, FAR, Accuracy] = run_simple_test(num_ref_data, nfft)
  
    addpath ../../source
    
   
    % -----------------------------------------------------------------------
    % Загрузка всех записей в один массив
    % Первая запись становится референсом, остальные для расчёта порога
    % -----------------------------------------------------------------------
    ref_folder = '../../audio/ref';
    ref_files_full  = dir(fullfile(ref_folder, '*.wav'));
    ref_data_inds = randperm(numel(ref_files_full), num_ref_data);
    
    [ref_data, ref_fs] = deal(cell(num_ref_data, 1));
    for j_test = 1 : num_ref_data
        [ref_data{j_test}, ref_fs{j_test}] = audioread(fullfile(ref_folder, ref_files_full(ref_data_inds(j_test)).name));
    end
    

    % -----------------------------------------------------------------------
    % Создание и настройка верификатора
    % -----------------------------------------------------------------------
    
    % fprintf("\n=== Запуск нового тест ===\n")
    
    params.Method = 'frames';
    params.nfft = nfft;
    
    vv = voiceVerifier();
    vv.Configure(ref_data, ref_fs, params);
    
    % -----------------------------------------------------------------------
    % Верификация: свои записи
    % -----------------------------------------------------------------------
    % fprintf('=== Свои (Authorized) ===\n');
    auth_folder = '../../audio/auth';
    auth_files  = dir(fullfile(auth_folder, '*.wav'));
    scores_auth = zeros(numel(auth_files), num_ref_data);
    decision_auth = zeros(1, numel(auth_files));
    
    for j_test = 1:numel(auth_files)
        % fprintf("[%i]: ", j_test);
        [test_data, test_fs] = audioread(fullfile(auth_folder, auth_files(j_test).name));
        [scores_auth(j_test, :), decision_auth(1, j_test)] = vv.Process(test_data, test_fs);
    end
    
    % -----------------------------------------------------------------------
    % Верификация: чужие записи
    % -----------------------------------------------------------------------
    % fprintf('=== Чужие (Impostors) ===\n');
    imp_folder = '../../audio/imposters';
    imp_files  = dir(fullfile(imp_folder, '*.wav'));
    scores_imp = zeros(numel(imp_files), num_ref_data);
    decision_imp = zeros(1, numel(imp_files));
    
    for j_test = 1:numel(imp_files)
        % fprintf("[%i]: ", j_test);
        [test_data, test_fs] = audioread(fullfile(imp_folder, imp_files(j_test).name));
        [scores_imp(j_test, :), decision_imp(1, j_test)] = vv.Process(test_data, test_fs);
    end
    
    % fprintf("\nАнализ результатов\n");
    
    FRR = (sum(decision_auth == 0) / numel(decision_auth)) * 100;
    FAR = (sum(decision_imp == 1) / numel(decision_imp)) * 100;
    
    % Общая точность (Accuracy)
    Accuracy = (sum(decision_auth == 1) + sum(decision_imp == 0)) /  (numel(decision_auth) + numel(decision_imp)) * 100;
    
    % fprintf('FRR (Ложный отказ): %.2f%%\n', FRR);
    % fprintf('FAR (Ложный доступ): %.2f%%\n', FAR);
    % fprintf('Общая точность: %.2f%%\n\n', Accuracy);

end