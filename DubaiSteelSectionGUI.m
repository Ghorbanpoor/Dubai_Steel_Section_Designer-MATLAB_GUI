function DubaiSteelSectionGUI
% DubaiSteelSectionGUI
% MATLAB R2016b-compatible GUI for preliminary compactness/seismic
% compactness checks of doubly-symmetric I/H steel sections.
%
% Basis:
%   Dubai Building Code 2021, Part F, F.6.5 -> AISC 360 + AISC 341.
%   AISC 360-16 Table B4.1b (flexural I-shape compactness)
%   AISC 341-16 Table D1.1 (highly ductile seismic limits)
%
% Units: mm, MPa, kN, kN.m
%
% NOTE: This is an engineering screening/preliminary design tool. It does
% not replace a complete member design, connection design, stability
% checks, or authority review.

clc;

S = struct('name',{},'bf',{},'tf',{},'tw',{},'h',{},'Fy',{}, ...
    'E',{},'A',{},'Ix',{},'Iy',{},'rx',{},'ry',{}, ...
    'lamf',{},'lamw',{},'lambda_p_f',{},'lambda_r_f',{}, ...
    'lambda_p_w',{},'lambda_r_w',{},'status360',{}, ...
    'statusModerate',{},'statusSpecial',{});

% ---------- Figure ----------
f = figure('Name','Dubai Steel Section Compactness & Seismic Check', ...
    'NumberTitle','off','MenuBar','none','ToolBar','none', ...
    'Color',[0.94 0.94 0.94],'Units','normalized', ...
    'Position',[0.03 0.05 0.94 0.88], ...
    'Resize','on','WindowScrollWheelFcn',@scrollWheel);

% ---------- Input panel ----------
p = uipanel('Parent',f,'Title','Section definition / تعریف مقطع', ...
    'Units','normalized','Position',[0.015 0.56 0.29 0.42]);

labels = {'Name','bf (mm)','tf (mm)','tw (mm)','h (mm)', ...
          'Fy (MPa)','E (MPa)'};
defaults = {'W-section','300','20','12','500','345','200000'};
ed = gobjects(1,numel(labels));

for i=1:numel(labels)
    y = 0.88-(i-1)*0.115;
    uicontrol(p,'Style','text','String',labels{i},'Units','normalized', ...
        'Position',[0.04 y 0.38 0.075],'HorizontalAlignment','left', ...
        'BackgroundColor',get(p,'BackgroundColor'));
    ed(i)=uicontrol(p,'Style','edit','String',defaults{i}, ...
        'Units','normalized','Position',[0.44 y 0.48 0.085], ...
        'BackgroundColor','white','Callback',@updateAll, ...
        'UserData',[]);
end

% Buttons
uicontrol(p,'Style','pushbutton','String','Add section / افزودن', ...
    'Units','normalized','Position',[0.04 0.035 0.27 0.075], ...
    'Callback',@addSection);
uicontrol(p,'Style','pushbutton','String','Save report / گزارش', ...
    'Units','normalized','Position',[0.35 0.035 0.27 0.075], ...
    'Callback',@saveReport);
uicontrol(p,'Style','pushbutton','String','Save list', ...
    'Units','normalized','Position',[0.66 0.035 0.12 0.075], ...
    'Callback',@saveList);
uicontrol(p,'Style','pushbutton','String','Load list', ...
    'Units','normalized','Position',[0.80 0.035 0.16 0.075], ...
    'Callback',@loadList);

% ---------- Geometry axes ----------
ax = axes('Parent',f,'Units','normalized','Position',[0.34 0.56 0.30 0.40]);
box(ax,'on'); axis(ax,'equal'); grid(ax,'on');
title(ax,'Dynamic section geometry');
xlabel(ax,'x (mm)'); ylabel(ax,'y (mm)');

% ---------- Report ----------
rp = uipanel('Parent',f,'Title','Dynamic report / گزارش پویای مقطع', ...
    'Units','normalized','Position',[0.655 0.56 0.33 0.42]);
