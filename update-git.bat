@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul

cd /d "%~dp0"
title Update Money Project to Git

echo.
echo ==============================================
echo   เงินกูไปไหน - Validate, Commit and Push
echo ==============================================
echo.

where git >nul 2>nul
if errorlevel 1 (
  echo [ERROR] ไม่พบ Git ใน PATH
  goto :failed
)

if not exist ".git" (
  echo [ERROR] โฟลเดอร์นี้ยังไม่ใช่ Git repository
  goto :failed
)

set "FLUTTER_CMD=flutter"
where flutter >nul 2>nul
if errorlevel 1 (
  set "FLUTTER_CMD=C:\Users\pondz\Documents\Codex\tools\flutter\bin\flutter.bat"
)
if not exist "%FLUTTER_CMD%" (
  where flutter >nul 2>nul
  if errorlevel 1 (
    echo [ERROR] ไม่พบ Flutter ทั้งใน PATH และ Codex tools
    goto :failed
  )
)

echo [1/6] ตรวจไฟล์ลับที่ห้าม Commit...
for %%F in (key.properties *.jks *.keystore) do (
  for /f "delims=" %%T in ('git ls-files "%%F" "**/%%F" 2^>nul') do (
    echo [ERROR] พบไฟล์ลับถูก Track: %%T
    echo เอาไฟล์นี้ออกจาก Git index ก่อน Push
    goto :failed
  )
)

echo [2/6] Flutter Analyze...
call "%FLUTTER_CMD%" analyze
if errorlevel 1 (
  echo [ERROR] Analyze ไม่ผ่าน ยกเลิกการ Commit
  goto :failed
)

echo [3/6] Flutter Tests...
call "%FLUTTER_CMD%" test
if errorlevel 1 (
  echo [ERROR] Tests ไม่ผ่าน ยกเลิกการ Commit
  goto :failed
)

echo [4/6] เตรียมไฟล์สำหรับ Commit...
git status --short
git add --all
git diff --cached --quiet
if not errorlevel 1 (
  echo.
  echo ไม่มีการเปลี่ยนแปลงใหม่ จะตรวจและ Push Commit ปัจจุบันต่อ
  goto :ensure_remote
)

echo.
set "COMMIT_MESSAGE="
set /p "COMMIT_MESSAGE=ข้อความ Commit: "
if not defined COMMIT_MESSAGE set "COMMIT_MESSAGE=chore: update project"

echo [5/6] Commit...
git commit -m "%COMMIT_MESSAGE%"
if errorlevel 1 goto :failed

:ensure_remote
git remote get-url origin >nul 2>nul
if errorlevel 1 (
  echo.
  echo ยังไม่มี Git remote กรุณาสร้าง Repository ว่างบน GitHub ก่อน
  echo ตัวอย่าง: https://github.com/USERNAME/REPOSITORY.git
  set "REMOTE_URL="
  set /p "REMOTE_URL=GitHub repository URL: "
  if not defined REMOTE_URL (
    echo [ERROR] ยังไม่ได้ใส่ URL จึงยัง Push ไม่ได้
    goto :failed
  )
  git remote add origin "%REMOTE_URL%"
  if errorlevel 1 goto :failed
)

for /f "delims=" %%B in ('git branch --show-current') do set "CURRENT_BRANCH=%%B"
if not defined CURRENT_BRANCH set "CURRENT_BRANCH=main"

echo [6/6] Push origin/%CURRENT_BRANCH%...
git push -u origin "%CURRENT_BRANCH%"
if errorlevel 1 goto :failed

echo.
echo ==============================================
echo   สำเร็จ: Project ถูกอัปเดตขึ้น Git แล้ว
echo ==============================================
git log -1 --oneline
echo.
pause
exit /b 0

:failed
echo.
echo งานถูกหยุดโดยยังไม่ Push การเปลี่ยนแปลงที่ไม่ผ่านตรวจ
echo แก้ข้อความด้านบนแล้วเปิดไฟล์นี้ใหม่ได้เลย
echo.
pause
exit /b 1
