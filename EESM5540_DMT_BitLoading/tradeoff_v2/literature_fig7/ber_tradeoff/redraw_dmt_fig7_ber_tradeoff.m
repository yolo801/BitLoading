function output = redraw_dmt_fig7_ber_tradeoff(folder)
%REDRAW_DMT_FIG7_BER_TRADEOFF Regenerate a report from authenticated data.
folder=char(java.io.File(char(folder)).getCanonicalPath());
[report,tables]=verify_dmt_fig7_ber_tradeoff(folder,false);
assert(report.valid && strcmp(report.phase,'formal'),'DMT:FBRedrawIdentity', ...
    'Use a verified formal study folder. %s',report.detail);
saved=load(fullfile(folder,'Protocol.mat'),'checkpoint');
p=saved.checkpoint;
[~,tag]=fileparts(tempname(folder));
output=fullfile(folder,['redraw_' tag]);
assert(~isfolder(output),'DMT:FBRedrawDirectory','Redraw directory already exists.');
mkdir(output);
dmt_fb_graphics(output,p.study,p.cfg,tables);
dmt_fb_graphics(output,p.study,p.cfg,tables,'verify');
end
