function rate=dmt_t2_cycle_rate(cfg,bitsPerSymbol,setupSymbols)
%DMT_T2_CYCLE_RATE One 50k-symbol cycle even when two repeats are pooled.
L=cfg.payload_symbols;
rate=L*bitsPerSymbol/((L+setupSymbols)*cfg.Ts+cfg.control_delay);
end
