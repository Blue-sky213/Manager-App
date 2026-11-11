; ตัวติดตั้ง Windows ของ Noir Manager (Inno Setup 6)
; CI สร้างให้อัตโนมัติ — สร้างเองในเครื่อง: flutter build windows --release แล้ว
;   iscc /DAppVersion=1.0.0 windows\installer\noir_manager.iss
; ติดตั้งแบบผู้ใช้คนเดียว (ไม่ต้องสิทธิ์ admin) · ข้อมูลแอปอยู่คนละที่ → ถอนการติดตั้งแล้วข้อมูลไม่หาย

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{BC456464-E6A6-53DF-A8DF-CC40A9C30E5C}
AppName=Noir Manager
AppVersion={#AppVersion}
AppPublisher=Noir
DefaultDirName={autopf}\Noir Manager
DefaultGroupName=Noir Manager
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\..\build\installer
OutputBaseFilename=NoirManager-Setup-{#AppVersion}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\noir_manager.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; ปิดแอปที่เปิดอยู่ก่อนอัปเดต (ไม่งั้นไฟล์ถูกล็อก)
CloseApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Noir Manager"; Filename: "{app}\noir_manager.exe"
Name: "{group}\{cm:UninstallProgram,Noir Manager}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Noir Manager"; Filename: "{app}\noir_manager.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\noir_manager.exe"; Description: "{cm:LaunchProgram,Noir Manager}"; Flags: nowait postinstall skipifsilent
