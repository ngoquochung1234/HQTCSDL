@echo off
chcp 65001 >nul
pushd "%~dp0"
call npm.cmd run setup
if errorlevel 1 goto failed
echo Mo http://localhost:3001. Mat khau demo: Aurora123!
call npm.cmd start
popd
exit /b
:failed
echo Xem loi phia tren va README.md.
pause
popd
exit /b 1
