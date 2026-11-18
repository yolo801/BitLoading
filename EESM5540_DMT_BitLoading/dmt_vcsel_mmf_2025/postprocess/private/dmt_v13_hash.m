function id = dmt_v13_hash(value)
%DMT_V13_HASH Canonical plain-value hash, with explicit shapes and complex parts.
% Runtime objects, global variables and MAT compression are not identifiers.
id=dmt_sha256(encode(value));
end

function text=encode(value)
shape=sprintf('%d,',size(value));
if isstruct(value)
    fields=sort(fieldnames(value));
    parts=cell(numel(value)*numel(fields)+2,1);
    parts{1}=['struct[' shape ']{']; n=1;
    for j=1:numel(value)
        for q=1:numel(fields)
            key=fields{q}; n=n+1;
            parts{n}=[sprintf('%d:',numel(key)) key '=' encode(value(j).(key))];
        end
    end
    parts{n+1}='}'; text=[parts{1:n+1}];
elseif istable(value)
    text=['table{' encode(value.Properties.VariableNames) encode(table2struct(value)) '}'];
elseif iscell(value)
    parts=cell(numel(value)+2,1); parts{1}=['cell[' shape ']{'];
    for j=1:numel(value),parts{j+1}=encode(value{j});end
    parts{end}='}';text=[parts{:}];
elseif isstring(value)
    parts=cell(numel(value)+2,1);parts{1}=['string[' shape ']{'];
    for j=1:numel(value)
        if ismissing(value(j)),parts{j+1}='missing;';else,parts{j+1}=encode(char(value(j)));end
    end
    parts{end}='}';text=[parts{:}];
elseif ischar(value)
    raw=unicode2native(value(:).','UTF-8');
    text=['char[' shape ']:' sprintf('%02x',raw) ';'];
elseif isnumeric(value) || islogical(value)
    assert(~issparse(value),'DMT:HashType','Sparse objects are not protocol records.');
    text=[class(value) '[' shape ']R=' sprintf('%.17g,',real(value(:)))];
    if ~isreal(value),text=[text 'I=' sprintf('%.17g,',imag(value(:)))];end
    text=[text ';'];
else
    error('DMT:HashType','Unsupported protocol record type: %s',class(value));
end
end
