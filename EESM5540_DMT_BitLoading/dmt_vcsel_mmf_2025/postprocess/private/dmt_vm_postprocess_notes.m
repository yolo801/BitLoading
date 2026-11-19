function dmt_vm_postprocess_notes(path,cfg,tables)
%DMT_VM_POSTPROCESS_NOTES Write the Chinese interpretation of audited formal tables.
% This postprocessor never touches waveform generation or frozen decisions.
tables=normalize(tables);
assert(cfg.payload_symbols==25000 && cfg.payload_repeats==2 && ...
    cfg.calibration_count==5 && cfg.Ts==(cfg.NFFT+cfg.NCP)/cfg.Fs, ...
    'DMT:VMNotesConfig','Formal configuration or symbol timing was inconsistent.');
fid=fopen(path,'wt','n','UTF-8');
assert(fid>=0,'DMT:VMFigureNotes','Cannot write the UTF-8 Chinese report.');
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'# VCSEL–MMF DMT 正式结果\n\n');
writeAcquisition(fid,cfg,tables.status,tables.power_adc);
writeWorkPoints(fid,cfg,tables);
writeSelectivity(fid,cfg,tables);
writeLengthSensitivity(fid,cfg,tables.length_sensitivity);
writeConditionTable(fid,tables.scenario);
fprintf(fid,['\n本实验以公开的两条 50 m VCSEL–MMF 模型响应幅度为依据，沿用统一的频带、噪声和 8 bit ADC 模型。' ...
    '速率采用仿真的采样时钟。ADSL2 与 VDSL2 展示了按频点分配比特的实际用途，' ...
    '本实验的两种策略则始终使用同一个活跃载波集合。\n\n']);
fprintf(fid,'<!-- VCSEL_POSTPROCESS_COMPLETE -->\n');
end

function writeAcquisition(fid,cfg,status,power)
states=["completed","design_rejected","power_error","execution_error","incomplete"];
assert(height(status)==120 && all(ismember(status.status,states)), ...
    'DMT:VMNotesStatus','Unexpected formal slot budget or acquisition state.');
counts=zeros(size(states));
for k=1:numel(states),counts(k)=sum(status.status==states(k));end
sent=counts(1);
assert(all(status.actual_symbols(status.status=="completed")==cfg.payload_symbols));
fprintf(fid,['正式计划 %d 槽。已发送 %d 槽，设计正常拒绝 %d 槽，功率错误 %d 槽，' ...
    '执行错误 %d 槽，其他未完成 %d 槽。设计正常拒绝表示候选未获发送许可。\n\n'], ...
    height(status),sent,counts(2),counts(3),counts(4),counts(5));
if sent==0
    assert(isempty(power));
    fprintf(fid,'本批没有载荷发送，因此没有削波率分母。\n\n');
    return;
end
key={'condition_id','calibration_id','strategy','payload_slot'};
[~,i]=sortrows(power,key);
[~,j]=sortrows(status(status.status=="completed",:),key);
completed=status(status.status=="completed",:);
assert(height(power)==sent && isequal(power(i,key),completed(j,key)), ...
    'DMT:VMNotesPower','Optical counters do not match the sent slots.');
samples=power.samples;
clipped=power.tx_low_count+power.tx_high_count;
assert(all(samples==cfg.payload_symbols*(cfg.NFFT+cfg.NCP)) && ...
    all(power.tx_low_count>=0 & power.tx_low_count==fix(power.tx_low_count)) && ...
    all(power.tx_high_count>=0 & power.tx_high_count==fix(power.tx_high_count)) && ...
    all(clipped<=samples),'DMT:VMNotesPower','Invalid sample or TX clip counters.');
