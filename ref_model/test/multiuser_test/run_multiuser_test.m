function [FRR, FAR, Accuracy, details] = run_multiuser_test(num_ref_voices, num_ref_data, nfft)
% run_multiuser_test  Мультипользовательский тест голосового верификатора.
%
%   Механизм:
%   случайный выбор команды, реф-голосов и записей (реф / auth / импостеры).
%
%   Ожидаемая структура аудио (мы ушли от папок ref/auth/imp —
%   всё определяется случайно здесь, в тесте):
%
%       audio/
%         task1/                
%           voice1/  rec1.wav rec2.wav ...
%           voice2/  rec1.wav rec2.wav ...
%           ...
%         task2/
%           ...
%
%   Логика теста:
%     1. Случайно выбирается ОДНА команда (папка task* в audio/).
%        Сейчас поддержка одной команды — берём одну случайную.
%     2. Внутри команды случайно выбираются num_ref_voices голосов как
%        реф-голоса. Каждый реф-голос получает СВОЙ отдельный верификатор
%        (U зарегистрированных пользователей).
%     3. Для каждого реф-голоса num_ref_data случайных записей идут в реф,
%        остальные записи этого голоса становятся auth (свои проверочные).
%     4. Импостеры для верификатора берутся из записей ВСЕХ остальных
%        голосов команды — включая другие реф-голоса (для ref_1 записи
%        ref_2 являются импостерами). Число импостеров на верификатор
%        равно числу его auth-записей (баланс выборок для честной оценки).
%     5. FRR/FAR/Accuracy агрегируются по всем верификаторам; details
%        содержит разбивку по каждому верификатору.
%
%   Входные параметры:
%     num_ref_voices — число реф-голосов U   (ожидается 1..4)
%     num_ref_data   — число реф-записей n   на каждый реф-голос (2..4)
%     nfft           — размер FFT, передаётся в верификатор
%
%   Выходные параметры:
%     FRR, FAR, Accuracy — агрегированные метрики по всем верификаторам, %
%     details            — структура с детальной разбивкой:
%                            .task            имя выбранной команды
%                            .ref_voices      имена выбранных реф-голосов
%                            .per_verifier    массив структур по каждому
%                                             верификатору (voice, num_ref,
%                                             num_auth, num_imp, FRR, FAR,
%                                             Accuracy)
%                            .num_auth_total  суммарно auth-проверок
%                            .num_imp_total   суммарно imp-проверок

    addpath ../../source

    % ------------------------------------------------------------------
    % 1. Выбор случайной команды (task)
    % ------------------------------------------------------------------
    audio_root = '../../audio';
    % Командами считаются только папки с именем task* — старые папки
    % ref/auth/imposters (если они ещё лежат в audio/) тест игнорирует.
    task_list  = list_subdirs(audio_root, 'task*');
    if isempty(task_list)
        error('run_multiuser_test:noTasks', ...
              'В папке "%s" не найдено ни одной команды (папки task*).', audio_root);
    end
    task_name = task_list{randi(numel(task_list))};
    task_path = fullfile(audio_root, task_name);

    % ------------------------------------------------------------------
    % 2. Список голосов команды и выбор реф-голосов
    % ------------------------------------------------------------------
    voice_list = list_subdirs(task_path);
    if numel(voice_list) < 2
        error('run_multiuser_test:notEnoughVoices', ...
              ['В команде "%s" найдено %d голосов; нужно >= 2 ', ...
               '(импостеры берутся из других голосов).'], ...
              task_name, numel(voice_list));
    end

    % Полный список .wav-файлов каждого голоса
    voice_files = cell(numel(voice_list), 1);
    for j = 1:numel(voice_list)
        wavs = dir(fullfile(task_path, voice_list{j}, '*.wav'));
        voice_files{j} = {wavs.name};
    end

    % Реф-голосом может быть только голос, у которого записей хватает
    % на n реф + хотя бы 1 auth.
    is_eligible  = cellfun(@(f) numel(f) >= num_ref_data + 1, voice_files);
    eligible_idx = find(is_eligible);
    if numel(eligible_idx) < num_ref_voices
        error('run_multiuser_test:notEnoughRefVoices', ...
              ['Команда "%s": голосов с >= %d записями всего %d, ', ...
               'а требуется %d реф-голосов.'], ...
              task_name, num_ref_data + 1, numel(eligible_idx), num_ref_voices);
    end

    % Случайно выбираем num_ref_voices реф-голосов среди подходящих
    sel = eligible_idx(randperm(numel(eligible_idx), num_ref_voices));

    % ------------------------------------------------------------------
    % 3-4. По каждому реф-голосу: реф / auth / импостеры + верификация
    % ------------------------------------------------------------------
    % Примечание: верификатору осмысленно передаётся только nfft.
    % Поле Method из старого simple_test тут не используется (у Process
    % нет аргумента метода) и вызывало бы warning в mergeParams.
    params      = struct();
    params.nfft = nfft;

    % Агрегированные решения по всем верификаторам
    all_decision_auth = [];
    all_decision_imp  = [];

    % Заготовка структуры с разбивкой по верификаторам
    per_verifier = repmat(struct('voice', '', 'num_ref', 0, 'num_auth', 0, ...
                                 'num_imp', 0, 'FRR', 0, 'FAR', 0, ...
                                 'Accuracy', 0), 1, num_ref_voices);

    for v = 1:num_ref_voices
        ref_voice_idx  = sel(v);
        ref_voice_name = voice_list{ref_voice_idx};
        ref_voice_dir  = fullfile(task_path, ref_voice_name);
        files_here     = voice_files{ref_voice_idx};

        % --- разбиение записей реф-голоса на ref и auth ---
        perm       = randperm(numel(files_here));
        ref_names  = files_here(perm(1:num_ref_data));
        auth_names = files_here(perm(num_ref_data + 1 : end));

        % --- загрузка реф-записей и конфигурация своего верификатора ---
        n_ref = numel(ref_names);
        [ref_data, ref_fs] = deal(cell(n_ref, 1));
        for k = 1:n_ref
            [ref_data{k}, ref_fs{k}] = ...
                audioread(fullfile(ref_voice_dir, ref_names{k}));
        end

        vv = voiceVerifier();
        vv.Configure(ref_data, ref_fs, params);

        % --- проверка auth (свои записи этого голоса) ---
        decision_auth = zeros(1, numel(auth_names));
        for k = 1:numel(auth_names)
            [td, tfs] = audioread(fullfile(ref_voice_dir, auth_names{k}));
            [~, decision_auth(k)] = vv.Process(td, tfs);
        end

        % --- пул импостеров: ВСЕ записи всех ДРУГИХ голосов команды ---
        imp_pool = {};
        for j = 1:numel(voice_list)
            if j == ref_voice_idx
                continue;
            end
            other_dir = fullfile(task_path, voice_list{j});
            imp_pool  = [imp_pool, fullfile(other_dir, voice_files{j})]; %#ok<AGROW>
        end

        % --- выбор импостеров: их число = числу auth этого верификатора ---
        n_imp_target = numel(auth_names);
        n_imp        = min(n_imp_target, numel(imp_pool));
        imp_sel      = imp_pool(randperm(numel(imp_pool), n_imp));

        % --- проверка импостеров (чужие записи) ---
        decision_imp = zeros(1, n_imp);
        for k = 1:n_imp
            [td, tfs] = audioread(imp_sel{k});
            [~, decision_imp(k)] = vv.Process(td, tfs);
        end

        % --- метрики этого верификатора ---
        v_FRR = rate_percent(decision_auth == 0, decision_auth);
        v_FAR = rate_percent(decision_imp  == 1, decision_imp);
        v_Acc = (sum(decision_auth == 1) + sum(decision_imp == 0)) / ...
                max(1, numel(decision_auth) + numel(decision_imp)) * 100;

        per_verifier(v).voice    = ref_voice_name;
        per_verifier(v).num_ref  = n_ref;
        per_verifier(v).num_auth = numel(auth_names);
        per_verifier(v).num_imp  = n_imp;
        per_verifier(v).FRR      = v_FRR;
        per_verifier(v).FAR      = v_FAR;
        per_verifier(v).Accuracy = v_Acc;

        % --- агрегирование решений ---
        all_decision_auth = [all_decision_auth, decision_auth]; %#ok<AGROW>
        all_decision_imp  = [all_decision_imp,  decision_imp];  %#ok<AGROW>
    end

    % ------------------------------------------------------------------
    % 5. Агрегированные метрики по всем верификаторам
    % ------------------------------------------------------------------
    FRR = rate_percent(all_decision_auth == 0, all_decision_auth);
    FAR = rate_percent(all_decision_imp  == 1, all_decision_imp);
    Accuracy = (sum(all_decision_auth == 1) + sum(all_decision_imp == 0)) / ...
               max(1, numel(all_decision_auth) + numel(all_decision_imp)) * 100;

    details.task           = task_name;
    details.ref_voices     = voice_list(sel);
    details.per_verifier   = per_verifier;
    details.num_auth_total = numel(all_decision_auth);
    details.num_imp_total  = numel(all_decision_imp);
end

% ====================================================================
%  Вспомогательные функции
% ====================================================================
function names = list_subdirs(parent, pattern)
% list_subdirs  Имена подпапок parent, подходящих под маску pattern
%               (без '.' и '..'), в виде cell-массива строк.
%               pattern по умолчанию '*' (все подпапки).
    if nargin < 2 || isempty(pattern)
        pattern = '*';
    end
    d = dir(fullfile(parent, pattern));
    if isempty(d)
        names = {};
        return;
    end
    d     = d([d.isdir]);
    names = {d.name};
    names = names(~ismember(names, {'.', '..'}));
end

function r = rate_percent(hit_mask, decisions)
% rate_percent  Доля сработавших элементов маски в процентах.
%               Возвращает 0, если решений нет.
    if isempty(decisions)
        r = 0;
    else
        r = sum(hit_mask) / numel(decisions) * 100;
    end
end
