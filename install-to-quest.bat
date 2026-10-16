@echo off
setlocal EnableExtensions
REM OpenMW-VR fitness mod for Meta Quest - installer / updater.
REM Downloads the latest game build and fitness scripts from GitHub, installs them on the
REM USB-connected Quest, copies your Morrowind data (first time only), launches the game,
REM and afterwards saves logs, screenshots and a backup of your saves on this PC.
REM Needs: Quest in developer mode + USB, SideQuest (for adb), your own copy of Morrowind.
set "WORK=%USERPROFILE%\Documents\openmw-fitness"
if not exist "%WORK%" mkdir "%WORK%"
set "APK=%WORK%\openmw-vr-quest.apk"
set "APK_URL=https://github.com/BrianChase515/openmw-vr-quest-fit/raw/apk/openmw-vr-quest.apk"
set "PKG=org.openmw.vr"
set "QDATA=/sdcard/Morrowind/Data Files"

REM ---- Find Morrowind's "Data Files" folder (remembered after the first run) ----
set "DATA="
if exist "%WORK%\morrowind-path.txt" set /p DATA=<"%WORK%\morrowind-path.txt"
if defined DATA if not exist "%DATA%\Morrowind.esm" set "DATA="
if not defined DATA for %%D in (C D E F G H) do for %%P in (
  "%%D:\Program Files (x86)\Steam\steamapps\common\Morrowind\Data Files"
  "%%D:\Program Files\Steam\steamapps\common\Morrowind\Data Files"
  "%%D:\Program Files\steamapps\common\Morrowind\Data Files"
  "%%D:\SteamLibrary\steamapps\common\Morrowind\Data Files"
  "%%D:\Steam\steamapps\common\Morrowind\Data Files"
  "%%D:\GOG Games\Morrowind\Data Files"
  "%%D:\Program Files (x86)\GOG Galaxy\Games\Morrowind\Data Files"
) do if not defined DATA if exist "%%~P\Morrowind.esm" set "DATA=%%~P"
if not defined DATA (
  echo Could not find Morrowind automatically.
  set /p DATA=Paste the full path of your Morrowind "Data Files" folder: 
)
set "DATA=%DATA:"=%"
if not exist "%DATA%\Morrowind.esm" (
  echo Morrowind.esm was not found in "%DATA%".
  pause & exit /b 1
)
> "%WORK%\morrowind-path.txt" echo %DATA%
echo Morrowind data: %DATA%

set "ADB="
if exist "%APPDATA%\SideQuest\platform-tools\adb.exe" set "ADB=%APPDATA%\SideQuest\platform-tools\adb.exe"
if not defined ADB if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" set "ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
if not defined ADB for /f "delims=" %%A in ('where adb 2^>nul') do if not defined ADB set "ADB=%%A"
if not defined ADB (
  echo Could not find adb. Open SideQuest once, then run this again.
  pause & exit /b 1
)
"%ADB%" get-state >nul 2>&1 || (
  echo Quest not detected. Plug it in, put it on, and allow USB debugging.
  pause & exit /b 1
)

echo == Downloading the latest build from GitHub
curl -L --fail -o "%APK%.part" "%APK_URL%" && move /y "%APK%.part" "%APK%" >nul
if exist "%APK%.part" del "%APK%.part"
if not exist "%APK%" (
  echo Download failed and no earlier APK is saved. Check your internet connection.
  pause & exit /b 1
)

echo == Downloading the latest fitness scripts from GitHub
curl -L --fail -s -o "%WORK%\fitness-mod.zip" "https://github.com/BrianChase515/openmw-vr-quest-fit/raw/apk/fitness-mod.zip"
if exist "%WORK%\fitness-mod.zip" (
  if exist "%WORK%\fitness-mod" rmdir /s /q "%WORK%\fitness-mod"
  mkdir "%WORK%\fitness-mod"
  tar -xf "%WORK%\fitness-mod.zip" -C "%WORK%\fitness-mod" && echo Fitness scripts updated.
) else (
  echo !! Could not download the scripts - using the copy already in %WORK%\fitness-mod
)

echo == Installing APK
"%ADB%" install -r "%APK%" > "%WORK%\install-result.txt" 2>&1
type "%WORK%\install-result.txt"
findstr /c:"INSTALL_FAILED_UPDATE_INCOMPATIBLE" "%WORK%\install-result.txt" >nul && call :reinstall
findstr /c:"Success" "%WORK%\install-result.txt" >nul || echo !! Install did not succeed - continuing with the version already on the Quest.
"%ADB%" shell pm grant %PKG% android.permission.READ_EXTERNAL_STORAGE
"%ADB%" shell pm grant %PKG% android.permission.WRITE_EXTERNAL_STORAGE

