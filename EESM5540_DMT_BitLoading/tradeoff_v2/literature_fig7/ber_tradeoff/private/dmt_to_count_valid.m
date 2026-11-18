function [ok,reason] = dmt_to_count_valid(errors,tested,M,nSymbols)
%DMT_TO_COUNT_VALID Pure exact-counter audit; performs no signal simulation.
% Synthetic counter examples may exercise this function in mechanical checks.
ok=false; reason='';
if ~(isnumeric(M) && isreal(M) && iscolumn(M) && ~isempty(M) && ...
        all(isfinite(M) & M>=2 & M==fix(M)) && all(log2(M)==fix(log2(M))))
    reason='Current modulation table is not a valid carrier column.'; return;
end
if ~(isnumeric(nSymbols) && isreal(nSymbols) && isscalar(nSymbols) && ...
        isfinite(nSymbols) && nSymbols>=1 && nSymbols==fix(nSymbols))
    reason='Actual symbol count is missing or invalid.'; return;
end
if ~(isnumeric(errors) && isnumeric(tested) && isreal(errors) && isreal(tested) && ...
        isequal(size(errors),size(M)) && isequal(size(tested),size(M)))
    reason='Error/tested counters must have one entry per independent carrier.'; return;
end
if (isa(errors,'uint64') && any(errors>uint64(flintmax))) || ...
        (isa(tested,'uint64') && any(tested>uint64(flintmax))) || ...
        (isa(errors,'int64') && any(errors>int64(flintmax))) || ...
        (isa(tested,'int64') && any(tested>int64(flintmax)))
    reason='Counters exceed the exactly representable integer range.'; return;
end
e=double(errors); n=double(tested); expected=double(nSymbols)*log2(double(M));
if ~(all(isfinite(e) & isfinite(n)) && all(e>=0 & e==fix(e) & e<=n) && ...
        all(n>0 & n==fix(n) & n==expected) && all(e<=flintmax & n<=flintmax))
    reason='Counters must be exact integers matching current M and actual symbols.'; return;
end
ok=true; reason='Exact raw bit/error counters match actual symbols and current modulation.';
end
