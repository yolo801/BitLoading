function dmt_fb_audit_csv(path,expected)
%DMT_FB_AUDIT_CSV Compare named CSV columns with authenticated field values.
assert(istable(expected),'DMT:FBCSVType','Expected a table for %s.',path);
fid=fopen(path,'rt','n','UTF-8');
assert(fid>=0,'DMT:FBCSVOpen','Cannot open %s.',path);
closer=onCleanup(@()fclose(fid));
header=fgetl(fid);
assert(ischar(header),'DMT:FBCSVHeader','Missing CSV header in %s.',path);
if ~isempty(header) && header(1)==char(65279),header=header(2:end);end
expectedHeader=strjoin(expected.Properties.VariableNames,',');
assert(strcmp(header,expectedHeader),'DMT:FBCSVHeader','Column names or delimiter differs in %s.',path);
clear closer;
if height(expected)==0
    text=erase(fileread(path),string(char(65279)));
    assert(strcmp(strtrim(text),expectedHeader),'DMT:FBCSVRows','Unexpected data rows in %s.',path);
    return;
end
opts=detectImportOptions(path,'Delimiter',',','Encoding','UTF-8','VariableNamingRule','preserve');
assert(isequal(opts.VariableNames,expected.Properties.VariableNames), ...
    'DMT:FBCSVImport','Resolved CSV columns differ in %s.',path);
opts=setvartype(opts,opts.VariableNames,'string');
observed=readtable(path,opts);
assert(height(observed)==height(expected),'DMT:FBCSVRows','CSV row count differs in %s.',path);
for j=1:width(expected)
    name=expected.Properties.VariableNames{j};
    a=observed.(name);
    b=expected.(name);
    if isnumeric(b) || islogical(b)
        a=lower(a);
        a(a=="true")="1";
        a(a=="false")="0";
        a=str2double(a);
        b=double(b);
        finite=isfinite(b);
        ints=finite & b==fix(b);
        realValue=finite & ~ints;
        equal=isequaln(a(~finite),b(~finite)) && isequal(a(ints),b(ints)) && ...
            all(abs(a(realValue)-b(realValue))<=2e-12*max(1,abs(b(realValue))));
    else
        b=string(b);
        a(ismissing(a))="";
        b(ismissing(b))="";
        equal=isequal(a,b);
    end
    assert(equal,'DMT:FBCSVValue','CSV column %s differs in %s.',name,path);
end
end
