SANIE LAUNCHER - ALL-IN-ONE SERVER UPDATE

The server wizard now starts on a platform-selection screen. Neither SanieHST
configuration controls nor server-management controls are active until a
platform is selected. Selecting Aternos only opens the browser after explicit
confirmation. Selecting SanieHST reveals configuration; `start-server.bat`,
server.properties and the server folder are created only after accepting EULA
and pressing «Создать SanieHST». Created servers can be selected again
in the same window, and their server.properties includes name, MOTD, port,
gamemode, difficulty and online-mode. Plugins are searched on Hangar and
installed into plugins. Fabric mods remain in the Modrinth/Fabric catalogue;
they are intentionally separate from Paper plugins. Version installation,
Fabric launch mode, themes, animations, Aternos browser access and the
server wizard are included in the same distribution.

SANIE LAUNCHER - SERVER BETA UPDATE

Servers now has a glowing «Создать свой (BETA)» button. The wizard offers:
- «★ Рекомендуем! SanieHST»: a locally managed Paper or Vanilla server.
  Choose RAM, port, server name/MOTD, game mode, difficulty and online-mode.
  It creates server.properties, eula.txt, plugins\ and start-server.bat.
- Aternos: opens https://aternos.org/ in the default browser; Sanie does not
  log in to or control Aternos accounts.

SanieHST's plugin panel searches the Hangar/PaperMC catalog and downloads the
selected plugin into the server's plugins folder. Only install plugins you
trust. Restart the server after adding plugins. Paper plugins are not Fabric
mods. The beta downloads server JARs from official PaperMC or Mojang endpoints.
Internet access, Java, router configuration and port forwarding are not
provided automatically. You must accept the Minecraft EULA yourself.

SANIE LAUNCHER - MODS & SERVERS UPDATE

NEW FEATURES
Servers: glowing Create your own button opens a separate server wizard.
Select an EMPTY folder and accept the Minecraft EULA to download the
selected official Mojang vanilla server (SHA-1 verified). Run the generated
start-server.bat with compatible Java on PATH. Local address: localhost.
Public access needs router/firewall setup; no cloud hosting is provided.
Online authentication remains enabled; the offline launcher profile cannot
join an authenticated server without a valid authenticated client session.

Catalogue: Search Modrinth for Fabric mods matching the selected Minecraft
version. Install selected downloads the primary JAR and required dependencies,
verifies SHA-512, and installs Fabric loader metadata/libraries. First install
base Minecraft via the existing version installer. After mod installation,
switch Catalogue launch mode to Fabric, then Play. Vanilla mode ignores mods.
Keep CommunityTools.ps1 beside the EXE. The wizard UI is currently English.
Uses GameDir from profile.ini; default is %APPDATA%\.minecraft.
Only Fabric is supported in this installer; not Forge/NeoForge/modpacks.
No transactional rollback, dependency conflict solver or separate mod profiles.
Back up worlds/mods and do not install while Minecraft is running. Changing
Minecraft versions shares the same mods folder: incompatible old mods must
be removed manually. Install only trusted third-party executable mods.
Java is not installed automatically. Fabric libraries use HTTPS; SHA-512
verification applies to Modrinth mod JARs, not Fabric Maven libraries.
Windows x64 EXE cross-compilation and PowerShell parser checks passed.
Interactive Windows UI, downloads and Minecraft gameplay remain untested.
This update supersedes older preview-only/Fabric limitations below.

SANIE LAUNCHER - THEMES & MOTION

Settings now includes 6 color palettes: Emerald, Ocean, Amethyst, Sunset,
Rose, Arctic. Each works in dark or light mode (12 combinations).
Smooth 380ms color interpolation, 280ms page reveal, sliding navigation
highlight, animated hover and pressed button feedback. Animation updates
use elapsed time and repaint only while a transition is active.
Settings includes an animation toggle. Theme/mode/motion preferences persist
in profile.ini. The banner sky and editor surfaces follow the active palette.
The editor's pixel canvas/template and legacy avatar colors stay unchanged.
No animated wallpapers, 3D effects or installer-console animations.
Successful Windows x64 cross-compilation; no visual Windows runtime test.

SANIE LAUNCHER - VERSION INSTALLER UPDATE

INSTALLATION
Select a version with the version selector, then click the Install / Verify
button above the quick-launch card. Confirm, wait for INSTALL COMPLETE,
press Enter to close the installer console, then click Play.
InstallVersion.ps1 must stay beside the EXE. It fetches Mojang's official
manifest and verifies SHA-1 plus file sizes for the client JAR, applicable
Windows x64 libraries/natives, asset index/objects, and log configuration.
The installer uses GameDir from profile.ini, defaulting to %APPDATA%\.minecraft.
Good cached files are reused, damaged files are replaced, failed downloads
are retried up to 3 times. Retrying does not resume a partial single file.
Worlds and options are not deleted. Back up important worlds nevertheless.
Installation runs in a separate console; this is not an in-window progress UI.
Do not run Minecraft or another installer against the same directory during
installation. Re-running verifies shared libraries/assets, which can take time.
Java is NOT installed automatically. Install the required x64 JDK separately.
Only vanilla versions from the existing UI list are supported; not Forge,
Fabric, snapshots, modpacks, or automatic synchronization of the UI list.
A version absent from Mojang's manifest is rejected without guessing URLs.
Log: %LOCALAPPDATA%\SanieLauncher\installer.log

