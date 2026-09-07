; OpenCpolarSync 安装程序脚本
; 使用 Inno Setup 6.x / 7.x 编译
; 编译命令：ISCC.exe setup.iss

#define MyAppName "OpenCpolarSync"
#define MyAppVersion "1.1.22"
#define MyAppPublisher "PingWang"
#define MyAppExeName "OpenCpolarSync.exe"

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=Output
OutputBaseFilename=OpenCpolarSync-Setup_{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}
SetupIconFile=..\src\OpenCpolarSync.Client\app.ico
AppCopyright=Copyright (C) 2026 PingWang
; 卸载时关闭运行中的程序
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加图标:"
Name: "autostart"; Description: "开机自动启动"; GroupDescription: "启动选项:"; Flags: unchecked

[Files]
; 主程序及依赖（从编译输出目录复制）
Source: "..\src\OpenCpolarSync.Client\bin\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

; cpolar 安装包
; 放到持久目录供 MSI 源使用：避免用 {tmp}（安装后即删）导致 Windows Installer 记录失效源，重装时报 1612
Source: "..\legacy\Cpolar\installer\cpolar_amd64.msi"; DestDir: "{app}\installer"; Flags: ignoreversion

; openlist 绿色包
Source: "..\legacy\Openlist\archive\openlist.zip"; DestDir: "{tmp}"; Flags: deleteafterinstall

; 注意：不打包 config.json，首次运行时程序自动创建空配置，用户在界面中填写后保存

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\卸载 {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Registry]
; 开机自启
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "OpenCpolarSync"; ValueData: """{app}\{#MyAppExeName}"""; Tasks: autostart; Flags: uninsdeletevalue

[Run]
; 启动主程序
Filename: "{app}\{#MyAppExeName}"; Description: "启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; 删除运行时生成的配置和日志目录
Type: filesandordirs; Name: "{app}\config"
Type: filesandordirs; Name: "{app}\logs"
; 删除 openlist 子目录（绿色包解压目录）
Type: filesandordirs; Name: "{app}\openlist"
; 删除 cpolar 安装源目录（持久化 MSI）
Type: filesandordirs; Name: "{app}\installer"
; 删除 cpolar 自动安装标记文件
Type: files; Name: "{app}\cpolar_autoinstalled.flag"

[Code]
const
  CPOLAR_PRODUCT_CODE = '{6999C327-6148-4692-B189-C9661B8FC004}';

var
  CpolarInstalled: Boolean;
  { 记录用户在卸载时是否选择删除用户数据目录（配置/openlist数据等） }
  DeleteUserData: Boolean;

function IsCpolarInstalled(): Boolean;
begin
  Result := CpolarInstalled;
end;

{ 遍历注册表卸载项，检查是否有 cpolar 相关条目 }
function IsCpolarInRegistry(): Boolean;
var
  SubKeys: array of string;
  I: Integer;
  DisplayName: string;
