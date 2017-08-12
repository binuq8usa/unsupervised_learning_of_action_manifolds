%% Script for evaluating using the trained CRBM and Auto-encoder models.
% Written and copyrighted by Binu M Nair
% Date : 01/20/2015

%%%%%%%%%%% Action Segment detection (Action localization) %%%%%%%%%%%%
% Here, a L-frame segment is classified as an action or non-action using
% the trained auto-encoder and CRBM models. 
% Here, an action label is given to a temporal window of length L frames.

% Within the L frames, each frame is associated with either a codeword or a
% background label ( from output of SVM classifier). Consecutive frames with
% background labels from SVM classifier are removed. Consecutive frames
% associated with the same codeword are also removed which gives us 
% or L_M manifold steps. Within this L_M manifold steps (temporal
% window of codewords), a shorter window of L'=3*nt is taken. If L'> L_M,
% then increase L frames to alpha*L frames and repeat till L' <= L_M
% frames. 
% nt is the number of time steps that the CRBM looks at. The first
% 2*nt frames are used to initialize the CRBM and the next nt frames in
% that L' shorter window is generated by the CRBM. The generated codewords
% in the next 'nt' instants of the manifold are then projected back into the
% original feature space and compared with the true features to compute the
% error for each action class. For now, this error computation is done only
% at the testing phase. Now, this shorter window is shifted by one position
% in the larger window L_M and the process is repeated. The errors are
% accumulated for the larger temporal window length L_M and the errors are
% accumulated for each action class. 
% Now, the action class obtained for the L frames of the sequence. What is
% it associated with it? Segment? How much length segment?


%The larger temporal window of length
% L_M is associated with the temporal window of length L frames and the
% action label obtained can be annotated for first L_shift frames. In the
% next iteration, the L-frame window is shifted by L_shift frames. 

% CLassify L-frame segment seperately and compute
% the action localization statistic : action segment overlap measure with
% ground truth. Moreover, an accumulated action classification stat can be
% computed by considering these segments as independent. 

%%%%%%%%%%% Features for training and testing %%%%%%%%%%%%%%%%
% The features for training and testing are stored in 'Features_train' and
% 'Features_test'. For now, 'Features_test' contain only the sub-sequences
% where a person is present. This is suitable for finding the action labels
% per frame.

clear all; clc;
% Adding the path
addpath(genpath('/home/roshni.uppala/Documents/MATLAB/Binu_Dissertation/Algorithm/'))

% load training file params 
training_params_filename = sprintf('Training_Params_UCF.mat');
load(training_params_filename);

% load the background and foreground features
load ForegroundFeatures_UCF;

[num_of_actions,num_of_total_seqs] = size(Features);
flag_full_seq = true;

% Iterating through each run
for rr = 1
    
    % load the test index and the stacked auto-encoders
    sae_filename = sprintf('SAE_Workspace_Run%d_OptimalAuto_UCF.mat',rr);
    load(sae_filename);
    
    % Load the clusters for this run
    clusters_filename = sprintf('Cluster_Workspace_Run%d_OptimalAuto_UCF.mat',rr);
    load(clusters_filename);
    
    % Load the CRBM trained classifiers
    crbm_filename = sprintf('CRBM_Workspace_Run%d_OptimalAuto_UCF.mat',rr);
    load(crbm_filename);
    
    % set the required test parameters
    nt = opts_crbm_per_action{1}.nt;
    %L = 30; % temporal window length of the sequence
    % if complete sequence, set L as the number of test frames
    L_dash = 3*nt; % minimum number of distinct codeword transitions within L
    L_shift = 2*nt;
     
    [num_of_actions,num_of_test_seqs] = size(Features_test);
    
    % some form of result structure which stores the segment/overlap result
    % It labels the entire L frames of the sequence as an action class
    % It does not label a single frame as an action class
    % The distances to each action class from the generated set of frames
    % from a trained CRBM model are computed and used in the final decision
    % of the action associated with L frames.
    results.action_class_L_framewindow = zeros(num_of_actions,num_of_actions);
    
    est_labels_full_seq = cell(num_of_actions,num_of_test_seqs);
    est_results = zeros(num_of_actions,num_of_actions);
    tId_CRBMTest = tic;
    % Iterating through each sub-sequence
    for seq_row = 1:num_of_actions
        for seq_num = 1:num_of_test_seqs %1:1:(num_of_test_seqs/(num_of_sets))
            
            % accumulate the frames of a single sequence belonging to one
            % set and one person : There are 16 subsequences