n=sum(samples);
e=sum(clipped);
assert(n>0 && n<=flintmax && e<=n && n==sent*cfg.payload_symbols*(cfg.NFFT+cfg.NCP));
fprintf(fid,['已发送的正式载荷共 %.0f 个含 CP 的发射样本（约 %.3g 亿个），其中 %.0f 个发生 TX 削波，' ...
    '比例为 %.6g（%.6g%%）。'],n,n/1e8,e,e/n,100*e/n);
fprintf(fid,['本批记录的发射削波用于描述这些工作点的观测情况。' ...
    '仅凭这些样本不足以单独评估削波对 BER 或速率的惩罚。实验没有测量硬件成本或电功耗。\n\n']);
end

function writeWorkPoints(fid,cfg,t)
fprintf(fid,'## 两个工作点的承载量、速率与真实配置开销\n\n');
fprintf(fid,['每次配置后的主载荷长度为 %d 个 DMT 符号。名义载荷速率为每符号比特数除以含 CP 的符号时长 %.3f ns。' ...
    '周期速率计入已实际发出的探测、训练和全部候选验证。两槽载荷是独立统计重复。' ...
    '发射机本地标定的时间在事件表单列。本批设定理想反馈延迟 %.3g 秒。' ...
    '比特和速率用两槽均实发轮次的中位数及范围表示。配置开销也计入最终被拒的实际尝试。达标轮数另列。\n\n'], ...
    cfg.payload_symbols,cfg.Ts*1e9,cfg.control_delay);
points=[1 .25;2 .5];
strategies=["UniformValidated","PerToneValidated"];
fprintf(fid,['| 频响、指令摆幅 | 策略 | 实发 / 达标轮数 | bit/DMT 符号 | 名义载荷速率 (Gbit/s) | ' ...
    '周期速率 (Gbit/s) | 从名义到周期的下降 (Gbit/s) | 下降比例 | 配置时间 (µs) | 候选尝试 |\n' ...
    '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n']);
for p=1:size(points,1)
    c=points(p,1);
    a=points(p,2);
    point=atPoint(t.summary,c,a);
    for b=1:numel(strategies)
        strategy=strategies(b);
        rows=point(point.strategy==strategy,:);
        assert(height(rows)==cfg.calibration_count && numel(unique(rows.calibration_id))==height(rows));
        inserted=rowStats(rows,atPoint(t.profiles,c,a),atPoint(t.overhead,c,a),cfg);
        fprintf(fid,'| Case %d，%.2f | %s | %d/%d，%d/%d | %s | %s | %s | %s | %s | %s | %s |\n', ...
            c,a,word(strategy),inserted.sent,cfg.calibration_count,nnz(rows.state=="supported"), ...
            cfg.calibration_count,span(inserted.bits,0,''),span(inserted.nominal/1e9,3,''), ...
            span(inserted.cycle/1e9,3,''),span((inserted.nominal-inserted.cycle)/1e9,3,''), ...
            span(100*(1-inserted.cycle./inserted.nominal),2,'%'), ...
            span(inserted.setup*1e6,3,''),span(inserted.attempts,0,''));
    end
end
fprintf(fid,['\n候选尝试和配置时间对应实际发出的块。表中少于五轮达标的条件保留各轮的鉴别结果。' ...
    '两策略尝试次数的差异取决于本协议、工作点与各轮实际验证路径。\n\n']);