if exist "%WORK%\.data-copied-v2" (
  echo == Morrowind data already on the Quest, skipping copy
) else (
  echo == Copying Morrowind data to the Quest's Morrowind folder, about 600 MB
  "%ADB%" shell mkdir -p /sdcard/Morrowind
  "%ADB%" push "%DATA%" /sdcard/Morrowind/ || (pause & exit /b 1)
  echo == Removing the earlier copy the game couldn't see
  "%ADB%" shell rm -rf /sdcard/Android/data/%PKG%/files/data/* /sdcard/omw-staging
  echo done> "%WORK%\.data-copied-v2"
)

REM A data folder created over USB inside the app's storage is unreadable to the game and crashes it.
"%ADB%" shell rm -rf /sdcard/Android/data/%PKG%/files/data /sdcard/omw-staging /sdcard/omw-fit-staging

echo == Copying the fitness mod scripts
if exist "%WORK%\fitness-mod\fitness.omwscripts" (
  "%ADB%" push "%WORK%\fitness-mod\fitness.omwscripts" "%QDATA%/" >nul
  "%ADB%" push "%WORK%\fitness-mod\scripts" "%QDATA%/" >nul && echo Fitness scripts copied.
) else (
  echo !! fitness-mod folder not found in %WORK%
)

REM ---- Optional comeback anthem: any songs you own in Documents\openmw-fitness\music ----
if not exist "%WORK%\music" mkdir "%WORK%\music"
dir /b /a-d "%WORK%\music" 2>nul | findstr . >nul && (
  "%ADB%" shell rm -rf "'%QDATA%/music/fitness'"
  "%ADB%" shell mkdir -p "'%QDATA%/music/fitness'"
  for %%F in ("%WORK%\music\*") do "%ADB%" push "%%F" "%QDATA%/music/fitness/" >nul
  echo Anthem music copied.
)

REM Saves now live in /sdcard/Morrowind/userdata (survives reinstalls). Put the PC backup
REM there if the Quest has none yet.
"%ADB%" shell "ls /sdcard/Morrowind/userdata/saves/*/*.omwsave" >nul 2>&1
if errorlevel 1 if exist "%WORK%\saves-backup\saves" (
  echo == Restoring your saves from the PC backup
  "%ADB%" shell mkdir -p /sdcard/Morrowind/userdata
  "%ADB%" push "%WORK%\saves-backup\saves" /sdcard/Morrowind/userdata/ >nul && echo Saves restored.
)

echo == Quick check of what the game will see:
"%ADB%" shell "ls '%QDATA%'"
"%ADB%" shell "ls '%QDATA%'" > "%WORK%\quest-files.txt" 2>&1

echo.
echo == Launching. Once the game is up in the headset you can unplug the cable.
echo    TIP: take screenshots in the headset - hold the Meta button and pull the right trigger.
"%ADB%" logcat -c
"%ADB%" shell touch /sdcard/omw-launch-marker
"%ADB%" shell am start -n %PKG%/.OpenMWActivity
echo.
echo When you're done testing, plug the headset back in and press any key here.
pause >nul
"%ADB%" logcat -d -v time > "%WORK%\quest-log.txt"
"%ADB%" shell "cat /sdcard/Android/data/%PKG%/files/config/openmw.log 2>/dev/null" > "%WORK%\openmw-log.txt"
echo == Backing up your saves to the PC
if not exist "%WORK%\saves-backup" mkdir "%WORK%\saves-backup"
"%ADB%" pull /sdcard/Morrowind/userdata/saves "%WORK%\saves-backup" >nul 2>&1
echo == Collecting headset screenshots taken this session
if not exist "%WORK%\screenshots" mkdir "%WORK%\screenshots"
for /f "delims=" %%S in ('call "%ADB%" shell find /sdcard/Oculus/Screenshots -type f -newer /sdcard/omw-launch-marker 2^>nul') do "%ADB%" pull "%%S" "%WORK%\screenshots" >nul
echo Logs and screenshots saved in %WORK%. Tell Claude how it went.
pause
exit /b 0

:reinstall
echo.
echo The new build is signed differently from the one on your Quest, so Android won't update it.
echo Fix: uninstall the old one first. This deletes the game's saves ON THE QUEST - they get
echo copied to %WORK%\saves-backup on your PC first. Your Morrowind files are not affected.
set /p ANSWER=Uninstall the old version and install the new one? (Y/N) 
if /i not "%ANSWER%"=="Y" exit /b 0
if not exist "%WORK%\saves-backup" mkdir "%WORK%\saves-backup"
"%ADB%" pull /sdcard/Android/data/%PKG%/files/saves "%WORK%\saves-backup" >nul 2>&1
"%ADB%" uninstall %PKG%
"%ADB%" install "%APK%" > "%WORK%\install-result.txt" 2>&1
type "%WORK%\install-result.txt"
"%ADB%" shell pm grant %PKG% android.permission.READ_EXTERNAL_STORAGE
"%ADB%" shell pm grant %PKG% android.permission.WRITE_EXTERNAL_STORAGE
exit /b 0
