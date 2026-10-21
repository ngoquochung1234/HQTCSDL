@echo off
chcp 65001 >nul
pushd "%~dp0"
where node.exe >nul 2>nul
if errorlevel 1 goto missing
where sqlcmd.exe >nul 2>nul
if errorlevel 1 goto missing
if exist "node_modules\qrcode\package.json" goto setup
call npm.cmd ci
if errorlevel 1 goto failed
:setup
call npm.cmd run setup
if errorlevel 1 goto failed
echo.
echo Mo trinh duyet tai http://localhost:3000
echo Tai khoan khach: guest1@demo.local / Aurora123!
echo Tai khoan dieu phoi: itinerary@demo.local / Aurora123!
echo Giu cua so nay mo khi su dung web. Ctrl+C de dung.
echo.
call npm.cmd start
popd
exit /b
:missing
echo Can Node.js va sqlcmd trong PATH. Xem README.md.
goto failed
:failed
echo Khong the khoi dong. Xem thong bao loi phia tren va README.md.
pause
popd
exit /b 1