for p=1:size(points,1)
    c=points(p,1);
    a=points(p,2);
    rows=atPoint(t.pair_gains,c,a);
    assert(height(rows)==cfg.calibration_count && numel(unique(rows.calibration_id))==height(rows));
    paired=rows(rows.pair_qualified,:);
    if isempty(paired)
        fprintf(fid,'Case %d、%.2f 没有同时符合 BER 和资源匹配要求的可比较轮次。\n\n',c,a);
        continue;
    end
    assert(all(paired.resource_match) && all(paired.uniform_state=="supported" & paired.pertone_state=="supported"));
    uniform=paired.uniform_bits_per_symbol;
    pertone=paired.pertone_bits_per_symbol;
    assert(all(uniform>0 & pertone>0 & uniform==fix(uniform) & pertone==fix(pertone)));
    delta=pertone-uniform;
    gain=100*delta./uniform;
    rateDelta=paired.pertone_R_cycle-paired.uniform_R_cycle;
    same(rateDelta,paired.validated_delta_R_cycle,'paired cycle gain');
    fprintf(fid,['Case %d、%.2f 有 %d/%d 轮满足两策略 BER 与资源匹配判据。' ...
        '逐载波选阶相对统一选阶的承载量差为 %s bit/DMT 符号（%s），周期速率差为 %s Gbit/s。' ...
        '对应配置时间差为 %s µs。\n\n'],c,a,height(paired),cfg.calibration_count, ...
        span(delta,0,''),span(gain,2,'%'),span(rateDelta/1e9,3,''), ...
        span((paired.pertone_T_setup_s-paired.uniform_T_setup_s)*1e6,3,''));
end
end

function values=rowStats(rows,profiles,overhead,cfg)
assert(all(rows.payload_slots_completed==0 | rows.payload_slots_completed==cfg.payload_repeats), ...
    'DMT:VMNotesRepeats','Formal report requires a resolved pair of payload slots.');
measured=rows(rows.payload_slots_completed==cfg.payload_repeats,:);
n=height(measured);
values=struct('sent',n,'bits',zeros(n,1),'nominal',zeros(n,1),'cycle',zeros(n,1), ...
    'setup',zeros(height(rows),1),'attempts',zeros(height(rows),1));
for i=1:height(rows)
    r=rows(i,:);
    taken=keyRows(overhead,r);
    assert(height(taken)==1);
    blocks=[taken.A0_symbols(1),taken.B0_symbols(1),taken.Ar_symbols(1),taken.Dr_symbols(1)];
    attempts=taken.attempts(1);
    assert(all(isfinite(blocks) & blocks>=0 & blocks==fix(blocks)) && ...
        isfinite(attempts) && attempts>=0 && attempts==fix(attempts));
    setup=sum(blocks)*cfg.Ts+cfg.control_delay;
    assert(sum(blocks)==r.setup_symbols(1) && attempts==r.attempts(1));
    same(taken.T_setup_s(1),setup,'overhead setup time');
    same(r.T_setup_s(1),setup,'summary setup time');
    values.setup(i)=setup;
    values.attempts(i)=attempts;
end
for i=1:n
    r=measured(i,:);
    frozen=keyRows(profiles,r);
    assert(height(frozen)==numel(cfg.k) && isequal(sort(frozen.k),sort(cfg.k(:))) && ...
        all(ismember(frozen.M,cfg.Mset)), ...
        'DMT:VMNotesProfile','Payload uses a missing or ambiguous modulation table.');
    bits=sum(log2(frozen.M));
    assert(bits==r.bits_per_symbol(1) && bits>0 && bits==fix(bits));
    setup=r.T_setup_s(1);
    nominal=bits/cfg.Ts;
    cycle=cfg.payload_symbols*bits/(cfg.payload_symbols*cfg.Ts+setup);
    same(r.R_nominal(1),nominal,'nominal rate');
    same(r.R_cycle(1),cycle,'cycle rate');
    values.bits(i)=bits;
    values.nominal(i)=nominal;
    values.cycle(i)=cycle;
end
end

function writeSelectivity(fid,cfg,t)
ref=cfg.representative;
target=atPoint(t.summary,ref.case_id,ref.swing);
target=target(target.calibration_id==ref.calibration_id,:);
profiles=atPoint(t.profiles,ref.case_id,ref.swing);
profiles=profiles(profiles.calibration_id==ref.calibration_id,:);
assert(height(target)==2 && isscalar(cfg.case2_notch_GHz) && isfinite(cfg.case2_notch_GHz));
fprintf(fid,'## 频率选择性与正式载荷误码\n\n');
fprintf(fid,['图 B 使用 Case %d、摆幅 %.2f、第 %d 轮。源幅度曲线的预定陷波在约 %.2f GHz。' ...
    '正式 BER 从该轮两槽的整数计数合并，零观察误码点显示逐点 95%% Wilson 上限。'], ...
    ref.case_id,ref.swing,ref.calibration_id,cfg.case2_notch_GHz);
