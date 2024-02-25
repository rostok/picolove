@echo off

setlocal

set command_line=schifahren-game-combined.p8

wmic process where "name='love.exe'" get commandline /value | findstr /i /c:"love.exe" /c:"%command_line%" >nul

if %errorlevel% equ 0 (

    nircmd win activate process love.exe
    nircmd sendkeypress ctrl+r
    nircmd win activate ititle Visual~x20Studio~x20Code

    REM Activate the previously active window using wmic
    for /f "usebackq skip=1 tokens=2 delims=," %%i in (`wmic process where "processid=%PARENT_PID%" get parentprocessid /format:csv`) do (
        for /f "usebackq tokens=2 delims==" %%j in (`wmic process where "processid=%%i" get caption /value ^| findstr /i "Caption"`) do (
            set WINDOW_TITLE=%%j
        )
    )

    REM Activate the previously active window using its title
    nircmd win activate title "%WINDOW_TITLE%"

    echo Keys sent to love.exe, returning to previous window...
    
    ping -n 1 127.0.0.1 > nul
    echo Moving window...
    powershell -Command "(Get-Process -Name love.exe | Select-Object -First 1).MainWindowHandle | foreach { [Windows.Win32.User32]::SetWindowPos($_, [Windows.Win32.User32]::HWND_TOP, -1080, 0, 0, 0, 3) }"
) else (
    echo Process not found, starting new instance...
    start "" "love.exe" . %command_line%
)

endlocal