report = uicontrol(rp,'Style','edit','Max',50,'Min',0, ...
    'HorizontalAlignment','left','Enable','inactive','BackgroundColor','white', ...
    'Units','normalized','Position',[0.02 0.02 0.96 0.96], ...
    'FontName','Consolas','FontSize',9);

% ---------- List ----------
lp = uipanel('Parent',f,'Title','Defined sections / مقاطع تعریف شده', ...
    'Units','normalized','Position',[0.015 0.04 0.97 0.47]);

cols = {'Name','bf','tf','tw','h','Fy','A','Ix','Iy','Ix/Iy','Moderate','Special'};
tbl = uitable(lp,'Units','normalized','Position',[0.01 0.13 0.98 0.84], ...
    'ColumnName',cols,'ColumnEditable',false(1,numel(cols)), ...
    'CellSelectionCallback',@selectRow);
uicontrol(lp,'Style','pushbutton','String','Delete selected', ...
    'Units','normalized','Position',[0.01 0.025 0.15 0.075], ...
    'Callback',@deleteSelected);
uicontrol(lp,'Style','pushbutton','String','Sort by Ix', ...
    'Units','normalized','Position',[0.18 0.025 0.15 0.075], ...
    'Callback',@sortIx);
uicontrol(lp,'Style','pushbutton','String','Sort by Iy', ...
    'Units','normalized','Position',[0.35 0.025 0.15 0.075], ...
    'Callback',@sortIy);
uicontrol(lp,'Style','pushbutton','String','Clear list', ...
    'Units','normalized','Position',[0.52 0.025 0.15 0.075], ...
    'Callback',@clearList);

rankText = uicontrol(lp,'Style','text','String','Inertia ranking: --', ...
    'Units','normalized','Position',[0.69 0.025 0.29 0.075], ...
    'HorizontalAlignment','left','BackgroundColor',get(lp,'BackgroundColor'));

% Status
statusText = uicontrol(f,'Style','text','String', ...
    'Scroll wheel: move over any dimension field to recalculate. | Code basis: DBC 2021 + AISC 360/341', ...
    'Units','normalized','Position',[0.015 0.005 0.97 0.025], ...
    'HorizontalAlignment','left','BackgroundColor',[0.94 0.94 0.94]);

% internal selected row
selectedRow = [];

updateAll();

