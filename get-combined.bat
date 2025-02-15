@echo off
::set a=%DATE:-=%-%TIME::=%
::set a=%a: =0%
::set a=%a:~0,-5%
for /f "tokens=2 delims==" %%i in ('wmic os get localdatetime /value') do set datetime=%%i
set year=%datetime:~0,4%
set month=%datetime:~4,2%
set day=%datetime:~6,2%
set hours=%datetime:~8,2%
set minutes=%datetime:~10,2%
set seconds=%datetime:~12,2%
set a=%year%%month%%day%-%hours%%minutes%
if exist schifahren-game-combined.p8 ( copy schifahren-game-combined.p8 trash\schifahren-game-combined-%a%.p8 )
::call shrinko8 --input-count pico8\schifahren-game.p8 schifahren-game-combined.p8 
::call shrinko8 --no-minify-rename --no-minify-spaces --no-minify-lines --no-minify-comments --no-minify-tokens --input-count pico8\schifahren-game.p8 schifahren-game-combined.p8 
python combinelua.py pico8/schifahren-game.p8 schifahren-game-combined.p8 

:: --input-count -c 