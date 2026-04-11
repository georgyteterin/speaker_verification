clear, clc, close all
addpath("source")

% Получение метрик для оргинала
ref_filename = "audio/ref.wav";
[ref_data, ref_fs] = audioread(ref_filename);
ref_features = extract_simple_mfcc(ref_data, ref_fs);

% Получение всех имен тестов

test_folder = "audio/imposters";
testnames = ls(test_folder + "/*.wav");
num_tests = size(testnames, 1);

simple_score_acc = zeros(1, num_tests);
hard_score_acc = zeros(1, num_tests);

result = struct(...
    "euclidean", [], ...
    'dtw', []);

for j_test = 1 : num_tests

    test_filename = test_folder + "/" + testnames(j_test, :);
    
    [test_data, test_fs] = audioread(test_filename);
    test_features = extract_simple_mfcc(test_data, test_fs);
    
    simple_score_acc(1, j_test) = compare_euclidean(test_features, ref_features);
    hard_score_acc(1, j_test) = compare_dtw(test_features, ref_features);

end

result.euclidean = simple_score_acc;
result.dtw = hard_score_acc;

