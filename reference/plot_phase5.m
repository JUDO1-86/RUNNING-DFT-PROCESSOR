% Plots the results of running_dft_top_tb for three refresh settings.
% First run the testbench three times from this folder, with SWAP_PERIOD = 1048576, 512 and 32
% (1048576 = no refresh). Each run writes top_mag_P<value>.csv.
%
% run with:  plot_phase5

function plot_phase5()

    files  = {'top_mag_P1048576.csv', 'top_mag_P512.csv', 'top_mag_P32.csv'};
    labels = {'no refresh', 'swap period 512', 'swap period 32'};
    style  = {'r', 'b', 'g'};

    fig1 = figure('Visible', 'off');
    subplot(2,1,1); hold on;
    subplot(2,1,2); hold on;

    for i = 1:3
        d = readmatrix(files{i});
        r = d(:,1);
        mag = d(:,2);
        ideal = d(:,3);
        cerr = d(:,4);
        valid = r >= 15;                      % skip the first N-1 warm up samples

        subplot(2,1,1);
        plot(r(valid), mag(valid), style{i}, 'DisplayName', labels{i});

        subplot(2,1,2);
        semilogy(r(valid), max(cerr(valid), 1e-9), style{i}, 'DisplayName', labels{i});
        hold on;

        fprintf('%-16s  max |mag - ideal| = %.2e   max complex error = %.2e   last = %.2e\n', ...
                labels{i}, max(abs(mag(valid) - ideal(valid))), max(cerr(valid)), cerr(end));
    end

    subplot(2,1,1);
    title('Normalized magnitude of bin k = 1 (output / K)');
    xlabel('sample r'); ylabel('|F(r,1)|');
    legend('Location', 'best'); grid on;

    subplot(2,1,2);
    title('Complex error against ideal floating point sliding DFT');
    xlabel('sample r'); ylabel('|F - F_{ideal}|');
    legend('Location', 'best'); grid on;

    saveas(fig1, 'phase5_results.png');
    disp('saved phase5_results.png');
end
