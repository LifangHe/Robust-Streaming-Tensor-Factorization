
% This file is part of OLSTEC package.
%
% Created by H.Kasai on June 13, 2017
clc;
clear;
close all;

% set running flags
image_display_flag  = true;
store_matrix_flag   = true;
permute_on_flag     = false;
maxepochs           = 1;
verbose             = 2;
tolcost             = 1e-8;

fraction            = 1;

% set dataset
data_type   = 'static';%'static'; % 'dynamic';
if strcmp(data_type, 'static')
    %file_path   =  './dataset/hall/hall_144x100_frame2900-3899.mat';
    file_path   =  './OLSTEC-master/dataset/hall/hall1-200.mat';
    tensor_dims = [144, 176, 50];
else
    file_path   =  './OLSTEC-master/dataset/hall/hall_144x100_frame2900-3899_pan.mat';
    tensor_dims = [144, 100, 500];
end

% set paramters
max_rank                = 15;

% load tensor (and equivalent matrix)
[Tensor_Y_Noiseless, Tensor_Y_Noiseless_Normalized, Tensor_Y_Normalized, OmegaTensor, ...
    Matrix_Y_Noiseless, Matrix_Y_Noiseless_Normalized, Matrix_Y_Normalized, OmegaMatrix, ...
    rows, cols, total_slices, Normalize_Ratio] = load_realdata_tensor(file_path, tensor_dims, fraction);

% revise tensor_dims
tensor_dims(1) = rows;
tensor_dims(2) = cols;
tensor_dims(3) = total_slices;

% set paramter for matrix case
numr = tensor_dims(1) * tensor_dims(2);
numc = tensor_dims(3);

% calculate matrix rank
num_params_of_tensor = max_rank * sum(tensor_dims,2);
matrix_rank = floor( num_params_of_tensor/ (numr+numc) );
if matrix_rank < 1
    matrix_rank = 1;
end

% generate init data
Xinit.A = randn(tensor_dims(1), max_rank);
Xinit.B = randn(tensor_dims(2), max_rank);
Xinit.C = randn(tensor_dims(3), max_rank);


% CPOPT (batch)
clear options;
options.maxepochs       = maxepochs;
options.display_iters   = 1;
options.store_subinfo   = true;
options.store_matrix    = store_matrix_flag;
options.verbose         = verbose;

tic;
[Xsol_cp_wopt, info_cp_wopt, sub_infos_cp_wopt] = cp_wopt_mod(Tensor_Y_Noiseless, OmegaTensor, [], tensor_dims, max_rank, Xinit, options);
elapsed_time_cpwopt = toc;

% TeCPSGD
clear options;
options.maxepochs       = maxepochs;
options.tolcost         = tolcost;
options.lambda          = 0.001;
options.stepsize        = 0.1;
options.mu              = 0.05;
options.permute_on      = permute_on_flag;
options.store_subinfo   = true;
options.store_matrix    = store_matrix_flag;
options.verbose         = verbose;

tic;
[Xsol_TeCPSGD, info_TeCPSGD, sub_infos_TeCPSGD] = TeCPSGD(Tensor_Y_Noiseless, OmegaTensor, [], tensor_dims, max_rank, Xinit, options);
elapsed_time_tecpsgd = toc;


% OLSTEC
clear options;
options.maxepochs       = maxepochs;
options.tolcost         = tolcost;
options.permute_on      = permute_on_flag;
options.lambda          = 0.7;  % Forgetting paramter
options.mu              = 0.1;  % Regualization paramter
options.tw_flag         = 1;    % 0:Exponential Window, 1:Truncated Window (TW)
options.tw_len          = 10;   % Window length for Truncated Window (TW) algorithm
options.store_subinfo   = true;
options.store_matrix    = store_matrix_flag;
options.verbose         = verbose;

tic;
[Xsol_olstec, infos_olstec, sub_infos_olstec] = olstec(Tensor_Y_Noiseless, OmegaTensor, [], tensor_dims, max_rank, Xinit, options);
elapsed_time_olstec = toc;
%%
% BRST

forgetting_factor = .98;
sliding_window_size = 20;

sub_infos_brst = brst_wrapper(Tensor_Y_Noiseless,fraction,forgetting_factor,sliding_window_size,max_rank);
disp('job done')
%%
save('Video_Factorization_rank15')

%%
figure;
hold on;
semilogy(sub_infos_TeCPSGD.inner_iter, sub_infos_TeCPSGD.err_run_ave, '-b', 'linewidth', 2.0);
semilogy(sub_infos_olstec.inner_iter, sub_infos_olstec.err_run_ave, '-r', 'linewidth', 2.0);
semilogy(sub_infos_brst.inner_iter, sub_infos_brst.err_run_ave, '-g', 'linewidth', 2.0);
hold off;
grid on;
legend('TeCPSGD', 'OLSTEC','Proposed', 'location', 'best');
%legend('TeCPSGD', 'OLSTEC');
ax1 = gca;
set(ax1,'FontSize',fs);
xlabel('data stream index','FontName','Arial','FontSize',fs,'FontWeight','bold');
ylabel('running average error','FontName','Arial','FontSize',fs,'FontWeight','bold');

%% Display images
observe = 100 * (1 - fraction);
if image_display_flag
    figure;
    width = 5;
    height = 3;
    for i=1:total_slices
        
        display_images(rows, cols, observe, height, width, 1, i, sub_infos_TeCPSGD, 'TeCPSGD',0);
        display_images(rows, cols, observe, height, width, 3, i, sub_infos_olstec, 'OLSTEC',0);
        display_images(rows, cols, observe, height, width, 5, i, sub_infos_brst, 'Proposed',1);
        pause(0.1);
    end
end


function display_images(rows, cols, observe, height, width, test, frame, sub_infos, algorithm,proposed_flag)

if(proposed_flag)
   
    
    subplot(height, width, 1 + (test-1));
    imagesc(sub_infos.I(:,:,frame));
    colormap(gray);axis image;axis off;
    title([algorithm, ': ', num2str(observe), '% missing']);
    
    subplot(height, width, width + 1 + (test-1));
    imagesc(sub_infos.L(:,:,frame));
    colormap(gray);axis image;axis off;
    title(['Low-rank image: f = ', num2str(frame)]);
    
    
    
else
    
    
    subplot(height, width, 1 + (test-1));
    imagesc(reshape(sub_infos.I(:,frame),[rows cols]));
    colormap(gray);axis image;axis off;
    title([algorithm, ': ', num2str(observe), '% missing']);
    
    subplot(height, width, width + 1 + (test-1));
    imagesc(reshape(sub_infos.L(:,frame),[rows cols]));
    colormap(gray);axis image;axis off;
    title(['Low-rank image: f = ', num2str(frame)]);
    
    subplot(height, width, 2*width + 1 + (test-1));
    imagesc(reshape(sub_infos.E(:,frame),[rows cols]));
    colormap(gray);axis image;axis off;
    title(['Residual image: error = ', num2str(sub_infos.err_residual(frame))]);
    
    
end


end












