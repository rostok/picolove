-- love 11.4 uses lua 5.1
__picolove_version = "0.1.1"

scale = 2
xpadding = 0
ypadding = 0
__pico_resolution = { 480, 270, scale }
-- __pico_resolution = { 640, 360, scale }
-- __pico_resolution = { 960, 540, scale }
-- __pico_resolution = { 256, 256, scale }
-- __pico_resolution = { 128, 128, scale }
__pico_fps_limiter = 60 -- if set each loop cycle will wait so FPS will target this setting, to disable set to 0
__pico_cart = nil
__pico_cart = "schifahren-game-combined.p8"
__no_pcall = not true -- if true api.run() will call f() instead of pcall(f) for better traceback debugging
__profilingS = -1 -- special profiling, set above 0 will profile this number of frames, at 0 writes report, at negative does nothing 
__profilingU = -1 -- update profiling 
__profilingD = -1 -- draw profiling
__profilingFrames = 30
__pico_nofocus_update = true -- if true will not pause on loosing focus
function love.conf(t)
	t.console = true
	t.identity = "picolove"
	t.version = "11.4"
	t.window.title = "PICOLÖVE"
	t.window.icon = "icon.png"
	t.window.width = __pico_resolution[1] * scale + xpadding * scale * 2
	t.window.height = __pico_resolution[2] * scale + ypadding * scale * 2
	t.window.resizable = true
end
