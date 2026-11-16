% Floating point reference model for the running DFT project
% - sliding DFT (eq. 2 of the paper) vs direct DFT of every window
% - test signal x(n) = sum_{k=1..7} sin(n*theta_k), N = 16
% - warm-up check for a PE that has just been refreshed (reset to zero)
% - writes the input samples as hex files for $readmemh
%
% run with:  running_dft_reference

function running_dft_reference()

    N     = 16;
    K     = 1;          % bin to monitor
    NSAMP = 2048;
    SCALE = 1/8;        % test signal peaks near 5, scale down for accumulator headroom

    s = test_signal(NSAMP, N, SCALE);
    fprintf('signal peak (scaled) = %.3f\n', max(abs(s)));

    % 1. sliding vs direct (MATLAB index = r+1, since r starts at 0)
    F = sliding_dft(s, K, N);
    F_direct = zeros(1, NSAMP);
    for r = N-1 : NSAMP-1
        F_direct(r+1) = direct_dft(s, r, K, N);
    end
    err = max(abs(F(N:end) - F_direct(N:end)));
    fprintf('max |sliding - direct| = %.3e   (should be ~1e-13)\n', err);

    % 2. magnitude of bin K (ideal = N/2 * SCALE * 2 = 1 for this signal)
    mag = abs(F(N:end));
    fprintf('|F(r,%d)| min/max = %.6f / %.6f\n', K, min(mag), max(mag));

    % 3. warm-up check after a refresh
    r0 = 1000;
    good = refreshed_pe(s, K, r0, true,  N);
    bad  = refreshed_pe(s, K, r0, false, N);
    idx  = (r0 + N) : NSAMP;          % samples after the warm-up
    e_good = max(abs(good(idx) - F(idx)));
    e_bad  = max(abs(bad(idx)  - F(idx)));
    fprintf('refreshed PE error after warm-up, with mask    = %.3e\n', e_good);
    fprintf('refreshed PE error after warm-up, without mask = %.3e\n', e_bad);

    % 4. files for the testbench
    write_hex('input_re.hex', s);
    write_hex('input_im.hex', zeros(1, NSAMP));
    r = 0 : NSAMP-1;
    fid = fopen('golden_float.csv', 'w');
    fprintf(fid, 'r,re,im,mag\n');
    fprintf(fid, '%d,%.12f,%.12f,%.12f\n', [r; real(F); imag(F); abs(F)]);
    fclose(fid);
    disp('wrote input_re.hex, input_im.hex, golden_float.csv');

    % 5. plots
    fig = figure('Visible', 'off');
    subplot(2,1,1);
    plot(s(1:64));
    title('test signal (scaled by 1/8)');
    subplot(2,1,2);
    plot(N-1 : NSAMP-1, mag);
    title(sprintf('|F(r,%d)| floating point', K));
    xlabel('r');
    saveas(fig, 'reference_plot.png');
end


function s = test_signal(nsamp, N, scale)
    n = 0 : nsamp-1;
    s = zeros(1, nsamp);
    for k = 1:7
        s = s + sin(n * 2*pi*k/N);
    end
    s = s * scale;
end


function Fr = direct_dft(s, r, k, N)
    % F(r,k) = sum_{n=0}^{N-1} s(n + r - N + 1) * exp(-j*theta*n)
    window = s(r-N+2 : r+1);          % samples r-N+1 ... r
    n = 0 : N-1;
    Fr = sum(window .* exp(-1j * 2*pi*k*n/N));
end


function F = sliding_dft(s, k, N)
    % F(r) = [F(r-1) + s(r) - s(r-N)] * exp(j*theta)
    th = 2*pi*k/N;
    F = zeros(1, length(s));
    prev = 0;
    for i = 1:length(s)
        if i > N
            old = s(i-N);
        else
            old = 0;
        end
        prev = (prev + s(i) - old) * exp(1j*th);
        F(i) = prev;
    end
end


function F = refreshed_pe(s, k, r0, mask, N)
    % PE that is reset (F = 0) just before sample r0.
    % mask = true : for the first N samples only s(r) is added
    % mask = false: s(r-N) is always subtracted, even though this PE never added it
    th = 2*pi*k/N;
    F = zeros(1, length(s));
    prev = 0;
    for r = r0 : length(s)-1
        old = s(r-N+1);
        if mask && (r - r0) < N
            old = 0;
        end
        prev = (prev + s(r+1) - old) * exp(1j*th);
        F(r+1) = prev;
    end
end


function write_hex(name, x)
    % Q1.15, two's complement, one 4 digit hex value per line
    q = round(x * 32768);
    q = max(min(q, 32767), -32768);
    q = mod(q, 65536);
    fid = fopen(name, 'w');
    fprintf(fid, '%04x\n', q);
    fclose(fid);
end