%             test_seqs_all = Features_test(seq_row,(seq_num-1)*num_of_sets+1:seq_num*num_of_sets);
%             test_seqs_all = test_seqs_all';
%             test_seq = cell2mat(test_seqs_all);
            test_seq = Features_test{seq_row,seq_num};
            
            % check if sequence is empty
            if(isempty(test_seq))
                continue;
            end
            num_of_test_frames = size(test_seq,1);
            
            %if(flag_full_seq || (L > num_of_test_frames))
            L = num_of_test_frames; % set the window length as that temporal window
            %end
            
            % Now, to simulate the streaming sequence 
            % Taking every L frames with a shift of L_shift
            dist_of_temp_win = zeros(num_of_actions,length(L:L_shift:num_of_test_frames));
            win_count = 0;
            % set L a
            
            for kl = L:L_shift:num_of_test_frames
                
                win_count = win_count + 1;
                % get the L frames
                test_seq_loc = test_seq(kl-L+1:1:kl,:);

                action_detected = ones(L,1);
                
                % TODO: Check if there are consecutive background labels detected
                % for L_shift frames
                flag_consecutive_bg = false;
                
                % Proceed with finding appropriate codewords for frames
                % with foreground detected
                if(~flag_consecutive_bg)
                    % get the frames with only foreground
                    id_fg = find(action_detected == 1);
                    
                    % number of foreground segments detected
                    % here, if number of detected foreground frames are
                    % less than L/2 frames, no point in analyzing it
                    num_detected_fg = length(id_fg);
                    if(num_detected_fg < 3*L/4)  
                        continue;
                    end
                    
                    test_seq_loc = test_seq_loc(id_fg,:);
                    num_of_test_frames_fg = size(test_seq_loc,1);
                    
                    % Find the corresponding cluster to each frame
                    [ids,dis] = yael_nn(single(global_C'),single(test_seq_loc'));
                    
                    % Replace each frame with the codeword. No removal of duplicate
                    % codewords here
                    X_test = zeros(num_of_test_frames_fg,size(test_seq,2));
                    for k = 1:1:num_of_test_frames_fg
                        X_test(k,:) = global_C(ids(k),:);
                    end
                    
                    % Remove consecutive duplicate codewords in the sequences
                    last_codeword_encoun = X_test(1,:);
                    dup_ids = zeros(num_of_test_frames_fg,1);
                    for k = 2:1:num_of_test_frames_fg
                        sum_dist = sum(sum((last_codeword_encoun - X_test(k,:)).^2));
                        if(sum_dist == 0) % duplicate : no change in last_codeword seen
                            dup_ids(k) = 1;
                        else % if no duplicate
                            last_codeword_encoun = X_test(k,:);
                        end
                    end
                    non_dup_ids = (~dup_ids);
                    rel_ids = find(non_dup_ids ~= 0);

                    X_test = X_test(rel_ids,:);
                    L_M = size(X_test,1); % num_frames_gen in this file
                    
                    % check if number of distinct transitions between
                    % codewords is smaller than the minimum length
                    if(L_M < L_dash)
                        % here, increase L by a significant amount
                        % go to next shift
                        continue;
                    end
                    
                    % Apply the set of distinct codewords detected in L
                    % frames to the set of action models
                    dist_to_each_action = zeros(num_of_actions,L_M);
                    for act_num = 1:num_of_actions
                        
                        % get the corresponding auto-encoder
                        st = sae{act_num};
                        crbm_local = crbm{act_num};
                        
                        % apply to the auto-encoder of action class
                        % 'act_num'
                        [X_test_out, a_X_test_out] = sae_nn_ff(st,X_test);
                        
                        % Normalizing the data to pass it to CRBM
                        a_X_test_out_norm = (a_X_test_out - repmat(crbm_local.data_mean,L_M,1))./(repmat(crbm_local.data_std,L_M,1));
                        
                        crbm_local.numGibbs = 1000;
                        
                        % Applying the crbm 
                        for start_fr_num = 1:1:L_M-L_dash+1
                            [a_X_test_out_rec_norm,hidden1,hidden2] = testCRBM(crbm_local,L_dash,a_X_test_out_norm,start_fr_num);

                            % get the unnormalized version from the regenerated sequence
                            a_X_test_out_rec = (a_X_test_out_rec_norm .* repmat(crbm_local.data_std,L_dash,1)) + repmat(crbm_local.data_mean,L_dash,1);

                            % apply the decoder
                            X_test_out_rec = sae_ff_nn_decoder(st,a_X_test_out_rec);
                            X1 = X_test(start_fr_num+2*nt:1:L_dash + start_fr_num-1,:);
                            X2 = X_test_out_rec(2*nt+1:L_dash,:);
                            
                            dist1 = slmetric_pw(X1',X2','chisq');
                            dist2 = diag(dist1); % only taking measures at the same frame instances
                            dist_to_each_action(act_num,L_dash+start_fr_num-1)= sum(dist2);

                            %dist_to_each_action(act_num,L_dash+start_fr_num-1) = sum(sum((X_test(start_fr_num+2*nt:1:L_dash + start_fr_num-1,:) - X_test_out_rec(2*nt+1:L_dash,:)).^2));

                        end
                    end
                    
                    % Now we get dist_to_each action for every 15 codeword
                    % window within the L_M set of distinct codewords
                    % after observing 3*nt=15 codewords at an instant within the
                    % L_M set of codewords, the action labels 
                    
                    dist_of_temp_win(:,win_count) = (sum(dist_to_each_action(:,L_dash:L_M).^2, 2))/(length(L_dash:L_M));
                    
                else
                    % set the result of the consecutive frames as zero
                    % label or background
                    % go to next shift
                    continue;
                end
                
                %fprintf('Finished testing window %d out of %d of seq %d-%d out of %d-%d\n',win_count,length(L:L_shift:num_of_test_frames),seq_row,seq_num,num_of_actions,num_of_test_seqs);
                
            end
            
            % Now, find the action class label for each window 
            % This is just to confirm if the labels for each action class
            % are appropriate.
            [mi,id] = min(dist_of_temp_win);
            %true_class = seq_row;
            