% ================================================================
% Callbacks
% ================================================================
    function scrollWheel(~,evt)
        % R2016b: WindowScrollWheelFcn receives event.VerticalScrollCount
        obj = get(f,'CurrentObject');
        if isempty(obj) || ~ishandle(obj), return; end
        if strcmp(get(obj,'Style'),'edit') && isfield(evt,'VerticalScrollCount')
            v = str2double(get(obj,'String'));
            if ~isnan(v)
                step = max(abs(v)*0.01,0.5);
                if evt.VerticalScrollCount < 0
                    v = v + step;
                else
                    v = max(0,v-step);
                end
                set(obj,'String',num2str(v,'%.6g'));
                updateAll();
            end
        end
    end

    function updateAll(~,~)
        q = readInputs();
        if ~q.ok
            set(report,'String',q.msg);
            return
        end
        r = calcSection(q);
        drawSection(r);
        makeReport(r);
    end

    function q = readInputs()
        q.ok=true; q.msg='';
        vals=zeros(1,7);
        for k=2:7
            vals(k)=str2double(get(ed(k),'String'));
            if isnan(vals(k)) || vals(k)<=0
                q.ok=false;
                q.msg=sprintf('Invalid input in %s.',labels{k});
                return
            end
        end
        q.name=get(ed(1),'String');
        if isempty(q.name), q.name='Section'; end
        q.bf=vals(2); q.tf=vals(3); q.tw=vals(4); q.h=vals(5);
        q.Fy=vals(6); q.E=vals(7);
        if q.h <= 2*q.tf || q.bf <= 0 || q.tw <= 0
            q.ok=false; q.msg='Require h > 2tf and positive dimensions.'; return
        end
    end

    function r=calcSection(q)
        % Doubly symmetric I/H section:
        % A = 2 bf tf + (h-2tf) tw
        hw=q.h-2*q.tf;
        r.A=2*q.bf*q.tf+hw*q.tw;
        r.Ix=2*(q.bf*q.tf^3/12 + q.bf*q.tf*(q.h/2-q.tf/2)^2) ...
             + q.tw*hw^3/12;
        r.Iy=2*(q.tf*q.bf^3/12)+(hw*q.tw^3/12);
        r.rx=sqrt(r.Ix/r.A); r.ry=sqrt(r.Iy/r.A);
        r.lamf=q.bf/(2*q.tf);
        r.lamw=hw/q.tw;

        % AISC 360-16 Table B4.1b, I-shape flexural elements:
        root=sqrt(q.E/q.Fy);
        r.lambda_p_f=0.38*root;
        r.lambda_r_f=1.00*root;
        r.lambda_p_w=3.76*root;
        r.lambda_r_w=5.70*root;

        r.flange360=classify(r.lamf,r.lambda_p_f,r.lambda_r_f);
        r.web360=classify(r.lamw,r.lambda_p_w,r.lambda_r_w);
        r.status360=combine(r.flange360,r.web360);

        % AISC 341-16 Table D1.1 style screening for HIGHLY ductile
        % I-shaped flexural members (special seismic):
        % flange b/t <= 0.32 sqrt(E/Fy), web h/t <= 2.45 sqrt(E/Fy)
        r.lambda_hd_f=0.32*root;
        r.lambda_hd_w=2.45*root;
        r.flangeSpecial = ternary(r.lamf<=r.lambda_hd_f,'PASS','FAIL');
        r.webSpecial = ternary(r.lamw<=r.lambda_hd_w,'PASS','FAIL');
        r.statusSpecial=ternary(strcmp(r.flangeSpecial,'PASS') && ...
                                 strcmp(r.webSpecial,'PASS'),'PASS','FAIL');

        % Moderate ductility: compact per AISC 360 is used as screening.
        r.statusModerate=ternary(strcmp(r.status360,'COMPACT'),'PASS','CHECK');

        r.q=q;
    end

    function s=classify(l,lp,lr)
        if l<=lp, s='COMPACT';
        elseif l<=lr, s='NONCOMPACT';
        else, s='SLENDER';
        end
    end

    function s=combine(a,b)
        if strcmp(a,'SLENDER') || strcmp(b,'SLENDER')
            s='SLENDER';
        elseif strcmp(a,'NONCOMPACT') || strcmp(b,'NONCOMPACT')
            s='NONCOMPACT';
        else
            s='COMPACT';
        end
    end

    function s=ternary(c,a,b)
        if c, s=a; else, s=b; end
    end

    function drawSection(r)
        q=r.q; cla(ax);
        hw=q.h-2*q.tf;
        % polygon for I section
        x=[-q.bf/2 q.bf/2 q.bf/2 q.tw/2 q.tw/2 q.bf/2 ...
           q.bf/2 -q.bf/2 -q.bf/2 -q.tw/2 -q.tw/2 -q.bf/2];
        y=[q.h/2 q.h/2 q.h/2-q.tf q.h/2-q.tf ...
           -q.h/2+q.tf -q.h/2+q.tf -q.h/2+q.tf ...
           -q.h/2+q.tf -q.h/2+q.tf -q.h/2+q.tf q.h/2-q.tf];
        % Simpler three rectangles
        rectangle(ax,'Position',[-q.bf/2 q.h/2-q.tf q.bf q.tf], ...
            'FaceColor',[0.65 0.75 0.90]);
        rectangle(ax,'Position',[-q.tw/2 -hw/2 q.tw hw], ...
            'FaceColor',[0.65 0.75 0.90]);
        rectangle(ax,'Position',[-q.bf/2 -q.h/2 q.bf q.tf], ...
            'FaceColor',[0.65 0.75 0.90]);
        line(ax,[0 0],[-q.h/2 q.h/2],'Color','k','LineStyle','--');
        line(ax,[-q.bf/2 q.bf/2],[0 0],'Color','k','LineStyle','--');
        axis(ax,'equal');
        lim=max(q.h,q.bf)*0.7;
        xlim(ax,[-lim lim]); ylim(ax,[-lim lim]);
        title(ax,sprintf('%s | A=%.1f mm^2 | Ix=%.3g | Iy=%.3g', ...
            q.name,r.A,r.Ix,r.Iy));
    end

    function makeReport(r)
        q=r.q;
        L={};
        L{end+1}=sprintf('DUBAI STEEL SECTION REPORT');
        L{end+1}=sprintf('Section: %s',q.name);
        L{end+1}=sprintf('Basis: Dubai Building Code 2021 Part F.6.5');
        L{end+1}=sprintf('Steel design: AISC 360; seismic: AISC 341');
        L{end+1}='---------------------------------------------';
        L{end+1}=sprintf('bf = %.3f mm     tf = %.3f mm',q.bf,q.tf);
        L{end+1}=sprintf('tw = %.3f mm     h  = %.3f mm',q.tw,q.h);
        L{end+1}=sprintf('Fy = %.3f MPa    E  = %.3f MPa',q.Fy,q.E);
        L{end+1}=sprintf('Area = %.3f mm^2',r.A);
        L{end+1}=sprintf('Ix   = %.6g mm^4',r.Ix);
        L{end+1}=sprintf('Iy   = %.6g mm^4',r.Iy);
        L{end+1}=sprintf('rx   = %.3f mm    ry = %.3f mm',r.rx,r.ry);
        L{end+1}=sprintf('Ix/Iy = %.5f',r.Ix/r.Iy);
        L{end+1}='---------------------------------------------';
        L{end+1}=sprintf('Flange lambda = %.4f',r.lamf);
        L{end+1}=sprintf('Web lambda    = %.4f',r.lamw);
        L{end+1}=sprintf('AISC360 flange: %s',r.flange360);
        L{end+1}=sprintf('AISC360 web:    %s',r.web360);
        L{end+1}=sprintf('AISC360 overall: %s',r.status360);
        L{end+1}='---------------------------------------------';
        L{end+1}=sprintf('Moderate ductility screening: %s',r.statusModerate);
        L{end+1}=sprintf('Special/high ductility screening: %s',r.statusSpecial);
        L{end+1}=sprintf('Special flange limit = %.4f',r.lambda_hd_f);
        L{end+1}=sprintf('Special web limit    = %.4f',r.lambda_hd_w);
        L{end+1}='---------------------------------------------';
        L{end+1}='Warning: seismic classification depends on';
        L{end+1}='the selected AISC 341 system/member role.';
        L{end+1}='This GUI is a section-level screening tool.';
        set(report,'String',L);
    end

    function addSection(~,~)
        q=readInputs(); if ~q.ok, errordlg(q.msg); return; end
        r=calcSection(q);
        k=numel(S)+1;
        S(k).name=q.name; S(k).bf=q.bf; S(k).tf=q.tf; S(k).tw=q.tw;
        S(k).h=q.h; S(k).Fy=q.Fy; S(k).E=q.E;
        S(k).A=r.A; S(k).Ix=r.Ix; S(k).Iy=r.Iy; S(k).rx=r.rx; S(k).ry=r.ry;
        S(k).lamf=r.lamf; S(k).lamw=r.lamw;
        S(k).lambda_p_f=r.lambda_p_f; S(k).lambda_r_f=r.lambda_r_f;
        S(k).lambda_p_w=r.lambda_p_w; S(k).lambda_r_w=r.lambda_r_w;
        S(k).status360=r.status360; S(k).statusModerate=r.statusModerate;
        S(k).statusSpecial=r.statusSpecial;
        refreshTable();
    end

    function refreshTable()
        n=numel(S); data=cell(n,12);
        for k=1:n
            data{k,1}=S(k).name; data{k,2}=S(k).bf; data{k,3}=S(k).tf;
            data{k,4}=S(k).tw; data{k,5}=S(k).h; data{k,6}=S(k).Fy;
            data{k,7}=S(k).A; data{k,8}=S(k).Ix; data{k,9}=S(k).Iy;
            data{k,10}=S(k).Ix/S(k).Iy; data{k,11}=S(k).statusModerate;
            data{k,12}=S(k).statusSpecial;
        end
        set(tbl,'Data',data);
        updateRanking();
    end

    function selectRow(~,evt)
        if isempty(evt.Indices), return; end
        selectedRow=evt.Indices(1);
        if selectedRow<=numel(S)
            q=S(selectedRow);
            set(ed(1),'String',q.name); set(ed(2),'String',num2str(q.bf));
            set(ed(3),'String',num2str(q.tf)); set(ed(4),'String',num2str(q.tw));
            set(ed(5),'String',num2str(q.h)); set(ed(6),'String',num2str(q.Fy));
            set(ed(7),'String',num2str(q.E));
            updateAll();
        end
    end

    function deleteSelected(~,~)
        if isempty(selectedRow) || selectedRow>numel(S), return; end
        S(selectedRow)=[]; selectedRow=[]; refreshTable();
    end

    function clearList(~,~)
        S=struct('name',{},'bf',{},'tf',{},'tw',{},'h',{},'Fy',{}, ...
            'E',{},'A',{},'Ix',{},'Iy',{},'rx',{},'ry',{}, ...
            'lamf',{},'lamw',{},'lambda_p_f',{},'lambda_r_f',{}, ...
            'lambda_p_w',{},'lambda_r_w',{},'status360',{}, ...
            'statusModerate',{},'statusSpecial',{});
        refreshTable();
    end

    function sortIx(~,~)
        if isempty(S), return; end
        [~,idx]=sort([S.Ix],'descend'); S=S(idx); refreshTable();
    end

    function sortIy(~,~)
        if isempty(S), return; end
        [~,idx]=sort([S.Iy],'descend'); S=S(idx); refreshTable();
    end

    function updateRanking()
        if isempty(S)
            set(rankText,'String','Inertia ranking: --'); return
        end
        [~,ix]=sort([S.Ix],'descend');
        [~,iy]=sort([S.Iy],'descend');
        topIx=S(ix(1)).name; topIy=S(iy(1)).name;
        set(rankText,'String',sprintf('Max Ix: %s | Max Iy: %s',topIx,topIy));
    end

    function saveReport(~,~)
        [file,path]=uiputfile('*.txt','Save section report');
        if isequal(file,0), return; end
        q=readInputs(); if ~q.ok, errordlg(q.msg); return; end
        r=calcSection(q); makeReport(r);
        fid=fopen(fullfile(path,file),'w');
        if fid<0, errordlg('Cannot create report file.'); return; end
        C=get(report,'String');
        if ischar(C), fprintf(fid,'%s\n',C);
        else
            for ii=1:numel(C), fprintf(fid,'%s\n',C{ii}); end
        end
        fclose(fid);
        msgbox('Report saved.','Done');
    end

    function saveList(~,~)
        [file,path]=uiputfile('*.mat','Save section list');
        if isequal(file,0), return; end
        Ssave=S; %#ok<NASGU>
        save(fullfile(path,file),'Ssave');
        msgbox('Section list saved.','Done');
    end

    function loadList(~,~)
        [file,path]=uigetfile('*.mat','Load section list');
        if isequal(file,0), return; end
        z=load(fullfile(path,file),'Ssave');
        if ~isfield(z,'Ssave')
            errordlg('Invalid list file.'); return
        end
        S=z.Ssave; refreshTable();
        if ~isempty(S)
            selectedRow=1;
            q=S(1);
            set(ed(1),'String',q.name); set(ed(2),'String',num2str(q.bf));
            set(ed(3),'String',num2str(q.tf)); set(ed(4),'String',num2str(q.tw));
            set(ed(5),'String',num2str(q.h)); set(ed(6),'String',num2str(q.Fy));
            set(ed(7),'String',num2str(q.E));
            updateAll();
        end
    end
end
