@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
set "PROJECT_DIR=%~dp0"
set "CHECK_DIR=%TEMP%\ngoen_ku_pai_nai_git_check"
title Project Git Update

echo.
echo ==============================================
echo   Validate, Commit, and Push Flutter Project
echo ==============================================
echo.

where git >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Git was not found in PATH.
  goto :failed
)

if not exist ".git" (
  echo [ERROR] This folder is not a Git repository.
  goto :failed
)

set "FLUTTER_CMD=flutter"
where flutter >nul 2>nul
if errorlevel 1 set "FLUTTER_CMD=C:\Users\pondz\Documents\Codex\tools\flutter\bin\flutter.bat"

if not exist "%FLUTTER_CMD%" (
  where flutter >nul 2>nul
  if errorlevel 1 (
    echo [ERROR] Flutter was not found.
    goto :failed
  )
)

echo [1/6] Checking tracked signing secrets...
for %%F in (key.properties *.jks *.keystore) do (
  for /f "delims=" %%T in ('git ls-files "%%F" "**/%%F" 2^>nul') do (
    echo [ERROR] Tracked secret file detected: %%T
    echo Remove it from the Git index before pushing.
    goto :failed
  )
)

echo [2/6] Running Flutter Analyze...
if exist "%CHECK_DIR%" rmdir /s /q "%CHECK_DIR%"
mkdir "%CHECK_DIR%" >nul 2>nul
xcopy "%PROJECT_DIR%lib" "%CHECK_DIR%\lib" /E /I /Q /Y >nul
xcopy "%PROJECT_DIR%test" "%CHECK_DIR%\test" /E /I /Q /Y >nul
copy /Y "%PROJECT_DIR%pubspec.yaml" "%CHECK_DIR%\pubspec.yaml" >nul
copy /Y "%PROJECT_DIR%pubspec.lock" "%CHECK_DIR%\pubspec.lock" >nul
copy /Y "%PROJECT_DIR%analysis_options.yaml" "%CHECK_DIR%\analysis_options.yaml" >nul
cd /d "%CHECK_DIR%"
call "%FLUTTER_CMD%" pub get >nul
if errorlevel 1 (
  echo [ERROR] Flutter Pub Get failed in the validation workspace.
  cd /d "%PROJECT_DIR%"
  goto :failed
)
call "%FLUTTER_CMD%" analyze
if errorlevel 1 (
  echo [ERROR] Analyze failed. Nothing was committed.
  cd /d "%PROJECT_DIR%"
  goto :failed
)

echo [3/6] Running Flutter Tests...
call "%FLUTTER_CMD%" test
if errorlevel 1 (
  echo [ERROR] Tests failed. Nothing was committed.
  cd /d "%PROJECT_DIR%"
  goto :failed
)
cd /d "%PROJECT_DIR%"

if /i "%~1"=="--check" goto :check_passed

echo [4/6] Staging project changes...
git status --short
git add --all
git diff --cached --quiet
if not errorlevel 1 (
  echo No new changes. The current commit will be pushed.
  goto :ensure_remote
)

echo.
set "COMMIT_MESSAGE="
set /p "COMMIT_MESSAGE=Commit message: "
if not defined COMMIT_MESSAGE set "COMMIT_MESSAGE=chore: update project"

echo [5/6] Creating commit...
git commit -m "%COMMIT_MESSAGE%"
if errorlevel 1 goto :failed

:ensure_remote
git remote get-url origin >nul 2>nul
if errorlevel 1 (
  echo.
  echo No Git remote is configured.
  echo Create an empty GitHub repository, then paste its URL below.
  echo Example: https://github.com/USERNAME/REPOSITORY.git
  set "REMOTE_URL="
  set /p "REMOTE_URL=GitHub repository URL: "
  if not defined REMOTE_URL (
    echo [ERROR] No URL was provided. Push was skipped.
    goto :failed
  )
  git remote add origin "%REMOTE_URL%"
  if errorlevel 1 goto :failed
)

for /f "delims=" %%B in ('git branch --show-current') do set "CURRENT_BRANCH=%%B"
if not defined CURRENT_BRANCH set "CURRENT_BRANCH=main"

echo [6/6] Pushing origin/%CURRENT_BRANCH%...
git push -u origin "%CURRENT_BRANCH%"
if errorlevel 1 goto :failed

echo.
echo ==============================================
echo   SUCCESS: Project was pushed to Git.
echo ==============================================
git log -1 --oneline
echo.
pause
exit /b 0

:check_passed
echo.
echo ==============================================
echo   CHECK PASSED: Analyze and tests succeeded.
echo ==============================================
exit /b 0

:failed
echo.
echo The operation stopped before pushing invalid changes.
echo Fix the error above and run this file again.
echo.
pause
exit /b 1