SANIE LAUNCHER - SKIN EDITOR UPDATE

SKIN EDITOR
Click the Skin Editor button in the top bar. A built-in editor window opens.
64x64 classic texture; left mouse draws; right mouse picks a color.
Pencil, transparent eraser, Windows color picker, grid toggle, undo/redo
(64 strokes), import/export PNG, editable template, live front base-layer
preview. Ctrl+Z / Ctrl+Y / Ctrl+S are supported.
Save writes %LOCALAPPDATA%\SanieLauncher\skin.png and reloads it next time.
All texture pixels are editable, but the preview shows only the base front
faces, not a full 3D model or outer layers. Slim/3px and old 64x32 imports
are not supported. PNG export does NOT apply the skin inside Minecraft.
Offline in-game skin display requires a separate compatible client mod.
The editor code lives in skin_editor.h, included by main.cpp.
EXE cross-compilation is checked; interactive Windows testing is not done.

SANIE LAUNCHER 2.1 - LOCAL OFFLINE LAUNCH

REQUIREMENTS
Windows 10/11 x64, Windows PowerShell 5.1, 64-bit Java compatible with
Minecraft. Install the game using the Install / Verify button or reuse an
existing complete installation. Java is not included or downloaded.
Use your legitimately obtained installation. No Microsoft login is made.
Offline profiles support singleplayer and servers allowing offline users;
they cannot access servers requiring valid authenticated sessions.

QUICK START
1. Extract the whole ZIP. Keep LaunchOffline.ps1 beside SanieLauncher.exe.
2. Make sure the selected version is fully installed in
   %APPDATA%\.minecraft (versions, libraries, assets and log_configs).
3. Set your nickname in Profile (3-16 ASCII letters, digits or underscores).
4. Select your installed version and RAM, then click Play.
5. A console checks files, launches Java and displays errors if needed.
   The console stays open while the game runs. Do not close it during play.
   No administrator privileges are required.

JAVA
The engine reads javaVersion from version JSON (default Java 8 for older
metadata) and looks for a matching JDK in the Minecraft runtime directory,
JAVA_HOME, standard vendor directories, and PATH. Set JavaPath explicitly
if detection fails. Typical versions: 1.16.5 -> Java 8, 1.18-1.20.4 -> 17,
1.20.5-1.21.x -> 21. Metadata is authoritative.

OPTIONAL CONFIGURATION
After running once, edit %LOCALAPPDATA%\SanieLauncher\profile.ini.
Add this section with your actual paths (omit keys you do not need):
[Launch]
GameDir=D:\Games\.minecraft
JavaPath=C:\Program Files\Eclipse Adoptium\jdk-21\bin\java.exe

LOGS
%LOCALAPPDATA%\SanieLauncher\launcher.log (launch checks and errors)
<GameDir>\logs\latest.log (Minecraft log, if the game initialized logging)
Missing files are reported, not silently downloaded. Only run trusted
version metadata, JARs and scripts; a local game executes Java code.

SCOPE AND LIMITATIONS
Modern arguments and legacy minecraftArguments, rules, inherited metadata,
classpath, assets, old native classifiers, offline UUIDs, and Java launch
are implemented. Primary target: installed vanilla versions from the UI.
Forge/Fabric/OptiFine and other custom installations are not guaranteed;
mod download/install remains a preview. Avatars do not change in-game skins.
The UI version list is unchanged and is not a live installation catalog.
The game-folder button still opens the default %APPDATA%\.minecraft folder;
GameDir overrides affect the launch engine only.
No Microsoft authentication, valid session tokens, DRM patches,
or bypass of authenticated multiplayer checks are implemented.
The old data/profile.txt is not automatically migrated.

BUILD
Visual Studio 2022 with Desktop development with C++, CMake:
  cmake -S . -B build
  cmake --build build --config Release
CMake copies LaunchOffline.ps1 beside the built EXE.
Windows EXE cross-compilation succeeded using MinGW-w64.
PowerShell syntax and isolated escaping/rule tests were checked.
Full Minecraft gameplay and Windows runtime testing were NOT performed.

Not affiliated with Mojang or Microsoft.


Дополнительные настройки (обновление):
- Сохранение выбранной цветовой темы, светлого/тёмного режима и анимаций.
- Переключатели режима закрытия и отображения окна запуска.
- Настройка лимита FPS: без ограничения, 60, 120 или 240.
- Новые параметры лаунчера автоматически сохраняются в profile.ini.
