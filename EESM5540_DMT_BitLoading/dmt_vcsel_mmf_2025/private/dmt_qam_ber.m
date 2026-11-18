function p = dmt_qam_ber(M, gamma)
% Nearest-neighbour square Gray-QAM BER approximation, Es/N0 convention.
% erfc is Base MATLAB; no Statistics Toolbox or qfunc dependency.
p = 4./log2(M).*(1-1./sqrt(M)).* ...
    (0.5*erfc(sqrt(3*gamma./(M-1))/sqrt(2)));
end