names=["UniformValidated","PerToneValidated"];
for j=1:numel(names)
    row=target(target.strategy==names(j),:);
    profile=profiles(profiles.strategy==names(j),:);
    assert(height(row)==1);
    state=word(row.state(1));
    if isempty(profile)
        fprintf(fid,' %s 状态为 %s，该轮没有可发送的冻结表。',word(names(j)),state);
    else
        m=unique(profile.M(:)).';
        assert(all(ismember(m,cfg.Mset)) && all(isfinite(profile.frequency_GHz)));
        [~,i]=min(abs(profile.frequency_GHz-cfg.case2_notch_GHz));
        % sprintf emits char per order and strjoin returns one char row.
        description=strjoin(arrayfun(@(order)sprintf('%d-QAM',order),m,'UniformOutput',false),'、');
        assert(ischar(description) && isrow(description) && ~isempty(description));
        capacity=row.bits_per_symbol(1);
        assert(isscalar(capacity) && isfinite(capacity) && capacity==sum(log2(profile.M)));
        fprintf(fid,[' %s 使用 %s，陷波最近的活跃载波为 %.2f GHz、%d-QAM，' ...
            '冻结表承载 %d bit/DMT 符号，该轮状态为 %s。'],word(names(j)), ...
            description,profile.frequency_GHz(i),profile.M(i),capacity,state);
    end
end
fprintf(fid,'\n\n');
end

function writeLengthSensitivity(fid,s)
fprintf(fid,'## 载荷长度敏感性\n\n');
valid=s(s.pair_qualified,:);
[cals,first]=unique(valid.calibration_id,'stable');
if isempty(cals)
    fprintf(fid,'代表点暂无两策略均达标且资源匹配的轮次。\n\n');
    return;
end
cross=valid.cross_over_L(first);
cross=cross(isfinite(cross) & cross>0);
coincident=sum(valid.cross_over_status(first)=="identical_cycle_rates");
if isempty(cross)
    fprintf(fid,'代表点 %d 个可比较轮次中，未发现孤立的正载荷长度交叉点。',numel(cals));
else
    fprintf(fid,'代表点 %d 个可比较轮次中，%d 轮的有限正交叉点为 %s 个载荷符号。', ...
        numel(cals),numel(cross),span(cross,0,''));
end
if coincident>0,fprintf(fid,' %d 轮的周期速率曲线重合。',coincident);end
fprintf(fid,' 这是固定已保存的调制表与配置时间，在 10³–10⁵ 符号之间重新计算周期速率的敏感性分析。\n\n');
end

function writeConditionTable(fid,scenario)
fprintf(fid,'## 全部正式工作点的判定\n\n');
fprintf(fid,['| 频响 | 摆幅 | 策略 | BER 达标轮数 | BER 失败 | 证据不足 | 功率失配 | ' ...
    '设计拒绝 | 功率错误 | 执行错误 | 未完成 | 达标周期速率范围 (Gbit/s) |\n' ...
    '| ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n']);