begin
  Result := False;

  { 检查 64 位注册表 }
  if RegGetSubkeyNames(HKLM, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', SubKeys) then
  begin
    for I := 0 to GetArrayLength(SubKeys) - 1 do
    begin
      if RegQueryStringValue(HKLM, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\' + SubKeys[I], 'DisplayName', DisplayName) then
      begin
        if Pos('cpolar', LowerCase(DisplayName)) > 0 then
        begin
          Result := True;
          Exit;
        end;
      end;
    end;
  end;

  { 检查 32 位注册表（WOW6432Node） }
  if RegGetSubkeyNames(HKLM, 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall', SubKeys) then
  begin
    for I := 0 to GetArrayLength(SubKeys) - 1 do
    begin
      if RegQueryStringValue(HKLM, 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\' + SubKeys[I], 'DisplayName', DisplayName) then
      begin
        if Pos('cpolar', LowerCase(DisplayName)) > 0 then
        begin
          Result := True;
          Exit;
        end;
      end;
    end;
  end;
end;

{ 从字符串中提取 GUID（带大括号的格式） }
function ExtractGuid(const S: string): string;
var
  StartPos, EndPos: Integer;
begin
  Result := '';
  StartPos := Pos('{', S);
  if StartPos > 0 then
  begin
    EndPos := Pos('}', S);
    if EndPos > StartPos then
    begin
      Result := Copy(S, StartPos, EndPos - StartPos + 1);
    end;
  end;
end;

{ 从注册表获取 cpolar 的 MSI ProductCode（用于卸载） }
function GetCpolarProductCode(): string;
var
  SubKeys: array of string;
  I: Integer;
  DisplayName, UninstallString: string;
  RootKey: Cardinal;
  RegPath: string;
  J: Integer;
begin
  Result := '';

  { 同时检查 64 位和 32 位注册表 }
  for J := 0 to 1 do
  begin
    if J = 0 then
    begin
      RootKey := HKLM64;
      RegPath := 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall';
    end
    else
    begin
      RootKey := HKLM32;
      RegPath := 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall';
    end;

    if RegGetSubkeyNames(RootKey, RegPath, SubKeys) then
    begin
      for I := 0 to GetArrayLength(SubKeys) - 1 do
      begin
        if RegQueryStringValue(RootKey, RegPath + '\' + SubKeys[I], 'DisplayName', DisplayName) then
        begin
          if Pos('cpolar', LowerCase(DisplayName)) > 0 then
          begin
            { 方式1：子键名本身就是 GUID（MSI 安装程序的常见格式） }
            if (Pos('{', SubKeys[I]) = 1) and (Pos('}', SubKeys[I]) = Length(SubKeys[I])) then
            begin
              Result := SubKeys[I];
              Exit;
            end;

            { 方式2：从 UninstallString 中提取 GUID }
            if RegQueryStringValue(RootKey, RegPath + '\' + SubKeys[I], 'UninstallString', UninstallString) then
            begin
              Result := ExtractGuid(UninstallString);
              if Result <> '' then Exit;
            end;
          end;
        end;
      end;
    end;
  end;
end;

{ 通过 wmic 命令获取 cpolar 的 ProductCode（注册表方式失败时的回退） }
function GetCpolarProductCodeByWmic(): string;
var
  ResultCode: Integer;
  TmpFile: string;
  Lines: TArrayOfString;
  I: Integer;
  Line: string;
begin
  Result := '';
  TmpFile := ExpandConstant('{tmp}\cpolar_guid.txt');

  { 用 wmic 查询 MSI 产品的 IdentifyingNumber（即 ProductCode） }
  Exec('cmd.exe',
       '/c wmic product where "name like ''%cpolar%''" get IdentifyingNumber /value > "' + TmpFile + '" 2>nul',
       '', SW_HIDE, ewWaitUntilTerminated, ResultCode);

  if LoadStringsFromFile(TmpFile, Lines) then
  begin
    for I := 0 to GetArrayLength(Lines) - 1 do
    begin
      Line := Trim(Lines[I]);
      if Pos('IdentifyingNumber=', Line) = 1 then
      begin
        Result := Trim(Copy(Line, Pos('=', Line) + 1, Length(Line)));
        if Result <> '' then Break;
      end;
    end;
  end;

  DeleteFile(TmpFile);
end;

{ 检测指定进程是否正在运行 }
function IsProcessRunning(ImageName: string): Boolean;
var
  ResultCode: Integer;
  TmpFile: string;
  Lines: TArrayOfString;
  I: Integer;
begin
  Result := False;
  TmpFile := ExpandConstant('{tmp}\proc_check.txt');
  { 使用 tasklist 检查进程 }
  Exec('cmd.exe', '/c tasklist /FI "IMAGENAME eq ' + ImageName + '" /NH > "' + TmpFile + '" 2>nul', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  if LoadStringsFromFile(TmpFile, Lines) then
  begin
    for I := 0 to GetArrayLength(Lines) - 1 do
    begin
      if Pos(ImageName, Lines[I]) > 0 then
      begin
        Result := True;
        Break;
      end;
    end;
  end;
  DeleteFile(TmpFile);
end;

{ 强制终止指定进程 }
procedure KillProcess(ImageName: string);
var
  ResultCode: Integer;
begin
  Exec('taskkill.exe', '/F /IM ' + ImageName + ' /T', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Sleep(500);
end;

procedure InitializeWizard;
begin
  { 方式1：遍历注册表卸载项，匹配 DisplayName 含 cpolar }
  CpolarInstalled := IsCpolarInRegistry();

  { 方式2：回退检查默认安装路径 }
  if not CpolarInstalled then
  begin
    CpolarInstalled := FileExists(ExpandConstant('{pf}\cpolar\cpolar.exe')) or
                        FileExists(ExpandConstant('{pf32}\cpolar\cpolar.exe'));
  end;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;

  { 在准备安装页面提示用户 }
  if CurPageID = wpReady then
  begin
    if not CpolarInstalled then
    begin
      if MsgBox('检测到您的电脑尚未安装 Cpolar。' + #13#10 +
                '安装程序将自动为您安装 Cpolar。' + #13#10 +
                '是否继续？',
                mbConfirmation, MB_YESNO) = IDNO then
      begin
        Result := False;
      end;
    end;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  OpenlistDir: string;
begin
  if CurStep = ssPostInstall then
  begin
    { 创建 openlist 子目录 }
    OpenlistDir := ExpandConstant('{app}\openlist');
    if not DirExists(OpenlistDir) then
    begin
      CreateDir(OpenlistDir);
    end;

    { 解压 openlist.zip 到 openlist 子目录 }
    if FileExists(ExpandConstant('{tmp}\openlist.zip')) then
    begin
      ExtractTemporaryFile('openlist.zip');
      { 使用 Windows 自带的解压功能 }
      Exec('powershell.exe',
           '-Command "Expand-Archive -Path ''' + ExpandConstant('{tmp}\openlist.zip') + ''' -DestinationPath ''' + OpenlistDir + ''' -Force"',
           '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    end;

    { 如果是我们自动安装的 cpolar，静默安装成功后才创建标记文件；卸载时据此判断是否同步卸载 cpolar }
    { 注意：msiexec 静默可能失败，必须校验退出码，避免留下“已安装”但实际未装成功的假标记 }
    if not CpolarInstalled then
    begin
      { 清理同 ProductCode 的失效 MSI 残留：Windows Installer 会用 SourceList 解析旧源，若旧源已删除将导致错误 1612 }
      { 该残留键名由 ProductCode 6999C327-6148-4692-B189-C9661B8FC004 的注册表变形决定，恒定不变 }
      if RegKeyExists(HKLM, 'Software\Classes\Installer\Products\723C9996841629641B989C66B1F80C40') then
      begin
        RegDeleteKeyIncludingSubkeys(HKLM, 'Software\Classes\Installer\Products\723C9996841629641B989C66B1F80C40');
      end;
      if RegKeyExists(HKLM, 'Software\Microsoft\Windows\CurrentVersion\Installer\Products\723C9996841629641B989C66B1F80C40') then
      begin
        RegDeleteKeyIncludingSubkeys(HKLM, 'Software\Microsoft\Windows\CurrentVersion\Installer\Products\723C9996841629641B989C66B1F80C40');
      end;
      { 用持久目录中的 MSI 作为安装源，避免临时目录被清后源失效再次触发 1612 }
      Exec('msiexec.exe',
           '/i "' + ExpandConstant('{app}\installer\cpolar_amd64.msi') + '" /qn',
           '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
      { 0=成功，3010=成功但需重启；其余视为安装失败，不写标记 }
      if (ResultCode = 0) or (ResultCode = 3010) then
      begin
        SaveStringToFile(ExpandConstant('{app}\cpolar_autoinstalled.flag'),
                         'cpolar was installed by OpenCpolarSync installer. Do not delete manually.',
                         False);
      end
      else
      begin
        MsgBox('Cpolar 自动安装失败（错误码 ' + IntToStr(ResultCode) + '）。' + #13#10 +
               '请稍后手动安装 Cpolar，卸载时本软件将不会执行同步卸载。',
               mbError, MB_OK);
      end;
    end;
  end;
end;

{ ==================== 卸载逻辑 ==================== }

function InitializeUninstall(): Boolean;
begin
  Result := True;
  DeleteUserData := False;

  { 检测主程序是否正在运行 }
  if IsProcessRunning('OpenCpolarSync.exe') then
  begin
    if MsgBox('检测到 OpenCpolarSync 正在运行。' + #13#10 +
              '卸载程序需要先关闭它，是否继续？',
              mbConfirmation, MB_YESNO) = IDYES then
    begin
      { 终止主程序进程 }
      KillProcess('OpenCpolarSync.exe');
      Sleep(1000);
    end
    else
    begin
      { 用户取消，中止卸载 }
      Result := False;
      Exit;
    end;
  end;

  { 询问用户是否删除用户数据（配置文件、openlist 数据等） }
  { 用户数据存储在 %LocalAppData%\OpenCpolarSync\，卸载程序默认不删除，以便重装后保留配置 }
  if MsgBox('是否同时删除用户数据？' + #13#10 + #13#10 +
            '用户数据包括：配置文件（Cpolar 登录信息、钉钉 Webhook 等）、' +
            'Openlist 运行数据。' + #13#10 + #13#10 +
            '选择"是"将完全清除所有用户数据（不可恢复）；' +
            '选择"否"将保留用户数据，重新安装后可继续使用。',
            mbConfirmation, MB_YESNO) = IDYES then
  begin
    DeleteUserData := True;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
  FlagFile: string;
  ProductCode: string;
begin
  if CurUninstallStep = usUninstall then
  begin
    { 终止 openlist 进程（如果在运行） }
    if IsProcessRunning('openlist.exe') then
    begin
      KillProcess('openlist.exe');
    end;

    { 检查 cpolar 是否由本安装程序自动安装 }
    FlagFile := ExpandConstant('{app}\cpolar_autoinstalled.flag');
    if FileExists(FlagFile) then
    begin
      { 是我们安装的，询问用户是否同步卸载 cpolar }
      if MsgBox('检测到 Cpolar 是由本软件安装的。' + #13#10 +
                '是否同时卸载 Cpolar？' + #13#10 +
                '（选择"是"将完全移除 Cpolar，选择"否"保留 Cpolar）',
                mbConfirmation, MB_YESNO) = IDYES then
      begin
        { 优先使用安装包自带 MSI 的固定 ProductCode；若注册表无该条目（例如 MSI 升级过/被替换），再回退到模糊搜索 }
        ProductCode := CPOLAR_PRODUCT_CODE;
        if not RegKeyExists(HKLM64,
             'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\' + ProductCode) then
        begin
          ProductCode := GetCpolarProductCode();
        end;
        { 注册表方式仍失败时，用 wmic 命令回退获取 }
        if ProductCode = '' then
        begin
          ProductCode := GetCpolarProductCodeByWmic();
        end;

        if ProductCode <> '' then
        begin
          { 先终止 cpolar 进程 }
          if IsProcessRunning('cpolar.exe') then
          begin
            KillProcess('cpolar.exe');
          end;

          { 执行 MSI 静默卸载 }
          Exec('msiexec.exe', '/x ' + ProductCode + ' /qn /norestart',
               '', SW_HIDE, ewWaitUntilTerminated, ResultCode);

          { 等待卸载完成 }
          Sleep(2000);

          { 验证卸载是否成功（检查注册表中是否还有 cpolar 条目） }
          if GetCpolarProductCode() <> '' then
          begin
            { 静默卸载可能失败，尝试带界面的卸载 }
            MsgBox('Cpolar 静默卸载可能未完成。' + #13#10 +
                   '请在弹出的窗口中完成 Cpolar 的卸载。',
                   mbInformation, MB_OK);
            Exec('msiexec.exe', '/x ' + ProductCode,
                 '', SW_SHOW, ewWaitUntilTerminated, ResultCode);
          end;
        end
        else
        begin
          { 无法获取 ProductCode，提示用户手动卸载 }
          MsgBox('无法自动获取 Cpolar 的卸载信息。' + #13#10 +
                 '请通过"控制面板 → 程序和功能"手动卸载 Cpolar。',
                 mbInformation, MB_OK);
        end;
      end;
    end;
  end;

  if CurUninstallStep = usPostUninstall then
  begin
    { 清理可能残留的安装目录（如果目录为空或仅含空目录） }
    { Inno Setup 会自动删除 [Files] 段安装的文件 }
    { [UninstallDelete] 段会删除 config、logs、openlist 子目录和标记文件 }
    { 此处额外检查并删除空的安装目录 }
    if DirExists(ExpandConstant('{app}')) then
    begin
      { 尝试删除目录（仅当目录为空时成功） }
      if RemoveDir(ExpandConstant('{app}')) then
      begin
        { 目录已删除 }
      end;
    end;

    { 如果用户在卸载时选择了删除用户数据，则删除 %LocalAppData%\OpenCpolarSync\ }
    if DeleteUserData then
    begin
      { 用户数据目录路径：%LocalAppData%\OpenCpolarSync }
      { 包含 config（配置文件）、openlist（运行数据）等子目录 }
      DelTree(ExpandConstant('{localappdata}\OpenCpolarSync'), True, True, True);
    end;
  end;
end;
