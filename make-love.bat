@echo off
if not exist release mkdir release
if not exist release\love mkdir release\love
for /f "delims=" %%a in ('where love.exe') do ( set love="%%a" )
echo %love%
::-m
call shrinko8 --input-count --no-minify-spaces --no-minify-lines --no-minify-rename --no-minify-tokens pico8\schifahren-game.p8 schifahren-game-combined.p8 
:: to minify code first save patched code. in cart.lua seek 
:: api.writeFile("_code_patched.lua",lua); 
:: then 
:: luamin -f code_patched.lua  > code_patched_min.lua 
7z a -r -tzip schifahren.love -xr!trash -xr!pico8 *.lua *.p8 *.png 
7z a -r -tzip schifahren.love pico8\map*.lua pico8\resources
copy /b %love% + schifahren.love schifahren.exe
7z a schifahren.7z schifahren.exe "C:\Program Files\LOVE\*.dll" 
move schifahren.love release\love
move schifahren.7z release
move schifahren.exe release