%             for k = 1:1:length(id)
%                 est_class = id(k);
%                 est_labels_full_seq(seq_row,seq_num) = est_class;
%                 %results.action_class_L_framewindow(true_class,est_class) = results.action_class_L_framewindow(true_class,est_class) + 1;
%             end
            est_labels_full_seq{seq_row,seq_num} = id;
            fprintf('\nFinished testing seq %d-%d\n', seq_row,seq_num);
            
        end
    end
    
    timeToTestCRBM = toc(tId_CRBMTest);
    
    % accumulate the labels
    for seq_row = 1:1:num_of_actions
        for seq_num = 1:1:num_of_test_seqs
            est_class = est_labels_full_seq{seq_row,seq_num};
            results.action_class_L_framewindow(seq_row,est_class) = results.action_class_L_framewindow(seq_row,est_class) + 1;
        end
    end
    
    results.action_class_L_framewindow_percent = results.action_class_L_framewindow * 100 ./( repmat(sum(results.action_class_L_framewindow,2),1,num_of_actions) );
    
    fprintf('Test for Prediction Accuracy of CRBM Completed in %f hours\n',timeToTestCRBM/3600);
   
    results_phase3 = results;
    if(flag_full_seq)
        results_filename = sprintf('Results_Phase3_Action_PredictionAccuracy_Run%d_CRBMSizes_%d_nt_%d_fullseq_UCF.mat',rr,opts_crbm_per_action{1}.sizes(1),opts_crbm_per_action{1}.n{1});
        save(results_filename,'results_phase3');
    else
        results_filename = sprintf('Results_Phase3_Action_Classification_Run%d_L_%d_UCF.mat',rr,L);
        save(results_filename,'results_phase3');
    end
    
    fprintf('\nTesting Completed for run %d for CRBM %d with nt %d\n',rr,opts_crbm_per_action{1}.sizes(1),opts_crbm_per_action{1}.n{1});
end
