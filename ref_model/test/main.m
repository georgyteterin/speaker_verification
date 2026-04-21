clear, clc, close all

% ==== Задаем словарь сценариев=====
tests = dictionary(double.empty, string.empty);
tests(1) = "base.json";
% ==== Выбор сценария ====
test_to_run = 1;
% ========================

test_folder = "tests_storage/";
test_name = test_folder + tests(test_to_run);

fid = fopen(test_name, 'r');
raw = fread(fid, inf);
str = char(raw');
fclose(fid);

scenarios = jsondecode(str);
scenario_names = fieldnames(scenarios);
results = cell(1, numel(scenario_names));

for j_scenario = 1 : numel(scenario_names)
    current_scenario  = scenario_names{j_scenario};
    current_config = scenarios.(current_scenario);
    results{1, j_scenario} = scenario_runner(current_config);
end

% addpath ..\examples\
% plot_verification_results(out.res.auth_scores, out.res.imposter_scores, out.params.method);
