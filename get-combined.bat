@echo off
set a=%DATE:-=%-%TIME::=%
set a=%a: =0%
set a=%a:~0,-5%
if exist schifahren-game-combined.p8 ( copy schifahren-game-combined.p8 trash\schifahren-game-combined-%a%.p8 )
::call shrinko8 --input-count pico8\schifahren-game.p8 schifahren-game-combined.p8 
call shrinko8 --no-minify-rename --no-minify-spaces --no-minify-lines --no-minify-comments --no-minify-tokens --input-count pico8\schifahren-game.p8 schifahren-game-combined.p8 

:: --input-count -c 