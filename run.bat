::love . schifahren-game-combined.p8  | tee
::lovec is better for windows terminal execution
taskkill /f /im love.exe /im lovec.exe
set __COMPAT_LAYER=~ HIGHDPIAWARE
start /separate lovec . schifahren-game-combined.p8