rows=sortrows(scenario,{'case_id','swing','strategy'});
assert(height(rows)==12);
for j=1:height(rows)
    r=rows(j,:);
    states=[r.supported_count(1) r.ber_failed_count(1) r.inconclusive_count(1) ...
        r.power_mismatch_count(1) r.design_rejected_count(1) r.power_error_count(1) ...
        r.execution_error_count(1) r.incomplete_count(1)];
    assert(all(isfinite(states) & states>=0 & states==fix(states)) && ...
        r.planned_calibrations(1)==5 && sum(states)==r.planned_calibrations(1) && ...
        r.qualified(1)==(states(1)==r.planned_calibrations(1)));
    rate='—';
    if r.qualified(1)
        limits=[r.R_cycle_min(1) r.R_cycle_max(1)]/1e9;
        assert(all(isfinite(limits) & limits>0) && limits(1)<=limits(2));
        rate=sprintf('%.3f–%.3f',limits(1),limits(2));
    end
    fprintf(fid,'| %d | %.2f | %s | %d/%d | %d | %d | %d | %d | %d | %d | %d | %s |\n', ...
        r.case_id(1),r.swing(1),word(r.strategy(1)),states(1),r.planned_calibrations(1), ...
        states(2),states(3),states(4),states(5),states(6),states(7),states(8),rate);
end
end

function rows=atPoint(t,c,swing)
rows=t(t.case_id==c & t.swing==swing & t.q==8,:);
end

function rows=keyRows(t,r)
rows=t(t.condition_id==r.condition_id(1) & t.calibration_id==r.calibration_id(1) & ...
    t.strategy==r.strategy(1),:);
end

function same(a,b,name)
assert(isequal(size(a),size(b)) && all(isfinite(a) & isfinite(b) & ...
    abs(a-b)<=5e-12*max(1,abs(b))), ...
    'DMT:VMNotesRecompute','Audited %s differs from independent recomputation.',name);
end

function label=word(value)
assert(isstring(value) && isscalar(value) && ~ismissing(value) && strlength(value)>0, ...
    'DMT:VMNotesText','A nonempty scalar text label is required.');
label=char(value);
end

function value=span(x,digits,suffix)
assert(isvector(x) || isempty(x));
if isempty(x),value='—';return;end
assert(all(isfinite(x)));
value=sprintf('%.*f%s',digits,median(x),suffix);
if min(x)~=max(x)
    value=sprintf('%s [%.*f–%.*f%s]',value,digits,min(x),digits,max(x),suffix);
end
end

function t=normalize(t)
% Convert at the table boundary, before comparisons or formatted output.
common={'condition_id','case_id','swing','q','calibration_id'};
stats={'supported_count','ber_failed_count','inconclusive_count','power_mismatch_count', ...
    'design_rejected_count','power_error_count','execution_error_count','incomplete_count'};
t.status=normalizeTable(t.status,{'phase','strategy','status'},[common {'payload_slot','actual_symbols'}],{});
t.power_adc=normalizeTable(t.power_adc,{'phase','strategy'}, ...
    [common {'payload_slot','samples','tx_low_count','tx_high_count'}],{});
t.summary=normalizeTable(t.summary,{'phase','strategy','state'},[common ...
    {'payload_slots_completed','bits_per_symbol','setup_symbols','T_setup_s','attempts','R_nominal','R_cycle'}],{});
t.profiles=normalizeTable(t.profiles,{'phase','strategy'},[common {'k','M','frequency_GHz'}],{});
t.overhead=normalizeTable(t.overhead,{'phase','strategy'},[common ...
    {'A0_symbols','B0_symbols','Ar_symbols','Dr_symbols','attempts','T_setup_s'}],{});
t.pair_gains=normalizeTable(t.pair_gains,{'phase','uniform_state','pertone_state'},[common ...
    {'uniform_bits_per_symbol','pertone_bits_per_symbol','pertone_R_cycle','uniform_R_cycle', ...
    'validated_delta_R_cycle','pertone_T_setup_s','uniform_T_setup_s'}],{'pair_qualified','resource_match'});
t.length_sensitivity=normalizeTable(t.length_sensitivity,{'phase','cross_over_status'}, ...
    {'calibration_id','cross_over_L'},{'pair_qualified'});
t.scenario=normalizeTable(t.scenario,{'phase','strategy'}, ...
    [{'case_id','swing','planned_calibrations','R_cycle_min','R_cycle_max'} stats],{'qualified'});
end

function t=normalizeTable(t,labels,numbers,flags)
assert(istable(t) && all(ismember([labels numbers flags],t.Properties.VariableNames)), ...
    'DMT:VMNotesSchema','A required formal report column is missing.');
for key=labels
    t.(key{1})=textColumn(t.(key{1}),height(t),key{1});
end
assert(all(t.phase=="formal"),'DMT:VMNotesPhase','Chinese results require formal tables.');
for key=numbers
    t.(key{1})=numericColumn(t.(key{1}),height(t),key{1});
end
for key=flags
    raw=t.(key{1});
    if iscell(raw) || ischar(raw) || isstring(raw) || iscategorical(raw)
        if ~iscell(raw) || all(cellfun(@(x)ischar(x)||isstring(x)||iscategorical(x),raw(:)))
            raw=lower(textColumn(raw,height(t),key{1}));
            raw(raw=="true")="1";
            raw(raw=="false")="0";
        end
    end
    x=numericColumn(raw,height(t),key{1});
    assert(all(ismember(x,[0 1])),'DMT:VMNotesFlag','Invalid logical column %s.',key{1});
    t.(key{1})=logical(x);
end
end

function out=textColumn(raw,n,key)
if ischar(raw)
    assert(size(raw,1)==n,'DMT:VMNotesText','Incorrect column height for %s.',key);
    raw=cellstr(raw);
end
assert(isequal(size(raw),[n 1]),'DMT:VMNotesText','Expected a scalar label per row in %s.',key);
if iscell(raw)
    out=strings(n,1);
    for j=1:n
        v=raw{j};
        assert((ischar(v)&&isrow(v)) || ...
            ((isstring(v)||iscategorical(v))&&isscalar(v)), ...
            'DMT:VMNotesText','Invalid text cell in %s.',key);
        out(j)=string(v);
    end
else
    assert(isstring(raw)||iscategorical(raw),'DMT:VMNotesText','Invalid text column %s.',key);
    out=string(raw);
end
assert(~any(ismissing(out)), 'DMT:VMNotesText','Missing text in %s.',key);
end

function out=numericColumn(raw,n,key)
if ischar(raw)
    assert(size(raw,1)==n,'DMT:VMNotesNumber','Incorrect column height for %s.',key);
    raw=cellstr(raw);
end
assert(isequal(size(raw),[n 1]),'DMT:VMNotesNumber','Expected one numeric value per row in %s.',key);
if (isnumeric(raw)||islogical(raw)) && isreal(raw)
    out=double(raw);
elseif iscell(raw)
    out=nan(n,1);
    for j=1:n
        v=raw{j};
        if (isnumeric(v)||islogical(v)) && isreal(v) && isscalar(v)
            out(j)=double(v);
        else
            assert((ischar(v)&&(isrow(v)||isempty(v))) || ...
                ((isstring(v)||iscategorical(v))&&isscalar(v)), ...
                'DMT:VMNotesNumber','Invalid numeric cell in %s.',key);
            out(j)=decode(string(v),key);
        end
    end
else
    assert(isstring(raw)||iscategorical(raw), ...
        'DMT:VMNotesNumber','Invalid numeric column %s.',key);
    out=decode(string(raw),key);
end
assert(all(isfinite(out) | isnan(out)),'DMT:VMNotesNumber','Nonfinite number in %s.',key);
end

function out=decode(words,key)
out=str2double(words);
knownMissing=ismissing(words)|wordIsEmptyOrNaN(words);
assert(isreal(out) && all(~isnan(out) | knownMissing), ...
    'DMT:VMNotesNumber','Non-numeric text in %s.',key);
end

function out=wordIsEmptyOrNaN(words)
words=lower(strtrim(words));
out=ismember(words,["","nan"]);
end
