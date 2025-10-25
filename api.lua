local api = {}

-- why screen starts from 1,1 and not 0,0 ?
-- using love's love.graphics.point and points without flr() on coord results with problem described on https://love2d.org/wiki/love.graphics
-- one can then adjust this with love.graphics.translate which is located in main.lua:restore_camera()
-- but as points start appearing at right positions (still not exactly pico8 style as pico8 floors coordinates)
-- there still is problem with love.graphics.line which for some reason behaves very strange
-- first there is a problem with 1px line 
-- then problem with horizontal or vertival lines
-- various tests with line0 line1 line2 line3 line4, translating px in restore_camera() failed
-- line0 is almost close to original
-- line2 is based on love.graphics.line and is faster

-- possible approach to fix this:
-- use test-gfx.p8 and see how functions behave for s float parameter adjusting coordinates from .1 to 1
-- make restore_camera() use translate with +.5 +.5 this should make pset() use love.graphics.point() to be OK
-- then make line4 align itself with pset()
-- make special case for 1px line
-- check horizontal lines
-- adjust remaining graphics functions like rect rectfill circ circfill oval ovalfill

local ok
ok,table_clear = pcall(require, "table.clear")
api.table_clear = table_clear

local __tempPointsTable = {}

local flr = math.floor
api.math = math
api.string = string
api.tonumber = tonumber
api.love = love
api.bit = bit
api.bitser = require("bitser")
api.utf8 = require("utf8")
utf8 = api.utf8
api.utf8string = require("utf8string")
api.ustring = require("ustring/ustring")
api.debug = debug
api.jit = jit
api.os = os
api.serpent = require("serpent")
api.gifpic = require("gifpic")
api.ffi = require("ffi")
api.love_thread = require("love.thread")
api.love_system = require("love.system")
api.love_timer = require("love.timer")
api._print = print

local function color(c)
	if c ~= pico8.color then -- rostok: skip if this is current color
		-- c = flr(c or 0) % 32
		c = flr(c or 0)
		pico8.color = c
		setColor(c)
	end
end

-- counting colors
-- local colorOrg = color
-- local uniqueColorsCount = 0
-- local uniqueColors = {}
-- local uniqueColorFrame = -1
-- local function color(c)
-- 	colorOrg(c)
--     if uniqueColorFrame ~= pico8.frames then 
--         uniqueColors = {} 
--         uniqueColorFrame = pico8.frames
--         uniqueColorsCount = 0
--     end
--     if not uniqueColors[c] then 
-- 		uniqueColorsCount = uniqueColorsCount + 1
-- 		uniqueColors[c]=true
-- 	end
-- 	pico8.uniqueColorsCount = uniqueColorsCount
-- end

local function warning(msg)
	log(debug.traceback("WARNING: " .. msg, 3))
end

local function _horizontal_line(lines, x0, y, x1)
	table.insert(lines, { x0 + 0.5, y + 0.5, x1 + 1.5, y + 0.5 })
end

local function _plot4points_old(lines, cx, cy, x, y)
	_horizontal_line(lines, cx - x, cy + y, cx + x)
	if y ~= 0 then
		_horizontal_line(lines, cx - x, cy - y, cx + x)
	end
end

local function _plot4points(lines, cx, cy, x, y)
	lines[#lines+1] = { cx - x + 0.5, cy + y + 0.5, cx + x + 1.5, cy + y + 0.5 }
	if y ~= 0 then
		lines[#lines+1] = { cx - x + 0.5, cy - y + 0.5, cx + x + 1.5, cy - y + 0.5 }
	end
end


local function scroll(pixels)
	local base = 0x6000
	local delta = base + pixels * 0x40
	local basehigh = 0x8000
	api.memcpy(base, delta, basehigh - delta)
end

local function setfps(fps)
	pico8.fps = flr(fps)
	if pico8.fps <= 0 then
		pico8.fps = 30
	end
	pico8.frametime = 1 / pico8.fps
end

local function getmousex()
	return flr((love.mouse.getX() - xpadding) / scale)
end

local function getmousey()
	return flr((love.mouse.getY() - ypadding) / scale)
end

-- extra functions provided by picolove
api.warning = warning
api.setfps = setfps

-- returns picolove conf resolution width and height
function api._getresolution()
    return pico8.resolution[1],pico8.resolution[2]
end

-- generic object to expose various api
function api._profileReport(counter, filename, depth)
	profileReport(counter, filename, depth)
end

-- return fullscreen state
function api._getFullScreen(state)
	return love.window.getFullscreen()
end

-- toggles, or if state is set, sets fullscreen
function api._toggleFullScreen(state)
	if state==nil then state = not love.window.getFullscreen() end
	local canvas=love.graphics.getCanvas()
	love.graphics.setCanvas()
	love.window.setFullscreen(state, "desktop")
	--for some reason this isn't called when fullscreen is unset
	love.resize(love.graphics.getWidth(), love.graphics.getHeight())
	love.graphics.setCanvas(canvas)
	return state
end

-- sets pixel perfect value or toggles it if no value is passed, returns current settig
function api._togglePixelPerfect(value)
	if value==nil then 
		pixelperfect = not pixelperfect
	else
		pixelperfect = value
	end
	return pixelperfect
end	

-- collect garbage shiv
function api.collectgarbage(opt,arg)
	return collectgarbage(opt,arg)
end

-- generic object to expose various api
function api._picolove()
	return {
		__profiling=__profiling,
		profile=profile,
		profile_start =   function () profile.start() end,
		profile_stop =    function () profile.stop() end,
		profile_s_start = function () if __profiling.S>0 then profile.start() end end,
		profile_s_stop =  function () if __profiling.S>0 then profile.stop() end end,
		_G=_G,
		timer=love.timer,
		pico8=pico8,
		love=love,
		loaded_code=loaded_code,
		load=function (code) local f = load(code) setfenv(f,pico8.cart) return f() end
	}
end

function api.__picolove_resize_canvas(w,h)
	pico8.screen = love.graphics.newCanvas(w,h)
	pico8.depth  = love.graphics.newCanvas(w, h, { format="depth24stencil8", readable=true})
	pico8.resolution[1] = w
	pico8.resolution[2] = h
end

function api._picolove_end()
	if
		not pico8.cart._update
		and not pico8.cart._update60
		and not pico8.cart._draw
	then
		api.printh("cart finished")
	end
end

function api.setPicoCanvas()
	-- love.graphics.setCanvas(pico8.screen)
	-- love.graphics.setCanvas({pico8.screen,stencil=true,depth=pico8.depth})
	-- love.graphics.setCanvas({pico8.screen,stencil=true,depth=true})
	love.graphics.setCanvas({pico8.screen,stencil=true,depth=true,depthstencil=pico8.depth})
end

function api._picolove_draw()
	love.graphics.setCanvas() -- TODO: Rework this
	love.event.pump()
	api.setPicoCanvas()
	if love.graphics and love.graphics.isActive() then
		love.graphics.origin()
		if love.draw then
			love.draw()
		end
	end
end

function api._getpicoloveversion()
	return __picolove_version
end

function api._getcursorx()
	return pico8.cursor[1]
end

function api._getcursory()
	return pico8.cursor[2]
end

function api._call(code)
	code = patch_lua(code)

	local ok, f, e = pcall(load, code, "repl")
	if not ok or f == nil then
		api.rectfill(0, api._getcursory(), 128, api._getcursory() + 5 + 6, 0)
		api.print("syntax error", 14)
		api.print(api.sub(e, 20), 6)
		return false
	else
		setfenv(f, pico8.cart)
		ok, e = pcall(f)
		if not ok then
			api.rectfill(0, api._getcursory(), 128, api._getcursory() + 5 + 6, 0)
			api.print("runtime error", 14)
			api.print(api.sub(e, 20), 6)
		end
	end
	return true
end

--------------------------------------------------------------------------------
-- PICO-8 API

function api.flip()
	flip_screen()
	love.timer.sleep(pico8.frametime)
end

function api.camera(x, y)
	pico8.camera_x = flr(tonumber(x) or 0)
	pico8.camera_y = flr(tonumber(y) or 0)
	restore_camera()
end

function api.clip(x, y, w, h)
	if type(x) == "number" then
		love.graphics.setScissor(x, y, w, h)
		pico8.clip = { x, y, w, h }
	else
		-- love.graphics.setScissor(0, 0, pico8.resolution[1], pico8.resolution[2])
		-- pico8.clip = { 0, 0, pico8.resolution[1], pico8.resolution[2] }
		love.graphics.setScissor()
		pico8.clip = nil
	end
end

function api.cls(col)
	-- col = flr(tonumber(col) or 0) % 16
	col = flr(tonumber(col) or 0) -- 64 colors

	pico8.clip = nil
	love.graphics.setScissor()
	-- love.graphics.clear(col / 15, 0, 0, 1, true, true)
	love.graphics.clear(col / 63, 0, 0, 1, true, true) -- 64 colors
	pico8.cursor = { 0, 0 }
end

function api.folder(dir)
	if dir == nil then
		love.system.openURL(
			"file://" .. love.filesystem.getWorkingDirectory() .. currentDirectory
		)
	elseif dir == "bbs" then
		api.print("not implemented", 14)
	elseif dir == "backups" then
		api.print("not implemented", 14)
	elseif dir == "config" then
		api.print("not implemented", 14)
	elseif dir == "desktop" then
		love.system.openURL(
			"file://" .. love.filesystem.getUserDirectory() .. "Desktop"
		)
	else
		api.print("useage: folder [location]", 14)
		api.print("locations:", 6)
		api.print("backups bbs config desktop", 6)
	end
end

function api._completecommand(command, path)
	-- TODO: handle depending on command

	local startDir = ""
	local pos = path:find("/", 1, true)
	if pos ~= nil then
		startDir = startDir .. path:sub(1, pos)
		path = path:sub(pos + 1)
	end
	local files = love.filesystem.getDirectoryItems(currentDirectory .. startDir)

	local filteredFiles = {}
	for _, file in ipairs(files) do
		if string.sub(file:lower(), 1, string.len(path)) == path then
			filteredFiles[#filteredFiles + 1] = file
		end
	end
	files = filteredFiles

	local result
	if #files == 0 then
		result = path
	elseif #files == 1 then
		if
			love.filesystem.getInfo(currentDirectory .. startDir .. files[1], "directory") ~= nil
		then
			result = files[1]:lower() .. "/"
		else
			result = files[1]:lower()
		end
	else
		local matches
		local match = path

		repeat
			result = match
			if #match == #files[1] then
				break
			end

			match = files[1]:sub(1, #match + 1)
			matches = 0
			for _, file in ipairs(files) do
				if string.sub(file:lower(), 1, string.len(match)) == match then
					matches = matches + 1
				end
			end
		until matches ~= #files

		result = result:lower()

		if #result == #path then
			-- TODO: remove duplicate code (see api.ls())
			local output = {}
			for _, file in ipairs(files) do
				if love.filesystem.getInfo(currentDirectory .. file, "directory") ~= nil then
					output[#output + 1] = { name = file:lower(), color = 14 }
				elseif file:sub(-3) == ".p8" or file:sub(-4) == ".png" then
					output[#output + 1] = { name = file:lower(), color = 6 }
				else
					output[#output + 1] = { name = file:lower(), color = 5 }
				end
			end

			local count = 0
			love.keyboard.setTextInput(false)
			api.rectfill(0, api._getcursory(), 127, api._getcursory() + 6, 0)
			api.print(#output .. " files", 12)
			for _, item in ipairs(output) do
				for j = 1, #item.name, 32 do
					api.rectfill(0, api._getcursory(), 127, api._getcursory() + 6, 0)
					api.print(item.name:sub(j, j + 32), item.color)
					flip_screen()
					count = count + 1
					if count == 20 then
						api.rectfill(0, api._getcursory(), 127, api._getcursory() + 6, 0)
						api.print("--more--", 12)
						flip_screen()
						local y = api._getcursory() - 6
						api.cursor(0, y)
						api.rectfill(0, y, 127, y + 6, 0)
						api.color(item.color)
						while true do
							local e = love.event.wait()
							if e == "keypressed" then
								break
							end
						end
						count = 0
					end
				end
			end
			love.keyboard.setTextInput(true)
		end
	end

	return command .. " " .. startDir .. result
end

-- TODO: move interactive implementation into nocart
-- TODO: should return table of strings
function api.ls()
	local files = love.filesystem.getDirectoryItems(currentDirectory)
	api.rectfill(0, api._getcursory(), 128, api._getcursory() + 5, 0)
	api.print("directory: " .. currentDirectory, 12)
	local output = {}
	for _, file in ipairs(files) do
		if love.filesystem.getInfo(currentDirectory .. file, "directory") ~= nil then
			output[#output + 1] = { name = file:lower(), color = 14 }
		elseif file:sub(-3) == ".p8" or file:sub(-4) == ".png" then
			output[#output + 1] = { name = file:lower(), color = 6 }
		else
			output[#output + 1] = { name = file:lower(), color = 5 }
		end
	end
	local count = 0
	love.keyboard.setTextInput(false)
	for _, item in ipairs(output) do
		for j = 1, #item.name, 32 do
			api.rectfill(0, api._getcursory(), 128, api._getcursory() + 5, 0)
			api.print(item.name:sub(j, j + 32), item.color)
			flip_screen()
			count = count + 1
			if count == 20 then
				api.rectfill(0, api._getcursory(), 128, api._getcursory() + 5, 0)
				api.print("--more--", 12)
				flip_screen()
				local y = api._getcursory() - 6
				api.cursor(0, y)
				api.rectfill(0, y, 127, y + 6, 0)
				api.color(item.color)
				while true do
					local e, a = love.event.wait()
					if e == "keypressed" then
						if a == "escape" then
							love.keyboard.setTextInput(true)
							return
						else
							love.event.clear() -- consume keypress
						end
						break
					end
				end
				count = 0
			end
		end
	end
	love.keyboard.setTextInput(true)
end

api.dir = api.ls

function api.cd(name)
	local output, count

	if #name > 0 then
		name = name .. "/"
	end

	-- filter /TEXT//$ -> /
	count = 1
	while count > 0 do
		name, count = name:gsub("//", "/")
	end

	local newDirectory = currentDirectory .. name

	if name == "/" then
		newDirectory = "/"
	end

	-- filter /TEXT/../ -> /
	count = 1
	while count > 0 do
		newDirectory, count = newDirectory:gsub("/[^/]*/%.%./", "/")
	end

	-- filter /TEXT/..$ -> /
	count = 1
	while count > 0 do
		newDirectory, count = newDirectory:gsub("/[^/]*/%.%.$", "/")
	end

	local failed = newDirectory:find("%.%.") ~= nil
	failed = failed or newDirectory:find("/[ ]+/") ~= nil

	if #name == 0 then
		output = "directory: " .. currentDirectory
	elseif failed then
		if newDirectory == "/../" then
			output = "cd: failed"
		else
			output = "directory not found"
		end
	elseif love.filesystem.getInfo(newDirectory) ~= nil then
		currentDirectory = newDirectory
		output = currentDirectory
	else
		failed = true
		output = "directory not found"
	end

	if not failed then
		api.rectfill(
			0,
			api._getcursory(),
			128,
			api._getcursory() + 5 + api.flr(#output / 32) * 6,
			0
		)
		api.color(12)
		for i = 1, #output, 32 do
			api.print(output:sub(i, i + 32))
		end
	else
		api.rectfill(0, api._getcursory(), 128, api._getcursory() + 5, 0)
		api.print(output, 7)
	end
end

function api.mkdir(...)
	local name = select(1, ...)
	if select("#", ...) == 0 then
		api.rectfill(0, api._getcursory(), 128, api._getcursory() + 5, 0)
		api.print("mkdir [name]", 6)
	elseif name ~= nil then
		love.filesystem.createDirectory(currentDirectory .. name)
	end
end

function api.install_demos()
	-- TODO: implement this
end

function api.install_games()
	-- TODO: implement this
end

function api.keyconfig()
	-- TODO: implement this
end

function api.splore()
	-- TODO: implement this
end

function api.pset(x, y, col)
	if col and col ~= pico8.color then color(col) end -- rostok: skip color if same
	love.graphics.points(flr(x), flr(y))
	-- love.graphics.points(x, y) -- stick to love coords
end

function api.psets(col,...)
	-- if col ~= pico8.color then color(col) end -- rostok: skip color if same

	-- hard coded inline color change
	col = col % 64 - col % 1 -- 64 colors
	if col ~= pico8.color then
		pico8.color = col
		setColor(col)
	end

	love.graphics.points(...)
end

api._canvasFrameNumber = nil
api._canvasGrabbed = nil

function api.pget(x, y)
	x= x - pico8.camera_x - 1
	y= y - pico8.camera_y - 1
	if
		x >= 0
		and x < pico8.resolution[1]
		and y >= 0
		and y < pico8.resolution[2]
	then
		if api._canvasFrameNumber~=pico8.frames then
			api._canvasFrameNumber = pico8.frames
			love.graphics.setCanvas()
			api._canvasGrabbed = pico8.screen:newImageData()
			api._canvasGrabbedW,api._canvasGrabbedH = api._canvasGrabbed:getDimensions()
			api.setPicoCanvas()
		end
		local r = 0
		if x >= 0 and x < api._canvasGrabbedW and y >= 0 and y < api._canvasGrabbedH then r = api._canvasGrabbed:getPixel(flr(x), flr(y)) end
		-- return r*15
		return flr(r*63+0.5) -- 64 colors
	end
	return -1
end

function api.pgetOLD(x, y)
	x= x - pico8.camera_x
	y= y - pico8.camera_y
	if
		x >= 0
		and x < pico8.resolution[1]
		and y >= 0
		and y < pico8.resolution[2]
	then
		love.graphics.setCanvas()
		local __screen_img = pico8.screen:newImageData()
		api.setPicoCanvas()
		local r = __screen_img:getPixel(flr(x), flr(y))
		-- return r*15
		return r*63+0.5 -- 64 colors
	end
	-- warning(string.format("pget out of screen %d, %d", x, y))
	return 0
end

api.color = color
-- function api.color(col)
-- 	color(col)
-- end

-- workaround for non printable chars
local tostring_org = tostring
local function tostring(str)
	return tostring_org(str)
	--return (tostring_org(str):gsub("[^%z\32-\127]", "8"))
end

-- comment this to remove diactrics substitution
api.glyph_diactrics = {
  ["é"] = "e",
  ["É"] = "E",
  ["è"] = "e",
  ["È"] = "E",
  ["ê"] = "e",
  ["Ê"] = "E",
  ["ë"] = "e",
  ["Ë"] = "E",
  ["à"] = "a",
  ["À"] = "A",
  ["â"] = "a",
  ["Â"] = "A",
  ["ä"] = "a",
  ["Ä"] = "A",
  ["î"] = "i",
  ["Î"] = "I",
  ["ï"] = "i",
  ["Ï"] = "I",
  ["ô"] = "o",
  ["Ô"] = "O",
  ["ö"] = "o",
  ["Ö"] = "O",
  ["ù"] = "u",
  ["Ù"] = "U",
  ["û"] = "u",
  ["Û"] = "U",
  ["ü"] = "u",
  ["Ü"] = "U",
  ["ç"] = "c",
  ["Ç"] = "C",
  ["ÿ"] = "y",
	["ą"] = "a\as;\ax-2;\ayh;\ai;\ap;",
	["ę"] = "e\as;\ax-2;\ayh;\ai;\ap;",
	["ć"] = "c\as;\b\ax3;\ay1;\ai;\ax1;\ay-1;\ai;\ap;",
	["ń"] = "n\as;\b\ax3;\ay1;\ai;\ax1;\ay-1;\ai;\ap;",
	["ł"] = "l\as;\ax-2;\ay3;\ai;\ax1;\ay-1;\ai;\ap;",
	["ó"] = "o\as;\b\ax3;\ay1;\ai;\ap;",
	["ś"] = "s\as;\b\ax3;\ay1;\ai;\ap;",
	["ż"] = "z\as;\b\ax3;\ay1;\ai;\ap;",
	["ź"] = "z\as;\b\ax3;\ay1;\ai;\ax1;\ay-1;\ai;\ap;",
	["Ą"] = "A\as;\ax-2;\ayh;\ai;\ap;",
	["Ę"] = "E\as;\ax-2;\ayh;\ai;\ap;",
	["Ć"] = "C\as;\b\ax3;\ay0;\ai;\ap;",
	["Ń"] = "N\as;\ax-3;\ai;\ap;",
	["Ł"] = "L\as;\ax-3;\ay3;\ai;\ax1;\ay-1;\ai;\ap;",
	["Ó"] = "O\as;\b\ax3;\ai;\ap;",
	["Ś"] = "S\as;\ax-2;\ai;\ap;",
	["Ż"] = "Z\as;\b\ax2;\ai;\ap;",
	["Ź"] = "Z\as;\b\ax3;\ai;\ap;",
	["_font0"] = {
	   ["ą"] = "a\as;\ax-2;\ayh;\ai;\ap;",
	   ["ę"] = "e\as;\ax-2;\ayh;\ai;\ap;",
	   ["ć"] = "c\as;\b\ax3;\ai;\ap;",
	   ["ń"] = "n\as;\b\ax3;\ai;\ap;",
	   ["ł"] = "l\as;\ax-2;\ay3;\ai;\ax1;\ay-1;\ai;\ap;",
	   ["ó"] = "o\as;\b\ax2;\ai;\ap;",
	   ["ś"] = "s\as;\b\ax2;\ai;\ap;",
	   ["ż"] = "z\as;\b\ax2;\ai;\ap;",
	   ["ź"] = "z\as;\b\ax3;\ai;\ap;",
	   ["Ą"] = "A\as;\ax-2;\ayh;\ai;\ap;",
	   ["Ę"] = "E\as;\ax-2;\ayh;\ai;\ap;",
	   ["Ć"] = "C\as;\b\ax2;\ay1;\ai;\ap;",
	   ["Ń"] = "N\as;\ax-1;\ay1;\ai;\ap;",
	   ["Ł"] = "L\as;\ax-2;\ay3;\ai;\ax1;\ay-1;\ai;\ap;",
	   ["Ó"] = "O\as;\b\ax2;\ay1;\ai;\ap;",
	   ["Ś"] = "S\as;\ax-2;\ay1;\ai;\ap;",
	   ["Ż"] = "Z\as;\b\ax2;\ay1;\ai;\ap;",
	   ["Ź"] = "Z\as;\b\ax3;\ay1;\ai;\ap;",
	},
	["_font3"] = {
	   ["ą"] = "a\as;\ax-2;\ay12;\ai;\ax1;\ay1;\ai;\ap;",
	   ["ę"] = "e\as;\ax-2;\ay12;\ai;\ax1;\ay1;\ai;\ap;",
	   ["Ą"] = "A\as;\ax-2;\ay12;\ai;\ax1;\ay1;\ai;\ap;",
	   ["Ę"] = "E\as;\ax-2;\ay12;\ai;\ax1;\ay1;\ai;\ap;",
	   ["ć"] = "c\as;\ax-4;\ay4;\ai;\ay-1;\ax1;\ai;\ap;",
	   ["ó"] = "o\as;\ax-4;\ay4;\ai;\ay-1;\ax1;\ai;\ap;",
	   ["ś"] = "s\as;\ax-4;\ay4;\ai;\ay-1;\ax1;\ai;\ap;",
	   ["ń"] = "n\as;\ax-4;\ay4;\ai;\ay-1;\ax1;\ai;\ap;",
	   ["ź"] = "z\as;\ax-4;\ay4;\ai;\ay-1;\ax1;\ai;\ap;",
	   ["Ć"] = "C\as;\ax-4;\ay2;\ai;\ay-1;\ax1;\ai;\ap;",
	   ["Ó"] = "O\as;\ax-4;\ay2;\ai;\ay-1;\ax1;\ai;\ap;",
	   ["Ś"] = "S\as;\ax-4;\ay2;\ai;\ay-1;\ax1;\ai;\ap;",
	   ["Ń"] = "N\as;\ax-4;\ay2;\ai;\ay-1;\ax1;\ai;\ap;",
	   ["Ź"] = "Z\as;\ax-4;\ay2;\ai;\ay-1;\ax1;\ai;\ap;",
	   ["ż"] = "z\as;\ax-4;\ay4;\ai;\ax1;\ai;\ap;",
	   ["Ż"] = "Z\b-",
	   ["ł"] = "l\as;\b\ax2;\ay9;\ai;\ax1;\ay-1;\ai;\ax3;\ay-3;\ai;\ax1;\ay-1;\ai;\ap;",
	   ["Ł"] = "L\as;\b\ax4;\ay7;\ai;\ax1;\ay-1;\ai;\ax1;\ay-1;\ai;\ap;",
	},
	["_font4"] = {
	   ["ą"] = api.utf8.char(224),
	   ["Ą"] = api.utf8.char(192),
	   ["ć"] = api.utf8.char(227),
	   ["Ć"] = api.utf8.char(195),
	   ["ę"] = api.utf8.char(230),
	   ["Ę"] = api.utf8.char(198),
	   ["ł"] = api.utf8.char(249),
	   ["Ł"] = api.utf8.char(217),
	   ["ń"] = api.utf8.char(241),
	   ["Ń"] = api.utf8.char(209),
	   ["ó"] = api.utf8.char(243),
	   ["Ó"] = api.utf8.char(211),
	   ["ś"] = api.utf8.char(250),
	   ["Ś"] = api.utf8.char(218),
	   ["ź"] = api.utf8.char(234),
	   ["Ź"] = api.utf8.char(202),
	   ["ż"] = api.utf8.char(253),
	   ["Ż"] = api.utf8.char(221),
	},
	["_font5"] = {
    ["ą"] = api.utf8.char(224-10), -- 214
    ["Ą"] = api.utf8.char(192-10), -- 182
    ["ć"] = api.utf8.char(227-10), -- 217
    ["Ć"] = api.utf8.char(195-10), -- 185
    ["ę"] = api.utf8.char(230-10), -- 220
    ["Ę"] = api.utf8.char(198-10), -- 188
    ["ł"] = api.utf8.char(249-10), -- 239
    ["Ł"] = api.utf8.char(217-10), -- 207
    ["ń"] = api.utf8.char(241-10), -- 231
    ["Ń"] = api.utf8.char(209-10), -- 199
    ["ó"] = api.utf8.char(243-10), -- 232
    ["Ó"] = api.utf8.char(211-10), -- 201
    ["ś"] = api.utf8.char(250-10), -- 240
    ["Ś"] = api.utf8.char(218-10), -- 208
    ["ż"] = api.utf8.char(253-10), -- 243
    ["ź"] = api.utf8.char(234-10), -- 224
    ["Ż"] = api.utf8.char(221-10-3-10-6), -- 192
    ["Ź"] = api.utf8.char(202-10), -- 192
	}  
}

function api._font(num)
    -- Initialize the FONTS table if it doesn't exist
    if not api.FONTS then
        api.FONTS = {}

        -- Load all font data into the FONTS table
        local glyphs
        -- Font 0: 3x5
        glyphs = ""
        for i = 32, 153 do
            glyphs = glyphs .. (api.glyph_edgecases[api.pico8_glyphs[i]] or api.pico8_glyphs[i])
        end
        api.FONTS[0] = {
			glyphs = glyphs,
            font = love.graphics.newImageFont("font.png", glyphs, 1),
            glyphWidth = 4,
            glyphHeight = 6
        }
        -- Font 1: 4x5
        glyphs = ""
        for i = 32, 127 do glyphs = glyphs .. string.char(i) end
        api.FONTS[1] = {
			glyphs = glyphs,
            font = love.graphics.newImageFont("font4x6.png", glyphs, 1),
            glyphWidth = 5,
            glyphHeight = 6
        }
        -- Font 2: 4x6
        glyphs = ""
        for i = 32, 127 do glyphs = glyphs .. string.char(i) end
        api.FONTS[2] = {
			glyphs = glyphs,
			-- font = love.graphics.newFont("unnamed-4x6.ttf", 6),
            font = love.graphics.newImageFont("unnamed-4x6.png", glyphs, 1),
            glyphWidth = 5,
            glyphHeight = 7
        }
        -- Font 3: 8x14
        glyphs = ""
        for i = 32, 127 do glyphs = glyphs .. string.char(i) end
        api.FONTS[3] = {
			glyphs = glyphs,
            font = love.graphics.newImageFont("fontvga8x14-32-127.png", glyphs, 1),
            glyphWidth = 8,
            glyphHeight = 14
        }
        -- Font 4: 9x9
        glyphs = ""
        for i = 32, 255 do
            -- glyphs = glyphs .. (api.glyph_edgecases[api.pico8_glyphs[i]] or api.pico8_glyphs[i] or string.char(i))
            -- glyphs = glyphs .. (i<127 and string.char(i) or api.utf8.char(i)) 
            -- glyphs = glyphs .. string.char(i)
            glyphs = glyphs .. api.utf8.char(i)
        end
        api.FONTS[4] = {
			glyphs = glyphs,
            font = love.graphics.newImageFont("smaf1257-04-f-9x10.png", glyphs, 1),
            glyphWidth = 9,
            glyphHeight = 9,
			-- hkerning = -1,
			varWidth = true
        }
        api.FONTS[5] = {
			glyphs = glyphs,
            font = love.graphics.newImageFont("Tiny5-PL-v2-10x9.png",glyphs,1),
            glyphWidth = 9,
            glyphHeight = 9,
			-- hkerning = -1,
			varWidth = true
        }

		for _,F in pairs(api.FONTS) do
			local mw,mh = 0,0
			for i=1,api.utf8.len(#F.glyphs) do
				local c = api.utf8sub(F.glyphs,i,i)
				if c then 
					mw = math.max(mw,F.font:getWidth(c))
					mh = math.max(mh,F.font:getHeight(c))
				end
			end
			-- logic("font ".._," org "..F.glyphWidth.."x"..F.glyphHeight," new "..mw.."x"..mh)
			F.glyphWidth  = mw
			F.glyphHeight = mh
		end
    end

    -- Set num default and clamp it to the valid range
    num = num or 0
    if num > #api.FONTS then num = 0 end

    -- Set the font using the preloaded data
    local fontData = api.FONTS[num]
    love.graphics.setFont(fontData.font)
    fontData.font:setFilter("nearest", "nearest")
    
    api.GLYPH_W = fontData.glyphWidth
    api.GLYPH_H = fontData.glyphHeight
    api.GLYPH_VAR_W = fontData.varWidth
    api.FONTNUM = num
	api.FONTDATA = fontData
end


function api._glyphSize()
	return api.GLYPH_W,api.GLYPH_H,api.FONTNUM,api.GLYPH_VAR_W
end

function api.printIntoCanvas(text)
    -- Get current canvas to restore later
    local originalCanvas = love.graphics.getCanvas()
    
    -- Measure text to determine canvas size
    local font = love.graphics.getFont() or love.graphics.newFont()
    local textWidth = font:getWidth(text)
    local textHeight = font:getHeight()

    -- Create a new canvas sized to fit the text, make canvas at least 1x1
    local canvas = love.graphics.newCanvas(math.max(textWidth,1), math.max(textHeight,1))
    
    -- Render the text to the canvas
    love.graphics.setCanvas(canvas)
	love.graphics.setShader(pico8.text_shader)
	love.graphics.push()
    love.graphics.origin()
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(text, 0, 0)
	love.graphics.pop()
    love.graphics.setCanvas(originalCanvas)
	love.graphics.setShader(pico8.draw_shader)
    
    -- Get image data from the canvas
    local imageData = canvas:newImageData()
    
    -- Convert image data to 0,1 table
    local w, h = imageData:getWidth(), imageData:getHeight()
    local tableData = {}

    for y = 0, h - 1 do
        tableData[y + 1] = {}
        for x = 0, w - 1 do
            local r, g, b, a = imageData:getPixel(x, y)
            -- If alpha > 0, set to 1 (text), otherwise 0 (empty space)
            tableData[y + 1][x + 1] = (r > 0) and 1 or 0
        end
    end

    -- Return the table, width, and height
    return tableData, w, h
end

function api.print0(...)
	local w,h,f = api._glyphSize()
	api._font(0)
	local x,y,z = api.print(...)
	api._font(f)
	return x,y,z
end

function api.print1(...)
	local w,h,f = api._glyphSize()
	api._font(1)
	local x,y,z = api.print(...)
	api._font(f)
	return x,y,z
end

function api.print2(...)
	local w,h,f = api._glyphSize()
	api._font(2)
	local x,y,z = api.print(...)
	api._font(f)
	return x,y,z
end

function api.print3(...)
	local w,h,f = api._glyphSize()
	api._font(3)
	local x,y,z = api.print(...)
	api._font(f)
	return x,y,z
end

function api.utf8sub(s, i, j)
    -- Get the start and end character positions, default j = i if not provided
    j = j or i

    -- Convert negative indices to positive
    local len = api.utf8.len(s)
    if i < 0 then i = len + i + 1 end
    if j < 0 then j = len + j + 1 end

    -- Find byte offsets for start and end+1 (Lua is 1-based)
    local start_byte = api.utf8.offset(s, i)
    local end_byte = api.utf8.offset(s, j + 1)

    if start_byte and end_byte then
        return s:sub(start_byte, end_byte - 1)
    elseif start_byte then
        return s:sub(start_byte)
    else
        return ""
    end
end

-- Vanilla Lua 5.1 UTF-8 validator that removes invalid characters.
-- Returns the sanitized string.
function api.utf8validate(input_str)
    if type(input_str) ~= "string" then
        -- Or error("Input must be a string")
        return "", "Input must be a string"
    end

    local result_bytes = {} -- Store byte values of valid characters
    local i = 1
    local n = #input_str

    while i <= n do
        local b1 = string.byte(input_str, i)

        if b1 < 0x80 then -- 1-byte sequence (0xxxxxxx, ASCII 0-127)
            table.insert(result_bytes, b1)
            i = i + 1
        elseif b1 >= 0xC2 and b1 <= 0xDF then -- 2-byte sequence (110xxxxx 10xxxxxx)
            -- Expected: C2-DF followed by 80-BF
            if i + 1 <= n then
                local b2 = string.byte(input_str, i + 1)
                if b2 >= 0x80 and b2 <= 0xBF then
                    table.insert(result_bytes, b1)
                    table.insert(result_bytes, b2)
                    i = i + 2
                else
                    -- Invalid second byte, skip b1
                    i = i + 1
                end
            else
                -- Incomplete sequence, skip b1
                i = i + 1
            end
        elseif b1 >= 0xE0 and b1 <= 0xEF then -- 3-byte sequence (1110xxxx 10xxxxxx 10xxxxxx)
            -- Expected: E0-EF followed by two 80-BF
            if i + 2 <= n then
                local b2 = string.byte(input_str, i + 1)
                local b3 = string.byte(input_str, i + 2)
                if b2 >= 0x80 and b2 <= 0xBF and b3 >= 0x80 and b3 <= 0xBF then
                    -- Check for overlong forms and surrogates
                    if (b1 == 0xE0 and b2 < 0xA0) or         -- Overlong: U+0000 to U+07FF encoded in 3 bytes
                       (b1 == 0xED and b2 > 0x9F) then       -- Surrogates: U+D800 to U+DFFF
                        -- Invalid sequence, skip b1
                        i = i + 1
                    else
                        table.insert(result_bytes, b1)
                        table.insert(result_bytes, b2)
                        table.insert(result_bytes, b3)
                        i = i + 3
                    end
                else
                    -- Invalid second or third byte, skip b1
                    i = i + 1
                end
            else
                -- Incomplete sequence, skip b1
                i = i + 1
            end
        elseif b1 >= 0xF0 and b1 <= 0xF4 then -- 4-byte sequence (11110xxx 10xxxxxx 10xxxxxx 10xxxxxx)
            -- Expected: F0-F4 followed by three 80-BF
            if i + 3 <= n then
                local b2 = string.byte(input_str, i + 1)
                local b3 = string.byte(input_str, i + 2)
                local b4 = string.byte(input_str, i + 3)
                if b2 >= 0x80 and b2 <= 0xBF and
                   b3 >= 0x80 and b3 <= 0xBF and
                   b4 >= 0x80 and b4 <= 0xBF then
                    -- Check for overlong forms and codepoints > U+10FFFF
                    if (b1 == 0xF0 and b2 < 0x90) or         -- Overlong: U+0000 to U+FFFF encoded in 4 bytes
                       (b1 == 0xF4 and b2 > 0x8F) then       -- Codepoint > U+10FFFF
                        -- Invalid sequence, skip b1
                        i = i + 1
                    else
                        table.insert(result_bytes, b1)
                        table.insert(result_bytes, b2)
                        table.insert(result_bytes, b3)
                        table.insert(result_bytes, b4)
                        i = i + 4
                    end
                else
                    -- Invalid second, third or fourth byte, skip b1
                    i = i + 1
                end
            else
                -- Incomplete sequence, skip b1
                i = i + 1
            end
        else
            -- Invalid starting byte (0x80-0xC1, 0xF5-0xFF)
            -- or a continuation byte appearing without a start byte.
            -- Skip this single invalid byte.
            i = i + 1
        end
    end

    return string.char(unpack(result_bytes))
end

-- removes any utf8 diactrics
function api.ascify(text)
	local asc ={
		["é"] = "e",
		["É"] = "E",
		["è"] = "e",
		["È"] = "E",
		["ê"] = "e",
		["Ê"] = "E",
		["ë"] = "e",
		["Ë"] = "E",
		["à"] = "a",
		["À"] = "A",
		["â"] = "a",
		["Â"] = "A",
		["ä"] = "a",
		["Ä"] = "A",
		["î"] = "i",
		["Î"] = "I",
		["ï"] = "i",
		["Ï"] = "I",
		["ô"] = "o",
		["Ô"] = "O",
		["ö"] = "o",
		["Ö"] = "O",
		["ù"] = "u",
		["Ù"] = "U",
		["û"] = "u",
		["Û"] = "U",
		["ü"] = "u",
		["Ü"] = "U",
		["ç"] = "c",
		["Ç"] = "C",
		["ÿ"] = "y",
		["ą"] = "a",
		["ę"] = "e",
		["ć"] = "c",
		["ń"] = "n",
		["ł"] = "l",
		["ó"] = "o",
		["ś"] = "s",
		["ż"] = "z",
		["ź"] = "z",
		["Ą"] = "A",
		["Ę"] = "E",
		["Ć"] = "C",
		["Ń"] = "N",
		["Ł"] = "L",
		["Ó"] = "O",
		["Ś"] = "S",
		["Ż"] = "Z",
		["Ź"] = "Z",
	}
	-- for key, value in pairs(asc) do text = text:gsub(key, value) end
	-- for key, value in pairs(asc) do text = api.ustring.gsub(text, key, value) end
	for key, value in pairs(asc) do text = api.utf8string.gsub(text, key, value) end
	-- text = text:gsub(api.utf8.charpattern, asc)
	-- text = api.ustring.gsub(text, api.utf8.charpattern, asc)
	-- text = api.utf8string.gsub(text, api.utf8.charpattern, asc)
	return text
end

-- converts utf diactics to normal ascii range glyphs, depends on selected font!
function api.convertDiactrics(text,fontnumber)
	local f = fontnumber
	if not f then
		local _
		_,_,f = api._glyphSize()
	end

	-- comment this to remove diactrics substitution
	for key, value in pairs(api.glyph_diactrics["_font"..f] or api.glyph_diactrics) do text = text:gsub(key, value) end
	-- for key, value in pairs(api.glyph_diactrics["_font"..f] or api.glyph_diactrics) do text = text:gsub(api.utf8.charpattern, {[key]=value}) end
	-- text = text:gsub(api.utf8.charpattern, api.glyph_diactrics["_font"..f] or api.glyph_diactrics)
	return text
end

--- Prints a string to the screen using Pico-8-like rendering, with support for glyph remapping,
-- cursor control, and inline P8SCII-style drawing commands.
--
-- This function emulates the behavior of the Pico-8 `print` function with additional
-- support for embedded control sequences using `\a` followed by a command.
-- 
-- @param str string: The text to print. May include embedded escape sequences for formatting and drawing.
-- @param x number|nil: Optional X coordinate. If omitted, uses the current cursor position.
-- @param y number|nil: Optional Y coordinate. If omitted, uses the current cursor and auto-advances by line height.
-- @param col number|nil: Optional color index. If omitted, uses the current drawing color.
-- 
-- @return number newX: X position after printing (rightmost extent).
-- @return number newY: Y position after printing (bottommost extent).

-- Special sequences:
-- - `\b`  : Backspace. Moves the cursor back by one glyph width.
-- - `\n`  : Newline. Moves cursor to the beginning of the next line.
-- - `\r`  : Carriage return. Moves cursor to the beginning of the current line.
-- - `\a`  : Introduces a **P8SCII-style command** (see below). Must be followed by a command character.
--
-- P8SCII-like commands (used after `\a` and terminated by `;`):
-- All commands must be terminated by a semicolon `;` to separate parameters unambiguously.
--
-- - `s;`     : Push current cursor position to stack.
-- - `r;`     : restore last postion from stack (if stack is not empty)
-- - `p;`     : Pop cursor position from stack and jump to it (if stack is not empty).
-- - `x[+/-]N;`: Adjust cursor X position by N pixels. Signs `+` or `-` optional (default: +).
-- - `y[+/-]N;`: Adjust cursor Y position by N pixels.
-- - `xw;` or `W;`: Add glyph width to X.  `x-w;` subtracts it.
-- - `yh;` or `H;`: Add glyph height to Y. `y-h;` subtracts it.
-- - `hN;`    : set absolute x by adding N*glyphWidth to original X coordinate
-- - `cN;`    : Change drawing color to value `N` (1–2 digits).
-- - `co;`    : Change color back to the original color at start of print().
-- - `i;`     : Plot a single pixel at the current cursor location.
--
-- Example:
-- ```lua
-- api.print("HP:\ac8\ai\ai\ai\aW\aW\ac6\ai\aW\ai", 10, 10)
-- ```
-- This draws the string "HP:" followed by 3 red pixels, skips 2 glyph widths, switches to color 6, and draws 2 more pixels.
function api.print(...)
	--TODO: support printing special pico8 chars

	local argc = select("#", ...)
	if argc == 0 then
		return
	end

	local fw,fh,f = api._glyphSize()
	local x = nil
	local y = nil
	local col = nil
	local str = select(1, ...)

	if argc == 2 then
		col = select(2, ...) or 0
	elseif argc > 2 then
		x = select(2, ...) or 0
		y = select(3, ...) or 0
		if argc >= 4 then
			col = select(4, ...) or 0
		end
	end

	if col ~= nil then
		color(col)
	end
	local orig_col = col or pico8.color

	local canscroll = y == nil
	if y == nil then
		y = pico8.cursor[2]
		pico8.cursor[2] = pico8.cursor[2] + fh
	end
	if x == nil then
		x = pico8.cursor[1]
	end
	if canscroll and y > pico8.resolution[2]-7 then -- 121
		local c = col or pico8.color
		scroll(6)
		y = pico8.resolution[2]-8 -- 120
		api.rectfill(0, y, pico8.resolution[2]-1, y + fh, 0) -- 127
		api.color(c)
		api.cursor(0, y + fh)
	end
	local to_print = tostring(api.tostr(str))

	-- diactrics replacement
	to_print = api.convertDiactrics(to_print, f)

	-- sanitize remaining utf8 multibyte characters
	-- to_print = to_print:gsub("[\128-\191][\128-\191]*[\194-\244][\128-\191]*", " "):gsub("[%z\1-\127]", "%0")

	-- to_print=to_print:gsub('.', function (c)
	-- 	local gl = pico8_glyphs[string.byte(c)]
	-- 	if not gl then return c end
	-- 	return glyph_edgecases[gl] or gl end)

	local curFont = love.graphics.getFont()

	love.graphics.setShader(pico8.text_shader)
	-- local sx,sy = flr(x)-1, flr(y)-1
	local sx,sy = flr(x), flr(y)
	local xx,yy = sx, sy
	local lx = xx
	local cursorStack
    local min_x_seen, max_x_seen = math.huge, -math.huge
    local min_y_seen, max_y_seen = math.huge, -math.huge
    local content_drawn = false

	local i = 1
	while i <= #to_print do
		local c = to_print:sub(i, i)
		if string.byte(c)>127 then 
			c = to_print:sub(i,i+1) 
			if c:len()==1 then c="" end
		end

		if c == '\a' then
			local cmd_end = to_print:find(";", i+1, true)
			local back = false
			if not cmd_end then cmd_end = to_print:find("\a", i+1, true) back = true end -- try find next \a
			if not cmd_end then break end -- malformed command, exit
			local cmd = to_print:sub(i+1, cmd_end-1):lower()
			i = cmd_end + (back and 0 or 1)

			if cmd == 's' then
				if not cursorStack then cursorStack = {} end
				table.insert(cursorStack, {xx, yy})
			elseif cmd == 'p' then
				if not cursorStack then cursorStack = {} end
				local pos = table.remove(cursorStack)
				if pos then xx, yy = pos[1], pos[2] end
			elseif cmd == 'r' then
				if not cursorStack then cursorStack = {} end
				local pos = cursorStack[#cursorStack]
				if pos then xx, yy = pos[1], pos[2] end
			elseif cmd:match("^x[+-]?%d+$") then
				local n = tonumber(cmd:sub(2))
				xx = xx + n
			elseif cmd:match("^y[+-]?%d+$") then
				local n = tonumber(cmd:sub(2))
				yy = yy + n
			elseif cmd:match("^h[+-]?%d+$") then
				local n = tonumber(cmd:sub(2))
				xx = sx + n * fw
			elseif cmd == 'x-w' then
				xx = xx - fw
			elseif cmd == 'xw' then
				xx = xx + fw
			elseif cmd == 'y-h' then
				yy = yy - fh
			elseif cmd == 'yh' then
				yy = yy + fh
			elseif cmd:match("^c%d+$") then
				color(tonumber(cmd:sub(2)))
			elseif cmd == 'co' then
				color(orig_col)
			elseif cmd == 'i' then
				love.graphics.points(xx, yy)
			end
        elseif c == '\t' then -- Tab character
            local TAB_WIDTH_IN_CHARS = 4
            local tab_width_pixels = TAB_WIDTH_IN_CHARS * fw
            if tab_width_pixels > 0 then
                -- Calculate the position of the next tab stop and move xx to it
                xx = (math.floor(xx / tab_width_pixels) + 1) * tab_width_pixels
            end
            i = i + 1
		elseif c=='\b' then
			-- xx = xx - fw
			xx = lx
			i = i + 1
		elseif c=='\n' then
			xx,yy = sx, yy+fh
			i = i + 1
		elseif c=='\r' then
			xx = sx
			i = i + 1
		else
			if c and c:len()>0 and curFont:hasGlyphs(string.byte(c)) then
				local cw = fw
				-- log(i,"["..c.."]",c:len(),to_print)
				-- log(string.byte(c),c:len()>1 and string.byte(c:sub(2,2)) or "")
				-- log(api.utf8.codepoint(c))
				c = api.utf8validate(c)
				if api.FONTS[api.FONTNUM].varWidth then cw = api.FONTS[api.FONTNUM].font:getWidth(c) + (api.FONTS[api.FONTNUM].hkerning or 0) end

				min_x_seen = math.min(min_x_seen, xx)
				max_x_seen = math.max(max_x_seen, xx + cw)
				min_y_seen = math.min(min_y_seen, yy)
				max_y_seen = math.max(max_y_seen, yy + fh)

				love.graphics.print(c,xx,yy)
				content_drawn = true

				lx = xx
				xx = xx + cw
			end
			i = i + 1
    		if (string.byte(c) or -1)>127 then i=i+1 end
		end
	end

	love.graphics.setShader(pico8.draw_shader) -- rostok: i think we should fall back to draw_shader

	if not content_drawn then return x,y end
	return max_x_seen,max_y_seen
end

--- Calculates the pixel width and height a string would occupy if printed.
-- This function simulates the printing process, including escape codes and P8SCII commands,
-- to determine the bounding box of the rendered text.
--
-- @param str_input any: The value to measure. It will be converted to a string using logic similar to api.print.
-- @return number w: The total width of the rendered string in pixels.
-- @return number h: The total height of the rendered string in pixels.
function api.strdim(str_input)
    -- 1. String Preprocessing (mirrors api.print)
    local text_to_measure = api.tostr(str_input)
    if type(text_to_measure) == "boolean" then
         text_to_measure = text_to_measure and "true" or "false"
    else
         text_to_measure = tostring(text_to_measure)
    end

    if text_to_measure == "" then return 0, 0 end

    local fw, fh, f_idx = api._glyphSize()
    if fw == 0 or fh == 0 then return 0, 0 end -- If glyphs have no dimensions, string (if not empty) can't be measured meaningfully.
    
    local to_print = text_to_measure

	-- diactrics replacement
	to_print = api.convertDiactrics(to_print, f_idx)

	-- sanitize remaining utf8 multibyte characters
	-- to_print = to_print:gsub("[\128-\191][\128-\191]*[\194-\244][\128-\191]*", " "):gsub("[%z\1-\127]", "%0")

	-- to_print=to_print:gsub('.', function (c)
	-- 	local gl = pico8_glyphs[string.byte(c)]
	-- 	if not gl then return c end
	-- 	return glyph_edgecases[gl] or gl end)
	
	-- to_print = to_print:gsub(api.utf8.charpattern, " ")

    -- 2. Simulation of Printing
    local xx, yy = 0, 0
    local lx = xx
    local start_of_line_x = 0 -- Relative start X for \n and \r
    local cursorStack

    local min_x_seen, max_x_seen = math.huge, -math.huge
    local min_y_seen, max_y_seen = math.huge, -math.huge
    local content_drawn = false

	local curFont = love.graphics.getFont()

    local i = 1
    while i <= #to_print do
        local c = to_print:sub(i, i)
		if string.byte(c)>127 then 
			c = to_print:sub(i,i+1) 
			if c:len()==1 then c="" end
		end
		-- local char = api.utf8sub(to_print, i, i)
        if c == '\a' then -- P8SCII command
            local cmd_end = to_print:find(";", i + 1, true)
			local back = false
			if not cmd_end then cmd_end = to_print:find("\a", i+1, true) back = true end -- try find next \a
			if not cmd_end then break end -- malformed
            local cmd = to_print:sub(i + 1, cmd_end - 1):lower()
            i = cmd_end + (back and 0 or 1)

            if cmd == 's' then
				if not cursorStack then cursorStack = {} end
                table.insert(cursorStack, {xx, yy, start_of_line_x})
            elseif cmd == 'p' then
				if not cursorStack then cursorStack = {} end
                local pos = table.remove(cursorStack)
                if pos then
                    xx, yy, start_of_line_x = pos[1], pos[2], pos[3]
                end
			elseif cmd == 'p' then
				if not cursorStack then cursorStack = {} end
				local pos = cursorStack[#cursorStack]
				if pos then xx, yy = pos[1], pos[2] end
            elseif cmd:match("^x[+-]?%d+$") then
                xx = xx + (tonumber(cmd:sub(2)) or 0)
            elseif cmd:match("^y[+-]?%d+$") then
                yy = yy + (tonumber(cmd:sub(2)) or 0)
			elseif cmd:match("^h[+-]?%d+$") then
				local n = tonumber(cmd:sub(2))
				xx = n * fw
            elseif cmd == 'x-w' then
                xx = xx - fw
            elseif cmd == 'xw' then
                xx = xx + fw
            elseif cmd == 'y-h' then
                yy = yy - fh
            elseif cmd == 'yh' then
                yy = yy + fh
            elseif cmd == 'i' then -- Plot pixel
                min_x_seen = math.min(min_x_seen, xx)
                max_x_seen = math.max(max_x_seen, xx)
                min_y_seen = math.min(min_y_seen, yy)
                max_y_seen = math.max(max_y_seen, yy)
                content_drawn = true
            end
            -- 'cN' (color) and 'co' (original color) don't affect dimensions
        elseif c == '\t' then -- Tab character
            local TAB_WIDTH_IN_CHARS = 4
            local tab_width_pixels = TAB_WIDTH_IN_CHARS * fw
            if tab_width_pixels > 0 then
                -- Calculate the position of the next tab stop and move xx to it
                xx = (math.floor(xx / tab_width_pixels) + 1) * tab_width_pixels
            end
            i = i + 1
		elseif c == '\b' then -- Backspace
            -- xx = xx - fw
            xx = lx
            i = i + 1
        elseif c == '\n' then -- Newline
            yy = yy + fh
            xx = start_of_line_x
            i = i + 1
        elseif c == '\r' then -- Carriage return
            xx = start_of_line_x
            i = i + 1
        else -- Normal character (or substituted glyph string)
            -- A character cell occupies [xx, xx+fw) and [yy, yy+fh)
            -- This assumes that even if a glyph is "unknown", its cell contributes to extents.
			-- log(i,"["..c.."]",c:len(),to_print)
			-- log(string.byte(c),c:len()>1 and string.byte(c:sub(2,2)) or "")
			if c and c:len()>0 and curFont:hasGlyphs(string.byte(c)) then
				local cw = fw
				c = api.utf8validate(c)
				if api.FONTS[api.FONTNUM].varWidth then cw = api.FONTS[api.FONTNUM].font:getWidth(c) + (api.FONTS[api.FONTNUM].hkerning or 0) end

				min_x_seen = math.min(min_x_seen, xx)
				max_x_seen = math.max(max_x_seen, xx + cw)
				min_y_seen = math.min(min_y_seen, yy)
				max_y_seen = math.max(max_y_seen, yy + fh)
				content_drawn = true

				lx = xx
				xx = xx + cw
			end

    		if (string.byte(c) or -1)>127 then i=i+1 end
            i = i + 1
        end
    end

    if not content_drawn then
        return 0, 0 -- String was empty or contained only non-drawing commands
    end
    local width = max_x_seen - min_x_seen
    local height = max_y_seen - min_y_seen
    
    return width, height
end

--- Calculates the number of character cells (glyphs) a string would occupy horizontally and vertically.
-- This function uses api.strdim to get pixel dimensions and then divides by the current glyph size.
--
-- @param str_input any: The value to measure.
-- @return number n: Number of characters horizontally (width_in_pixels / glyph_width, ceiled).
-- @return number m: Number of characters vertically (height_in_pixels / glyph_height, ceiled).
function api.strsize(str_input)
    local fw, fh = api._glyphSize()
    local w_pixels, h_pixels = api.strdim(str_input)

    local n_chars, m_chars

    if fw == 0 then
        -- If glyph width is 0, conceptually infinite characters fit if width > 0, or 0 if width is 0.
        -- Since strdim returns w_pixels=0 if fw=0 and string isn't just commands, result is 0.
        n_chars = 0
    else
        n_chars = math.ceil(w_pixels / fw)
    end

    if fh == 0 then
        -- Similar logic for height.
        m_chars = 0
    else
        m_chars = math.ceil(h_pixels / fh)
    end
    
    return n_chars, m_chars
end

--- Calculates the number of characters in a string, considering UTF-8 characters as single units.
-- This function processes the string similarly to the initial stages of `api.print`
-- (including `api.tostr` conversion, diacritic replacement, and basic sanitization)
-- before counting. Control characters like \n, \r, and characters forming P8SCII
-- escape sequences (e.g., '\a', 'C', '1', ';') are each counted as one character.
--
-- @param str_input any: The value whose character length is to be determined.
-- @return number: The number of characters in the processed string.
function api.strlen(str_input)
    local text_to_count = api.tostr(str_input)
    if type(text_to_count) == "boolean" then
         text_to_count = text_to_count and "true" or "false"
    else
         text_to_count = tostring(text_to_count) -- Handles nil -> "nil", numbers, etc.
    end

    if text_to_count == "" then return 0 end

    local _, _, f_idx = api._glyphSize()

	text_to_count = text_to_count:gsub(api.utf8.charpattern, " ")
	local count = select(2, string.gsub(text_to_count, ".", ""))
    return count
end

api.printh = print
api.io = io
api.loadstring = loadstring
api.dofile = dofile
api.load = load
api.pcall = pcall

function api.cursor(x, y, col)
	if col then
		color(col)
	end
	x = flr(tonumber(x) or 0) % 256
	y = flr(tonumber(y) or 0) % 256
	pico8.cursor = { x, y }
end

function api.tonum(val, format)
	local kind = type(val)
	if kind ~= "number" and kind ~= "string" and kind ~= "boolean" then
		return
	elseif kind == "number" then
		return val
	end

	if type(format) == "string" then
		format = tonumber(format)
	elseif type(format) ~= "number" then
		format = nil
	end

	local base = 10
	local shift = false
	local zeroreturn = false
	if type(format) == "number" then
		base = bit.band(format, 1) ~= 0 and 16 or 10
		shift = bit.band(format, 2) ~= 0
		zeroreturn = bit.band(format, 4) ~= 0
	end

	if kind == "boolean" then
		val = val and 1 or 0
		return shift and 0 or val
	end

	local result = tonumber(val, base)
	if result ~= nil then
		return shift and result / 0x10000 or result
	elseif zeroreturn then
		return 0
	end
end

function api.chr(num)
	--GTODO: stuff
	local n = tonumber(num)
	if n == nil then
		return
	end
	n = n % 256
	return tostring(string.char(n))
end

function api.ord(...)
	local str = select(1, ...)
	if str == nil then
		return nil
	end

	local argc = select("#", ...)
	local index = select(2, ...) or 0
	local count = select(3, ...) or 0

	if argc == 1 then
		return string.byte(str)
	elseif argc == 2 then
		return string.byte(str, index)
	elseif argc >= 3 then
		local values = {}
		for i = 1, count do
			if index + i > 1 then
				values[i] = string.byte(str, index + i - 1)
				api.printh(values[i], i)
			end
		end
		return unpack(values, 1, count)
	end

	return nil
end

api.tostring = tostring

function api.tostr(...)
	if select("#", ...) == 0 then
		return ""
	end

	local val = select(1, ...)
	local kind = type(val)

	if kind == "string" then
		return val
	elseif kind == "number" then
		local format = select(2, ...)
		if format == true then
			format = 1
		end

		if format and bit.band(format, 1) ~= 0 then
			val = val * 0x10000
			local part1 = bit.rshift(bit.band(val, 0xFFFF0000), 16)
			local part2 = bit.band(val, 0xFFFF)
			if bit.band(format, 2) ~= 0 then
				return string.format("0x%04x%04x", part1, part2)
			else
				return string.format("0x%04x.%04x", part1, part2)
			end
		else
			if format and bit.band(format, 2) ~= 0 then
				val = val * 0x10000
			end
			return tostring(val)
		end
	elseif kind == "boolean" then
		return tostring(val)
	else
		return "[" .. kind .. "]"
	end
end


--sync spritesheet_data and spritesheet
local function refresh_spritesheet()
	if pico8.spritesheet_changed then
		pico8.spritesheet_changed=false
		pico8.spritesheet:replacePixels(pico8.spritesheet_data)
	end
end

function api.spr(n, x, y, w, h, flip_x, flip_y)
	love.graphics.setShader(pico8.sprite_shader)
	n = flr(tonumber(n) or 0)
	x = tonumber(x) or 0
	y = tonumber(y) or 0
	w = tonumber(w) or 1
	h = tonumber(h) or 1
	local q
	if w == 1 and h == 1 then
		q = pico8.quads[n]
		if not q then
			-- log("warning: sprite " .. n .. " is missing")
			return
		end
	else
		local id = string.format("%d-%d-%d", n, w, h)
		if pico8.quads[id] then
			q = pico8.quads[id]
		else
			q = love.graphics.newQuad(
				flr(n % 16) * 8,
				flr(n / 16) * 8,
				8 * w,
				8 * h,
				128,
				128
			)
			pico8.quads[id] = q
		end
	end
	if not q then
		log("missing quad", n)
	end
	refresh_spritesheet()
	love.graphics.draw(
		pico8.spritesheet,
		q,
		flr(x) + (w * 8 * (flip_x and 1 or 0)),
		flr(y) + (h * 8 * (flip_y and 1 or 0)),
		0,
		flip_x and -1 or 1,
		flip_y and -1 or 1
	)
	love.graphics.setShader(pico8.draw_shader)
end

function api.sspr(sx, sy, sw, sh, dx, dy, dw, dh, flip_x, flip_y)
	-- Stretch rectangle from sprite sheet (sx, sy, sw, sh) // given in pixels
	-- and draw in rectangle (dx, dy, dw, dh)
	-- Color 0 drawn as transparent by default (see palt())
	-- dw, dh defaults to sw, sh
	-- flip_x = true to flip horizontally
	-- flip_y = true to flip vertically
	dw = dw or sw
	dh = dh or sh
	-- FIXME: cache this quad
	local q =
		love.graphics.newQuad(sx, sy, sw, sh, pico8.spritesheet:getDimensions())
	love.graphics.setShader(pico8.sprite_shader)
	refresh_spritesheet()
	love.graphics.draw(
		pico8.spritesheet,
		q,
		flr(dx) + (flip_x and dw or 0),
		flr(dy) + (flip_y and dh or 0),
		0,
		dw / sw * (flip_x and -1 or 1),
		dh / sh * (flip_y and -1 or 1)
	)
	love.graphics.setShader(pico8.draw_shader)
end

function api.rect0(x0, y0, x1, y1, col)
	-- GTODO: x0=x1
	if col then color(col) end
	
	if x0==x1 and y0==y1 then return love.graphics.points(x0,y0) end
	if x0==x1 or y0==y1 then return love.graphics.line(x0,y0,x1,y1) end
	-- x0,y0,x1,y1 = flr(x0),flr(y0),flr(x1),flr(y1)
	-- love.graphics.line(x0,y0,x1,y0)
	-- love.graphics.line(x1,y0,x1,y1)
	-- love.graphics.line(x1,y1,x0,y1)
	-- love.graphics.line(x0,y1,x0,y0)

	love.graphics.rectangle(
		"line",
		flr(x0),
		flr(y0),
		flr(x1 - x0),
		flr(y1 - y0)
	)

	-- x0 = flr(x0)
	-- x1 = flr(x1)
	-- y0 = flr(y0)
	-- y1 = flr(y1)
	-- if x1<x0 then x0,x1=x1,x0 end
	-- if y1<y0 then y0,y1=y1,y0 end
	-- love.graphics.rectangle(
	-- 	"line",
	-- 	x0,
	-- 	y0,
	-- 	x1 - x0,
	-- 	y1 - y0
	-- )
end

-- no flr()
function api.rect1(x0, y0, x1, y1, col)
	if col then color(col) end
	
	if x0==x1 and y0==y1 then return love.graphics.points(x0,y0) end
	if x0==x1 or y0==y1 then return love.graphics.line(x0,y0,x1,y1) end

	love.graphics.rectangle(
		"line",
		x0,
		y0,
		x1 - x0,
		y1 - y0
	)
end

api.rect = api.rect0

function api.rectfill0(x0, y0, x1, y1, col)
	if col then color(col) end
	if x1 < x0 then
		x0, x1 = x1, x0
	end
	if y1 < y0 then
		y0, y1 = y1, y0
	end
	-- love.graphics.rectangle(
	-- 	"fill",
	-- 	flr(x0),
	-- 	flr(y0),
	-- 	flr(x1 - x0) + 1,
	-- 	flr(y1 - y0) + 1
	-- )
	love.graphics.rectangle(
		"fill",
		flr(x0)-1,
		flr(y0)-1,
		flr(x1 - x0)+1,
		flr(y1 - y0)+1
	)
end

function api.rectfill1(x0, y0, x1, y1, col)
	if col then color(col) end
	if x1 < x0 then
		x0, x1 = x1, x0
	end
	if y1 < y0 then
		y0, y1 = y1, y0
	end
	love.graphics.rectangle(
		"fill",
		(x0)-1,
		(y0)-1,
		(x1 - x0)+1,
		(y1 - y0)+1
	)
end

api.rectfill = api.rectfill0

function api.circ2(ox, oy, r, col)
	if col then
		color(col)
	end
	-- love.graphics.circle(
	-- 	"line",
	-- 	flr(ox),
	-- 	flr(oy),
	-- 	flr(r)
	-- )
	love.graphics.circle(
		"line",
		(ox-.5),
		(oy-.5),
		(r+.25)
	)
end

function api.circfill2(ox, oy, r, col)
	if col then
		color(col)
	end
	-- love.graphics.circle(
	-- 	"fill",
	-- 	flr(ox),
	-- 	flr(oy),
	-- 	flr(r)
	-- )
	love.graphics.circle(
		"fill",
		(ox-.5),
		(oy-.5),
		(r+.25)
	)
end

function api.circold(ox, oy, r, col)
	if col then
		color(col)
	end
	ox = flr(ox)-- + 1 -- rostok, making top-left pixel 1,1 not 0,0
	oy = flr(oy)-- + 1 -- rostok, making top-left pixel 1,1 not 0,0
	r = flr(r)
	local points = {}
	local x = r
	local y = 0
	local decisionOver2 = 1 - x

	while y <= x do
		table.insert(points, { ox + x, oy + y })
		table.insert(points, { ox + y, oy + x })
		table.insert(points, { ox - x, oy + y })
		table.insert(points, { ox - y, oy + x })

		table.insert(points, { ox - x, oy - y })
		table.insert(points, { ox - y, oy - x })
		table.insert(points, { ox + x, oy - y })
		table.insert(points, { ox + y, oy - x })
		y = y + 1
		if decisionOver2 < 0 then
			decisionOver2 = decisionOver2 + 2 * y + 1
		else
			x = x - 1
			decisionOver2 = decisionOver2 + 2 * (y - x) + 1
		end
	end
	if #points > 0 then
		love.graphics.points(points)
	end
end

function api.circ(ox, oy, r, col)
	if col then
		color(col)
	end
	ox = flr(ox)-- + 1 -- rostok, making top-left pixel 1,1 not 0,0
	oy = flr(oy)-- + 1 -- rostok, making top-left pixel 1,1 not 0,0
	r = flr(r)
	local points = __tempPointsTable
	table_clear(points)
	local x = r
	local y = 0
	local decisionOver2 = 1 - x

	while y <= x do
		points[#points+1] = ox + x
		points[#points+1] = oy + y
		points[#points+1] = ox + y
		points[#points+1] = oy + x
		points[#points+1] = ox - x
		points[#points+1] = oy + y
		points[#points+1] = ox - y
		points[#points+1] = oy + x
		points[#points+1] = ox - x
		points[#points+1] = oy - y
		points[#points+1] = ox - y
		points[#points+1] = oy - x
		points[#points+1] = ox + x
		points[#points+1] = oy - y
		points[#points+1] = ox + y
		points[#points+1] = oy - x
		y = y + 1
		if decisionOver2 < 0 then
			decisionOver2 = decisionOver2 + 2 * y + 1
		else
			x = x - 1
			decisionOver2 = decisionOver2 + 2 * (y - x) + 1
		end
	end
	if #points > 0 then
		love.graphics.points(points)
	end
end

function api.circfill(cx, cy, r, col)
	if col then
		color(col)
	end
	cx = flr(cx)-1
	cy = flr(cy)-1
	r = flr(r)
	local x = r
	local y = 0
	local err = 1 - r

	local lines = {}

	while y <= x do
		_plot4points(lines, cx, cy, x, y)
		if err < 0 then
			err = err + 2 * y + 3
		else
			if x ~= y then
				_plot4points(lines, cx, cy, y, x)
			end
			x = x - 1
			err = err + 2 * (y - x) + 3
		end
		y = y + 1
	end
	if #lines > 0 then
		for i = 1, #lines do
			love.graphics.line(lines[i])
		end
	end
end

-- original bresenham but with much faster polygon fill
function api.circfillpoly(cx, cy, r, col)
	if col then
		color(col)
	end
	cx = flr(cx)-1
	cy = flr(cy)-1
	r = flr(r)
	local x = r
	local y = 0
	local err = 1 - r

	local verts = {} -- x1,y1,x2,y2 with total size of r*4

	while y <= x do
		--_plot4points(lines, cx, cy, x, y)
		verts[r*0+y*2+1]=cx+x -- 0
		verts[r*0+y*2+2]=cy+y
		verts[r*4-y*2+1]=cx-x -- 3
		verts[r*4-y*2+2]=cy+y
		verts[r*4+y*2+1]=cx-x -- 4
		verts[r*4+y*2+2]=cy-y
		verts[r*6+y*2+1]=cx+x -- 7
		verts[r*6+y*2+2]=cy-y 
		if err < 0 then
			err = err + 2 * y + 3
		else
			if x ~= y then
				verts[r*0+x*2+1]=cx+y -- 1
				verts[r*0+x*2+2]=cy+x
				verts[r*4-x*2+1]=cx-y -- 2
				verts[r*4-x*2+2]=cy+x
				verts[r*4+x*2+1]=cx-y -- 5
				verts[r*4+x*2+2]=cy-x
				verts[r*8-x*2+1]=cx+y -- 6
				verts[r*8-x*2+2]=cy-x
			end
			x = x - 1
			err = err + 2 * (y - x) + 3
		end
		y = y + 1
	end
	if #verts > 0 then
		love.graphics.polygon("fill",verts)
	end
end

function api.ellipse(x, y, rx, ry, col)
	if col then color(col) end
	love.graphics.ellipse("line",x,y,rx,ry)
end

function api.oval(x0, y0, x1, y1, col)
	if col then color(col) end
	local x,y=(x1+x0)/2,(y1+y0)/2
	local rx,ry=math.abs(x1-x),math.abs(y1-y)
	love.graphics.ellipse("line",x,y,rx,ry)
end

function api.ovalfill(x0, y0, x1, y1, col)
	if col then color(col) end
	local x,y=(x1+x0)/2,(y1+y0)/2
	local rx,ry=math.abs(x1-x),math.abs(y1-y)
	love.graphics.ellipse("fill",x,y,rx,ry)
end

function api.rotoval(a, x0, y0, x1, y1, col)
    love.graphics.push()
    love.graphics.translate((x1 + x0) / 2, (y1 + y0) / 2)
    love.graphics.rotate(- (a or 0) * 2 * math.pi)
    love.graphics.translate(-(x1 + x0) / 2, -(y1 + y0) / 2)
    api.oval(x0, y0, x1, y1, col)
    love.graphics.pop()
end

function api.rotovalfill(a, x0, y0, x1, y1, col)
    love.graphics.push()
    love.graphics.translate((x1 + x0) / 2, (y1 + y0) / 2)
    love.graphics.rotate(- (a or 0) * 2 * math.pi)
    love.graphics.translate(-(x1 + x0) / 2, -(y1 + y0) / 2)
    api.ovalfill(x0, y0, x1, y1, col)
    love.graphics.pop()
end

-- the original line picolove implementation but with variable parameter coords (uses table and points)
function api.line0(x0, y0, x1, y1, col)
	if col then
		color(col)
	end

	if not x0 then -- Invalidates the current endpoint.
    	pico8.line_endpoint_x = nil
	    pico8.line_endpoint_y = nil
	    return
	end
	if not y0 then -- Invalidates the current endpoint. Remembers color as the current pen color.
    	pico8.line_endpoint_x = nil
	    pico8.line_endpoint_y = nil
	    if x0 ~= pico8.color then color(x0) end -- rostok: skip color if same
	    return
	end
	if not x1 then -- Draws a line from the current endpoint to (x1, y1) in the current pen color. If there is no current endpoint, nothing is drawn. Remembers (x1, y1) as the current endpoint.
	    if pico8.line_endpoint_x then
		    x0,y0,x1,y1=pico8.line_endpoint_x,pico8.line_endpoint_y,x0,y0
		else
			pico8.line_endpoint_x = x0
			pico8.line_endpoint_y = y0
			return
		end
	elseif not y1 then -- Draws a line from the current endpoint to (x1, y1) in the given color. If there is no current endpoint, nothing is drawn. Remembers (x1, y1) as the current endpoint and color as the current pen color.
	    if pico8.line_endpoint_x then
		    x0,y0,x1,y1,col=pico8.line_endpoint_x,pico8.line_endpoint_y,x0,y0,x1
		else
			pico8.line_endpoint_x = x0
			pico8.line_endpoint_y = y0
			if x1 ~= pico8.color then color(x1) end -- rostok: skip color if same
			return
		end
	end

	if col and col ~= pico8.color then color(col) end -- rostok: skip color if same

	pico8.line_endpoint_x = x1
	pico8.line_endpoint_y = y1

	x0 = flr(x0) -- + 1
	y0 = flr(y0) -- + 1
	x1 = flr(x1) -- + 1
	y1 = flr(y1) -- + 1

	local dx = x1 - x0
	local dy = y1 - y0
	local stepx, stepy

	local points = __tempPointsTable
	table_clear(points)
	points[#points+1]=x0
	points[#points+1]=y0

	if dx == 0 then
		-- simple case draw a vertical line
		table_clear(points)
  	    if y0 > y1 then
			y0, y1 = y1, y0
		end
		for y = y0, y1 do
			points[#points+1]=x0
			points[#points+1]=y
		end
	elseif dy == 0 then
		-- simple case draw a horizontal line
		table_clear(points)
		if x0 > x1 then
			x0, x1 = x1, x0
		end
		for x = x0, x1 do
			points[#points+1]=x
			points[#points+1]=y0
		end
	else
		if dy < 0 then
			dy = -dy
			stepy = -1
		else
			stepy = 1
		end

		if dx < 0 then
			dx = -dx
			stepx = -1
		else
			stepx = 1
		end

		if dx > dy then
			local fraction = dy - bit.rshift(dx, 1)
			while x0 ~= x1 do
				if fraction >= 0 then
					y0 = y0 + stepy
					fraction = fraction - dx
				end
				x0 = x0 + stepx
				fraction = fraction + dy
				points[#points+1]=flr(x0)
				points[#points+1]=flr(y0)
				end
		else
			local fraction = dx - bit.rshift(dy, 1)
			while y0 ~= y1 do
				if fraction >= 0 then
					x0 = x0 + stepx
					fraction = fraction - dy
				end
				y0 = y0 + stepy
				fraction = fraction + dx
				points[#points+1]=flr(x0)
				points[#points+1]=flr(y0)
			end
		end
	end
	love.graphics.points(points)
end

-- hybrid approach with hor/vertical lines being drawn by love.graphics.line
function api.line1(x0, y0, x1, y1, col)
	if not x0 then -- Invalidates the current endpoint.
    	pico8.line_endpoint_x = nil
	    pico8.line_endpoint_y = nil
	    return
	end
	if not y0 then -- Invalidates the current endpoint. Remembers color as the current pen color.
    	pico8.line_endpoint_x = nil
	    pico8.line_endpoint_y = nil
	    if x0 ~= pico8.color then color(x0) end -- rostok: skip color if same
	    return
	end
	if not x1 then -- Draws a line from the current endpoint to (x1, y1) in the current pen color. If there is no current endpoint, nothing is drawn. Remembers (x1, y1) as the current endpoint.
	    if pico8.line_endpoint_x then
		    x0,y0,x1,y1=pico8.line_endpoint_x,pico8.line_endpoint_y,x0,y0
		else
			pico8.line_endpoint_x = x0
			pico8.line_endpoint_y = y0
			return
		end
	elseif not y1 then -- Draws a line from the current endpoint to (x1, y1) in the given color. If there is no current endpoint, nothing is drawn. Remembers (x1, y1) as the current endpoint and color as the current pen color.
	    if pico8.line_endpoint_x then
		    x0,y0,x1,y1,col=pico8.line_endpoint_x,pico8.line_endpoint_y,x0,y0,x1
		else
			pico8.line_endpoint_x = x0
			pico8.line_endpoint_y = y0
			if x1 ~= pico8.color then color(x1) end -- rostok: skip color if same
			return
		end
	end

	if col and col ~= pico8.color then color(col) end -- rostok: skip color if same

	pico8.line_endpoint_x = x1
	pico8.line_endpoint_y = y1
	
	-- if x0==x1 or y0==y1 then return love.graphics.line(flr(x0),flr(y0),ceil(x1),ceil(y1)) end
	-- if x0==x1 then return love.graphics.line(flr(x0),flr(y0),flr(x1)+1,flr(y1)) end
	-- if y0==y1 then return love.graphics.line(flr(x0),flr(y0),flr(x1),flr(y1)+1) end

	x0 = flr(x0 or 0) -- + 1 -- x0 = flr(tonumber(x0) or 0) + 1
	y0 = flr(y0 or 0) -- + 1 -- y0 = flr(tonumber(y0) or 0) + 1
	x1 = flr(x1 or 0) -- + 1 -- x1 = flr(tonumber(x1) or 0) + 1
	y1 = flr(y1 or 0) -- + 1 -- y1 = flr(tonumber(y1) or 0) + 1
	

	local dx = x1 - x0
	local dy = y1 - y0
	local stepx, stepy

	local points = __tempPointsTable
	table_clear(points)
	points[#points+1]=x0
	points[#points+1]=y0

	if dx == 0 then
		-- simple case draw a vertical line
		if y0 > y1 then
			y0, y1 = y1, y0
		end
		return love.graphics.line(x0,y0-1,x0,y1)
		-- points = {}
		-- for y = y0, y1 do
		-- 	table.insert(points, { x0, y })
		-- end
	elseif dy == 0 then
		-- simple case draw a horizontal line
		if x0 > x1 then
			x0, x1 = x1, x0
		end
		return love.graphics.line(x0-1,y0,x1,y0)
		-- points = {}
		-- for x = x0, x1 do
		-- 	table.insert(points, { x, y0 })
		-- end
	else
		if dy < 0 then
			dy = -dy
			stepy = -1
		else
			stepy = 1
		end

		if dx < 0 then
			dx = -dx
			stepx = -1
		else
			stepx = 1
		end

		if dx > dy then
			local fraction = dy - bit.rshift(dx, 1)
			while x0 ~= x1 do
				if fraction >= 0 then
					y0 = y0 + stepy
					fraction = fraction - dx
				end
				x0 = x0 + stepx
				fraction = fraction + dy
				-- table.insert(points, { flr(x0), flr(y0) })
				points[#points+1] = flr(x0)
				points[#points+1] = flr(y0)
			end
		else
			local fraction = dx - bit.rshift(dy, 1)
			while y0 ~= y1 do
				if fraction >= 0 then
					x0 = x0 + stepx
					fraction = fraction - dy
				end
				y0 = y0 + stepy
				fraction = fraction + dx
				-- table.insert(points, { flr(x0), flr(y0) })
				points[#points+1] = flr(x0)
				points[#points+1] = flr(y0)
			end
		end
	end
	love.graphics.points(points)
end

-- love.graphics.line but with flr() to coordinates
function api.line2(x0, y0, x1, y1, col)
	if not x0 then -- Invalidates the current endpoint.
    	pico8.line_endpoint_x = nil
	    pico8.line_endpoint_y = nil
	    return
	end
	if not y0 then -- Invalidates the current endpoint. Remembers color as the current pen color.
    	pico8.line_endpoint_x = nil
	    pico8.line_endpoint_y = nil
	    if x0 ~= pico8.color then color(x0) end -- rostok: skip color if same
	    return
	end
	if not x1 then -- Draws a line from the current endpoint to (x1, y1) in the current pen color. If there is no current endpoint, nothing is drawn. Remembers (x1, y1) as the current endpoint.
	    if pico8.line_endpoint_x then
		    x0,y0,x1,y1=pico8.line_endpoint_x,pico8.line_endpoint_y,x0,y0
		else
			pico8.line_endpoint_x = x0
			pico8.line_endpoint_y = y0
			return
		end
	elseif not y1 then -- Draws a line from the current endpoint to (x1, y1) in the given color. If there is no current endpoint, nothing is drawn. Remembers (x1, y1) as the current endpoint and color as the current pen color.
	    if pico8.line_endpoint_x then
		    x0,y0,x1,y1,col=pico8.line_endpoint_x,pico8.line_endpoint_y,x0,y0,x1
		else
			pico8.line_endpoint_x = x0
			pico8.line_endpoint_y = y0
			if x1 ~= pico8.color then color(x1) end -- rostok: skip color if same
			return
		end
	end

	if col and col ~= pico8.color then color(col) end -- rostok: skip color if same

	pico8.line_endpoint_x = x1
	pico8.line_endpoint_y = y1
	
	-- x0 = flr(x0 or 0) + 1 -- x0 = flr(tonumber(x0) or 0) + 1
	-- y0 = flr(y0 or 0) + 1 -- y0 = flr(tonumber(y0) or 0) + 1
	-- x1 = flr(x1 or 0) + 1 -- x1 = flr(tonumber(x1) or 0) + 1
	-- y1 = flr(y1 or 0) + 1 -- y1 = flr(tonumber(y1) or 0) + 1
	if x0<=x1 then
		x0,x1=flr(x0-.5),math.ceil(x1)
	else
		x0,x1=math.ceil(x0),flr(x1-.5)
	end
	if y0<=y1 then
		y0,y1=flr(y0-.5),math.ceil(y1)
	else
		y0,y1=math.ceil(y0),flr(y1-.5)
	end
	
	return love.graphics.line(x0,y0,x1,y1)
end

-- full love.graphics.line
function api.line3(x0, y0, x1, y1, col)
	if not x0 then -- Invalidates the current endpoint.
    	pico8.line_endpoint_x = nil
	    pico8.line_endpoint_y = nil
	    return
	end
	if not y0 then -- Invalidates the current endpoint. Remembers color as the current pen color.
    	pico8.line_endpoint_x = nil
	    pico8.line_endpoint_y = nil
	    if x0 ~= pico8.color then color(x0) end -- rostok: skip color if same
	    return
	end
	if not x1 then -- Draws a line from the current endpoint to (x1, y1) in the current pen color. If there is no current endpoint, nothing is drawn. Remembers (x1, y1) as the current endpoint.
	    if pico8.line_endpoint_x then
		    x0,y0,x1,y1=pico8.line_endpoint_x,pico8.line_endpoint_y,x0,y0
		else
			pico8.line_endpoint_x = x0
			pico8.line_endpoint_y = y0
			return
		end
	elseif not y1 then -- Draws a line from the current endpoint to (x1, y1) in the given color. If there is no current endpoint, nothing is drawn. Remembers (x1, y1) as the current endpoint and color as the current pen color.
	    if pico8.line_endpoint_x then
		    x0,y0,x1,y1,col=pico8.line_endpoint_x,pico8.line_endpoint_y,x0,y0,x1
		else
			pico8.line_endpoint_x = x0
			pico8.line_endpoint_y = y0
			if x1 ~= pico8.color then color(x1) end -- rostok: skip color if same
			return
		end
	end

	if col and col ~= pico8.color then color(col) end -- rostok: skip color if same

	pico8.line_endpoint_x = x1
	pico8.line_endpoint_y = y1
	
	-- if x0<=x1 then
	-- 	x0,x1=flr(x0-.5),math.ceil(x1)
	-- else
	-- 	x0,x1=math.ceil(x0),flr(x1-.5)
	-- end
	-- if y0<=y1 then
	-- 	y0,y1=flr(y0-.5),math.ceil(y1)
	-- else
	-- 	y0,y1=math.ceil(y0),flr(y1-.5)
	-- end

	-- local D=-.5
	-- local A=1
	-- if flr(x0+D)==flr(x1+D) then
	-- 	if x0<=x1 then
	-- 		x0,x1 = x0,x1+A
	-- 	else
	-- 		x0,x1 = x0+A,x1
	-- 	end
	-- end
	-- if flr(y0+D)==flr(y1+D) then
	-- 	if y0<=y1 then
	-- 		y0,y1 = y0,y1+A
	-- 	else
	-- 		y0,y1 = y0+A,y1
	-- 	end
	-- end

	local D=0
	local A=0
	if flr(x1+D)<=flr(x0+D) then x0=x0+A else x1=x1+A end
	if flr(y1+D)<=flr(y0+D) then y0=y0+A else y1=y1+A end

	-- local D=0
	-- local A=.5
	-- if flr(x0+D)==flr(x1+D) then
	-- 	if y0<=y1 then
	-- 		y0,y1 = y0,y1+A
	-- 	else
	-- 		y0,y1 = y0+A,y1
	-- 	end
	-- end
	-- if flr(y0+D)==flr(y1+D) then
	-- 	if x0<=x1 then
	-- 		x0,x1 = x0,x1+A
	-- 	else
	-- 		x0,x1 = x0+A,x1
	-- 	end
	-- end

	local B=0.5
	return love.graphics.line(x0+B,y0+B,x1+B,y1+B)
end

-- the original line picolove implementation but with variable parameter coords and no flr()
function api.line4(x0, y0, x1, y1, col)
	if col then
		color(col)
	end

	if not x0 then -- Invalidates the current endpoint.
    	pico8.line_endpoint_x = nil
	    pico8.line_endpoint_y = nil
	    return
	end
	if not y0 then -- Invalidates the current endpoint. Remembers color as the current pen color.
    	pico8.line_endpoint_x = nil
	    pico8.line_endpoint_y = nil
	    if x0 ~= pico8.color then color(x0) end -- rostok: skip color if same
	    return
	end
	if not x1 then -- Draws a line from the current endpoint to (x1, y1) in the current pen color. If there is no current endpoint, nothing is drawn. Remembers (x1, y1) as the current endpoint.
	    if pico8.line_endpoint_x then
		    x0,y0,x1,y1=pico8.line_endpoint_x,pico8.line_endpoint_y,x0,y0
		else
			pico8.line_endpoint_x = x0
			pico8.line_endpoint_y = y0
			return
		end
	elseif not y1 then -- Draws a line from the current endpoint to (x1, y1) in the given color. If there is no current endpoint, nothing is drawn. Remembers (x1, y1) as the current endpoint and color as the current pen color.
	    if pico8.line_endpoint_x then
		    x0,y0,x1,y1,col=pico8.line_endpoint_x,pico8.line_endpoint_y,x0,y0,x1
		else
			pico8.line_endpoint_x = x0
			pico8.line_endpoint_y = y0
			if x1 ~= pico8.color then color(x1) end -- rostok: skip color if same
			return
		end
	end

	if col and col ~= pico8.color then color(col) end -- rostok: skip color if same

	pico8.line_endpoint_x = x1
	pico8.line_endpoint_y = y1

	x0 = flr(x0) -- + 1
	y0 = flr(y0) -- + 1
	x1 = flr(x1) -- + 1
	y1 = flr(y1) -- + 1

	local dx = x1 - x0
	local dy = y1 - y0
	local stepx, stepy

	local points = __tempPointsTable
	table_clear(points)
	points[#points+1]=x0
	points[#points+1]=y0

	if dx == 0 then
		-- simple case draw a vertical line
		points = {}
		if y0 > y1 then
			y0, y1 = y1, y0
		end
		for y = y0, y1 do
			points[#points+1]=x0
			points[#points+1]=y
				end
	elseif dy == 0 then
		-- simple case draw a horizontal line
		points = {}
		if x0 > x1 then
			x0, x1 = x1, x0
		end
		for x = x0, x1 do
			points[#points+1]=x
			points[#points+1]=y0
		end
	else
		if dy < 0 then
			dy = -dy
			stepy = -1
		else
			stepy = 1
		end

		if dx < 0 then
			dx = -dx
			stepx = -1
		else
			stepx = 1
		end

		if dx > dy then
			local fraction = dy - bit.rshift(dx, 1)
			while x0 ~= x1 do
				if fraction >= 0 then
					y0 = y0 + stepy
					fraction = fraction - dx
				end
				x0 = x0 + stepx
				fraction = fraction + dy
				points[#points+1]=x0
				points[#points+1]=y0
			end
		else
			local fraction = dx - bit.rshift(dy, 1)
			while y0 ~= y1 do
				if fraction >= 0 then
					x0 = x0 + stepx
					fraction = fraction - dy
				end
				y0 = y0 + stepy
				fraction = fraction + dx
				points[#points+1]=x0
				points[#points+1]=y0
			end
		end
	end
	love.graphics.points(points)
end

-- love2d line
function api.line5(x0, y0, x1, y1, col)
	if not x0 then -- Invalidates the current endpoint.
    	pico8.line_endpoint_x = nil
	    pico8.line_endpoint_y = nil
	    return
	end
	if not y0 then -- Invalidates the current endpoint. Remembers color as the current pen color.
    	pico8.line_endpoint_x = nil
	    pico8.line_endpoint_y = nil
	    if x0 ~= pico8.color then color(x0) end -- rostok: skip color if same
	    return
	end
	if not x1 then -- Draws a line from the current endpoint to (x1, y1) in the current pen color. If there is no current endpoint, nothing is drawn. Remembers (x1, y1) as the current endpoint.
	    if pico8.line_endpoint_x then
		    x0,y0,x1,y1=pico8.line_endpoint_x,pico8.line_endpoint_y,x0,y0
		else
			pico8.line_endpoint_x = x0
			pico8.line_endpoint_y = y0
			return
		end
	elseif not y1 then -- Draws a line from the current endpoint to (x1, y1) in the given color. If there is no current endpoint, nothing is drawn. Remembers (x1, y1) as the current endpoint and color as the current pen color.
	    if pico8.line_endpoint_x then
		    x0,y0,x1,y1,col=pico8.line_endpoint_x,pico8.line_endpoint_y,x0,y0,x1
		else
			pico8.line_endpoint_x = x0
			pico8.line_endpoint_y = y0
			if x1 ~= pico8.color then color(x1) end -- rostok: skip color if same
			return
		end
	end

	if col and col ~= pico8.color then color(col) end -- rostok: skip color if same

	pico8.line_endpoint_x = x1
	pico8.line_endpoint_y = y1
	
	love.graphics.line(x0, y0, x1, y1)
end


api.line = api.line0

api.thline = function(thickness,x0,y0,x1,y1,c)
	love.graphics.setLineWidth(thickness)
	color(c)
	love.graphics.line(x0,y0,x1,y1)
	love.graphics.setLineWidth(1)
end

function api.polygon(...)
	love.graphics.polygon("fill",...)
end

api.__meshVertices = {}
api.__trimeshVertices = {}
for i=1,128 do
	api.__meshVertices[i] = {0,0,0}
	api.__trimeshVertices[i] = {0,0,0}
end
api.__mesh = love.graphics.newMesh(api.__meshVertices,"fan","dynamic")
api.__trimesh = love.graphics.newMesh(api.__meshVertices,"triangles","dynamic")

function api.meshpolygonOLD(...)
    local cnt = select('#', ...);
	local args = {}
	for i = 1, cnt,2 do
        -- args[#args+1] = {select(i, ...),select(i+1, ...),0,0,1,1,1,1}
        args[#args+1] = {select(i, ...),select(i+1, ...),0}
    end
	api.__mesh:setVertices(args)
	love.graphics.draw( api.__mesh )
end

-- draw zbuffered polygon, tab values are {x,y,z}
-- with z being 0..1 or smaller as in setZ()
-- buffer passed to mesh are x,y,0,z with texure-v acting as z
-- love Mesh vertices are x,y,u,v,r,g,b,alfa
-- this uses "fan" draw mode
function api.meshpolygon(tab)
	local tabSize = #tab
	local c = pico8.color
	for i = 1, tabSize do
        tab[i][5] = c
        tab[i][6] = tab[i][4] -- z
    end
	api.__mesh:setVertices(tab,1,tabSize)
	api.__mesh:setDrawRange( 1, tabSize )
	love.graphics.draw( api.__mesh )
end

function api.polygonline(...)
	love.graphics.polygon("line",...)
end

function api.pal(c0, c1, p)
	-- GTODO: 0 vs 1 indexing
	-- GTODO: support other variants of this func
	local __palette_modified = false
	local __display_modified = false
	if type(c0) ~= "number" then
		for i = 0, 15 do
			if pico8.draw_palette[i] ~= i then
				pico8.draw_palette[i] = i
				__palette_modified = true
			end
			if pico8.display_palette[i] ~= pico8.palette[i] then
				pico8.display_palette[i] = pico8.palette[i]
				__display_modified = true
			end
		end
		if __palette_modified then
			pico8.draw_shader:send("palette", shdr_unpack(pico8.draw_palette))
			pico8.sprite_shader:send("palette", shdr_unpack(pico8.draw_palette))
			pico8.text_shader:send("palette", shdr_unpack(pico8.draw_palette))
		end
		if __display_modified then
			pico8.display_shader:send("palette", shdr_unpack(pico8.display_palette))
		end
		-- According to PICO-8 manual:
		-- pal() to reset to system defaults (including transparency values)
		api.palt()
	elseif p == 1 and c1 ~= nil then
		c0 = flr(c0) % 16
		if c1>15 or c1<0 then 
			c1 = 16 + flr(c1) % 16
		else 
			c1 = flr(c1) % 16 
		end
		pico8.display_palette[c0] = pico8.palette[c1]
		pico8.display_shader:send("palette", shdr_unpack(pico8.display_palette))
	elseif c1 ~= nil then
		c0 = flr(c0) % 16
		if c1>15 or c1<0 then 
			c1 = 16 + flr(c1) % 16
		else
		    c1 = flr(c1) % 16 
		end
		if pico8.draw_palette[c0] ~= c1 then
			pico8.draw_palette[c0] = c1
			pico8.draw_shader:send("palette", shdr_unpack(pico8.draw_palette))
			pico8.sprite_shader:send("palette", shdr_unpack(pico8.draw_palette))
			pico8.text_shader:send("palette", shdr_unpack(pico8.draw_palette))
		end
	end
end

function api.palt(c, t)
	local __alpha_modified=false
	c = tonumber(c)
	if c == nil then
		for i = 0, 15 do
			local v = i == 0 and 0 or 1
			if pico8.pal_transparent[i] ~= v then
				pico8.pal_transparent[i] = v
				__alpha_modified = true
			end
		end
	else
		c = flr(c) % 16
		local v = t and 0 or 1
		if pico8.pal_transparent[c] ~= v then
			pico8.pal_transparent[c] = v
			__alpha_modified = true
		end
	end
	if __alpha_modified then
		pico8.sprite_shader:send("transparent", shdr_unpack(pico8.pal_transparent))
	end
end

function api.fillp(_)
	-- TODO: implement this
end

function api.map(cel_x, cel_y, sx, sy, cel_w, cel_h, bitmask)
	love.graphics.setShader(pico8.sprite_shader)
	love.graphics.setColor(1, 1, 1, 1)
	refresh_spritesheet()
	cel_x = flr(tonumber(cel_x) or 0)
	cel_y = flr(tonumber(cel_y) or 0)
	sx = flr(tonumber(sx) or 0)
	sy = flr(tonumber(sy) or 0)
	cel_w = flr(tonumber(cel_w) or 128)
	cel_h = flr(tonumber(cel_h) or 64)
	bitmask = tonumber(bitmask) or 0

	for y = 0, cel_h - 1 do
		if cel_y + y < 64 and cel_y + y >= 0 then
			for x = 0, cel_w - 1 do
				if cel_x + x < 128 and cel_x + x >= 0 then
					local v = pico8.map[flr(cel_y + y)][flr(cel_x + x)]
					if v > 0 then
						if bitmask == 0 or
							bit.band(pico8.spriteflags[v], bitmask) ~= 0 then
							love.graphics.draw(
								pico8.spritesheet,
								pico8.quads[v],
								sx + 8 * x,
								sy + 8 * y
							)
						end
					end
				end
			end
		end
	end
	love.graphics.setShader(pico8.draw_shader)
end
-- deprecated pico-8 function
api.mapdraw = api.map

function api.mget(x, y)
	x = flr(tonumber(x) or 0)
	y = flr(tonumber(y) or 0)
	if x >= 0 and x < 128 and y >= 0 and y < 64 then
		return pico8.map[y][x]
	end
	return 0
end

function api.mset(x, y, v)
	x = flr(tonumber(x) or 0)
	y = flr(tonumber(y) or 0)
	v = flr(tonumber(v) or 0) % 256
	if x >= 0 and x < 128 and y >= 0 and y < 64 then
		pico8.map[y][x] = v
	end
end

function api.fget(n, f)
	-- difference from pico8: fget() returns fget(0) instead of nil
	-- TODO: handle this properly with varargs
	-- if n == nil then
	-- 	return nil
	-- end
	n = flr(tonumber(n) or 0)
	if f ~= nil then
		f = flr(tonumber(f) or 0)
		-- return just that bit as a boolean
		if not pico8.spriteflags[flr(n)] then
			warning(string.format("fget(%d, %d)", n, f))
			return false
		end
		return bit.band(pico8.spriteflags[n], bit.lshift(1, f)) ~= 0
	end
	return pico8.spriteflags[n] or 0
end

function api.fset(n, f, v)
	-- fset n [f] v
	-- f is the flag index 0..7
	-- v is boolean
	if n == nil then
		return
	end
	n = flr(tonumber(n) or 0)
	if v == nil then
		v, f = f, nil
	end
	if f then
		f = flr(tonumber(f) or 0)
		-- set specific bit to v (true or false)
		if v then
			pico8.spriteflags[n] = bit.bor(pico8.spriteflags[n], bit.lshift(1, f))
		else
			pico8.spriteflags[n] =
				bit.band(pico8.spriteflags[n], bit.bnot(bit.lshift(1, f)))
		end
	else
		v = flr(tonumber(v) or 0)
		-- set bitfield to v (number)
		pico8.spriteflags[n] = v
	end
end

function api.sget(x, y)
	-- return the color from the spritesheet
	x = flr(tonumber(x) or 0)
	y = flr(tonumber(y) or 0)

	if x >= 0 and x < 128 and y >= 0 and y < 128 then
		-- local c = pico8.spritesheet_data:getPixel(x, y)*15
		local c = pico8.spritesheet_data:getPixel(x, y)*63 -- 64 colors
		return c
	end
	return 0
end

function api.sset(x, y, c)
	x = flr(tonumber(x) or 0)
	y = flr(tonumber(y) or 0)
	c = flr(tonumber(c) or 0)%16
	if x>=0 and x<128 and y>=0 and y<128 then
		-- pico8.spritesheet_data:setPixel(x, y, c / 15, 0, 0, 1)
		pico8.spritesheet_data:setPixel(x, y, c / 63, 0, 0, 1) -- 64 colors
		pico8.spritesheet_changed = true --lazy
	end
end

function api.music(n, fade_len, channel_mask) -- luacheck: no unused
	-- TODO: implement fade out
	if n == -1 then
		if pico8.current_music then
			for i = 0, 3 do
				if pico8.music[pico8.current_music.music][i] < 64 then
					pico8.audio_channels[i].sfx = nil
					pico8.audio_channels[i].offset = 0
					pico8.audio_channels[i].last_step = -1
				end
			end
			pico8.current_music = nil
		end
		return
	end
	local m = pico8.music[n]
	if not m then
		warning(string.format("music %d does not exist", n))
		return
	end
	local music_speed = nil
	local music_channel = nil
	for i = 0, 3 do
		if m[i] < 64 then
			local sfx = pico8.sfx[m[i]]
			if music_speed == nil or music_speed > sfx.speed then
				music_speed = sfx.speed
				music_channel = i
			end
		end
	end
	pico8.audio_channels[music_channel].loop = false
	pico8.current_music = {
		music = n,
		offset = 0,
		channel_mask = channel_mask or 15,
		speed = music_speed,
	}
	for i = 0, 3 do
		if pico8.music[n][i] < 64 then
			pico8.audio_channels[i].sfx = pico8.music[n][i]
			pico8.audio_channels[i].offset = 0
			pico8.audio_channels[i].last_step = -1
		end
	end
end

function api.sfx(n, channel, offset)
	-- n = -1 stop sound on channel
	-- n = -2 to stop looping on channel
	channel = channel or -1
	if n == -1 and channel >= 0 then
		pico8.audio_channels[channel].sfx = nil
		return
	elseif n == -2 and channel >= 0 then
		pico8.audio_channels[channel].loop = false
	end
	offset = offset or 0
	if channel == -1 then
		-- find a free channel
		for i = 0, 3 do
			if pico8.audio_channels[i].sfx == nil then
				channel = i
			end
		end
	end
	if channel == -1 then
		return
	end
	local ch = pico8.audio_channels[channel]
	ch.sfx = n
	ch.offset = offset
	ch.last_step = offset - 1
	ch.loop = true
end

function api.peek(addr)
	addr = flr(tonumber(addr) or 0)
	if addr < 0 then
		return 0
	elseif addr < 0x2000 then
		-- local lo = pico8.spritesheet_data:getPixel(addr*2%128, flr(addr/64))*15
		-- local hi = pico8.spritesheet_data:getPixel(addr*2%128+1, flr(addr/64))*15
		local lo = pico8.spritesheet_data:getPixel(addr*2%128, flr(addr/64))*63 -- 64 colors
		local hi = pico8.spritesheet_data:getPixel(addr*2%128+1, flr(addr/64))*63 -- 64 colors
		return hi*16+lo
	elseif addr < 0x3000 then
		addr = addr - 0x2000
		return pico8.map[flr(addr / 128)][addr % 128]
	elseif addr < 0x3100 then
		return pico8.spriteflags[addr - 0x3000]
	elseif addr < 0x3200 then -- luacheck: ignore 542
		-- TODO: music data
	elseif addr < 0x4300 then -- luacheck: ignore 542
		-- TODO: sfx data
	elseif addr < 0x5e00 then
		return pico8.usermemory[addr - 0x4300]
	elseif addr < 0x5f00 then
		local val = pico8.cartdata[flr((addr - 0x5e00) / 4)] * 0x10000
		local shift = (addr % 4) * 8
		return bit.rshift(bit.band(val, bit.lshift(0xFF, shift)), shift)
	elseif addr < 0x5f40 then
		-- TODO: draw state
		if addr == 0x5f20 then
			return pico8.clip[1]
		elseif addr == 0x5f21 then
			return pico8.clip[2]
		elseif addr == 0x5f22 then
			return pico8.clip[1] + pico8.clip[3]
		elseif addr == 0x5f23 then
			return pico8.clip[2] + pico8.clip[4]
		elseif addr == 0x5f25 then
			return pico8.color
		elseif addr == 0x5f26 then
			return pico8.cursor[1]
		elseif addr == 0x5f27 then
			return pico8.cursor[2]
		elseif addr == 0x5f28 then
			return pico8.camera_x % 256
		elseif addr == 0x5f29 then
			return flr(pico8.camera_x / 256)
		elseif addr == 0x5f2a then
			return pico8.camera_y % 256
		elseif addr == 0x5f2b then
			return flr(pico8.camera_y / 256)
		elseif addr == 0x5f2c then -- luacheck: ignore 542
			-- TODO: screen transformation mode
		elseif addr == 0x5f2d then
			-- TODO: fully implement
			return love.keyboard.hasTextInput()
		end
	elseif addr < 0x5f80 then -- luacheck: ignore 542
		-- TODO: hardware state
	elseif addr < 0x6000 then -- luacheck: ignore 542
		-- TODO: gpio pins
	elseif addr < 0x8000 then
		-- screen data
		local dx = (addr - 0x6000) % 64
		local dy = flr((addr - 0x6000) / 64)
		local low = api.pget(dx, dy)
		local high = bit.lshift(api.pget(dx + 1, dy), 4)
		return bit.bor(low, high)
	end
	return 0
end

function api.poke(addr, val)
	if tonumber(val) == nil then
		return
	end
	addr, val = flr(tonumber(addr) or 0), flr(val) % 256
	if addr < 0 or addr >= 0x8000 then
		error("bad memory access")
	elseif addr < 0x1000 then -- luacheck: ignore 542
		local lo=val%16
		local hi=flr(val/16)
		pico8.spritesheet_data:setPixel(addr*2%128, flr(addr/64), lo/15, 0, 0, 1)
		pico8.spritesheet_data:setPixel(addr*2%128+1, flr(addr/64), hi/15, 0, 0, 1)
		pico8.spritesheet_changed = true --lazy
	elseif addr < 0x2000 then
		local lo=val%16
		local hi=flr(val/16)
		pico8.spritesheet_data:setPixel(addr*2%128, flr(addr/64), lo/15, 0, 0, 1)
		pico8.spritesheet_data:setPixel(addr*2%128+1, flr(addr/64), hi/15, 0, 0, 1)
		pico8.spritesheet_changed = true --lazy
		pico8.map[flr(addr/128)][addr%128]=val
	elseif addr < 0x3000 then
		addr = addr - 0x2000
		pico8.map[flr(addr / 128)][addr % 128] = val
	elseif addr < 0x3100 then
		pico8.spriteflags[addr - 0x3000] = val
	elseif addr < 0x3200 then -- luacheck: ignore 542
		-- TODO: music data
	elseif addr < 0x4300 then -- luacheck: ignore 542
		-- TODO: sfx data
	elseif addr < 0x5e00 then
		pico8.usermemory[addr - 0x4300] = val
	elseif addr < 0x5f00 then -- luacheck: ignore 542
		local ind=math.floor((addr-0x5e00)/4)
		local oval=pico8.cartdata[ind]*0x10000
		local shift=(addr%4)*8
		pico8.cartdata[ind]=bit.bor(bit.band(oval, bit.bnot(bit.lshift(0xFF, shift))), bit.lshift(val, shift))/0x10000
	elseif addr < 0x5f40 then -- luacheck: ignore 542
		-- TODO: draw state
		if addr == 0x5f26 then
			pico8.cursor[1] = val
		elseif addr == 0x5f27 then
			pico8.cursor[2] = val
		elseif addr == 0x5f28 then
			pico8.camera_x = flr(pico8.camera_x / 256) + val % 256
		elseif addr == 0x5f29 then
			pico8.camera_x = flr((val % 256) * 256) + pico8.camera_x % 256
		elseif addr == 0x5f2a then
			pico8.camera_y = flr(pico8.camera_y / 256) + val % 256
		elseif addr == 0x5f2b then
			pico8.camera_y = flr((val % 256) * 256) + pico8.camera_y % 256
		elseif addr == 0x5f2c then -- luacheck: ignore 542
			-- TODO: screen transformation mode
		elseif addr == 0x5f2d then
			love.keyboard.setTextInput(bit.band(val, 1) == 1)

			if bit.band(val, 2) == 1 then -- luacheck: ignore 542
				-- TODO mouse buttons
			else -- luacheck: ignore 542
			end

			if bit.band(val, 4) == 1 then -- luacheck: ignore 542
				-- TODO pointer lock
			else -- luacheck: ignore 542
			end
		end
	elseif addr < 0x5f80 then -- luacheck: ignore 542
		-- TODO: hardware state
	elseif addr < 0x6000 then -- luacheck: ignore 542
		-- TODO: gpio pins
	elseif addr < 0x8000 then
		addr = addr - 0x6000
		local dx = addr % 64 * 2
		local dy = flr(addr / 64)
		api.pset(dx, dy, bit.band(val, 15))
		api.pset(dx + 1, dy, bit.rshift(val, 4))
	end
end

function api.peek2(addr)
	local val = 0
	val = val + api.peek(addr + 0)
	val = val + api.peek(addr + 1) * 0x100
	return val
end

function api.peek4(addr)
	local val = 0
	val = val + api.peek(addr + 0) / 0x10000
	val = val + api.peek(addr + 1) / 0x100
	val = val + api.peek(addr + 2)
	val = val + api.peek(addr + 3) * 0x100
	return val
end

function api.poke2(addr, val)
	api.poke(addr + 0, bit.rshift(bit.band(val, 0x00FF), 0))
	api.poke(addr + 1, bit.rshift(bit.band(val, 0xFF00), 8))
end

function api.poke4(addr, val)
	val = val * 0x10000
	api.poke(addr + 0, bit.rshift(bit.band(val, 0x000000FF), 0))
	api.poke(addr + 1, bit.rshift(bit.band(val, 0x0000FF00), 8))
	api.poke(addr + 2, bit.rshift(bit.band(val, 0x00FF0000), 16))
	api.poke(addr + 3, bit.rshift(bit.band(val, 0xFF000000), 24))
end

function api.memcpy(dest_addr, source_addr, len)
	--GTODO
	if len < 1 or dest_addr == source_addr then
		return
	end

	-- only for range 0x6000 + 0x8000
	if source_addr < 0x6000 or dest_addr < 0x6000 then
		return
	end
	if source_addr + len > 0x8000 or dest_addr + len > 0x8000 then
		return
	end
	love.graphics.setCanvas()
	local img = pico8.screen:newImageData()
	api.setPicoCanvas()
	for i = 0, len - 1 do
		local x = flr(source_addr - 0x6000 + i) % 64 * 2
		local y = flr((source_addr - 0x6000 + i) / 64)
		--TODO: why are colors broken?
		local c = api.ceil(img:getPixel(x, y) / 16)
		local d = api.ceil(img:getPixel(x + 1, y) / 16)
		if c ~= 0 then
			c = c - 1
		end
		if d ~= 0 then
			d = d - 1
		end

		local dx = flr(dest_addr - 0x6000 + i) % 64 * 2
		local dy = flr((dest_addr - 0x6000 + i) / 64)
		api.pset(dx, dy, c)
		api.pset(dx + 1, dy, d)
	end
end

function api.memset(dest_addr, val, len)
	if len < 1 then
		return
	end

	for i = dest_addr, dest_addr + len - 1 do
		api.poke(i, val)
	end
end

-- In your api.lua file (or wherever api.reload_cart is defined)

-- Ensure 'pico8', 'cartname', 'currentDirectory' are accessible.
-- If they are global in main.lua, use _G.pico8, _G.cartname, _G.currentDirectory.
-- If they are part of the api table passed to the cart, use pico8, etc.
-- For this example, I'll assume globals from main.lua.

function api.reload_cart(new_cart_filename)
    local target_cartname = new_cart_filename or _G.cartname -- Reload current or specified cart

    if not target_cartname then
        api.print("ERROR: NO CART SPECIFIED FOR RELOAD.", 1, 20, 8)
        if _G.cartname then api.print("CURRENT: " .. _G.cartname, 1, 28, 7) end
        log("Error: No cart name available for reload.")
        return false
    end

    log("Attempting to reload cart: " .. target_cartname)
    api.print("RELOADING: " .. target_cartname, 1, 1, 7) -- Display message on screen

    -- 1. Stop any currently playing audio from the old cart
    api.music(-1) -- Stop music
    for i = 0, 3 do
        api.sfx(-1, i) -- Stop SFX on all channels
        -- Optionally, reset more detailed state in _G.pico8.audio_channels[i] if needed
        if _G.pico8 and _G.pico8.audio_channels and _G.pico8.audio_channels[i] then
            _G.pico8.audio_channels[i].sfx = nil
            _G.pico8.audio_channels[i].offset = 0
            -- etc.
        end
    end
    _G.pico8.current_music = nil

    local previous_cartname = _G.cartname -- Save in case _load fails for a *new* cart
    local load_success = _load(target_cartname)

    if load_success then
        -- log("Cart '" .. target_cartname .. "' loaded successfully by _G._load.")
        -- 3. Call api.run() to initialize the newly loaded cart
        --    api.run() should call the cart's _init() function (if it exists)
        --    and reset default PICO-8 API states (pal, camera, clip, color).
        api.run()
        return true
    else
        log("Failed to load cart '" .. target_cartname .. "' via _G._load.")
        api.print("RELOAD FAILED: " .. target_cartname, 1, 10, 8)
        -- Optionally, try to reload the *previous* cart if loading a new one failed
        if new_cart_filename and previous_cartname and previous_cartname ~= new_cart_filename then
            log("Attempting to restore previous cart: " .. previous_cartname)
            api.print("REVERTING TO: " .. previous_cartname, 1, 18, 7)
            if _G._load(previous_cartname) then
                api.run()
            end
        end
        return false
    end
end

function api.reload(dest_addr, source_addr, len, filepath) -- luacheck: no unused
	-- FIXME: doesn't handle filepaths
	--
	dest_addr = flr(tonumber(dest_addr) or 0)
	source_addr = flr(tonumber(source_addr) or 0)
	len = flr(tonumber(len) or 0x4300)
	len = math.min(0x4300-source_addr, len)
	for i=0, len-1 do
		api.poke(dest_addr+i, pico8.rom[source_addr+i])
	end

end

function api.cstore(dest_addr, source_addr, len) -- luacheck: no unused
	-- TODO: implement this
end

function api.rnd(x)
	return love.math.random() * (x or 1) -- rostok: optimize for speed tonumber(x)
end

-- api.rnd = love.math.random

function api.srand(seed)
	seed=seed or 0 -- rostok: optimize for speed tonumber(seed)
	if seed == 0 then
		seed = 1
	end
	return love.math.setRandomSeed(flr(seed * 0x8000))
end

api.table = table
api.flr = math.floor
api.ceil = math.ceil

function api.sgn(x)
	x = x or 0 -- rostok: optimize for speed tonumber(x)
	return x < 0 and -1 or 1
end

api.abs = math.abs

function api.min(a, b)
	a = a or 0 -- rostok: optimize for speed tonumber(a)
	b = b or 0 -- rostok: optimize for speed tonumber(b)
	return a < b and a or b
end

function api.max(a, b)
	a = a or 0 -- rostok: optimize for speed tonumber(a)
	b = b or 0 -- rostok: optimize for speed tonumber(b)
	return a > b and a or b
end

function api.mid(x, y, z)
	x = x or 0 -- rostok: optimize for speed tonumber(x)
	y = y or 0 -- rostok: optimize for speed tonumber(y)
	z = z or 0 -- rostok: optimize for speed tonumber(z)
	if x > y then
		x, y = y, x
	end
	return api.max(x, api.min(y, z))
end

function api.cos(x)
	return math.cos((x or 0) * math.pi * 2)
end

function api.sin(x)
	return -math.sin((x or 0) * math.pi * 2)
end

api.sqrt = math.sqrt

function api.atan2(x, y)
	return (0.75 + math.atan2(x, y) / (math.pi * 2)) % 1.0
end

local bit = require("bit")

function api.band(x, y)
	return bit.band(x*0x10000, y*0x10000)/0x10000
end

function api.bor(x, y)
	return bit.bor(x*0x10000, y*0x10000)/0x10000
end

function api.bxor(x, y)
	return bit.bxor(x*0x10000, y*0x10000)/0x10000
end

function api.bnot(x)
	return bit.bnot(x*0x10000)/0x10000
end

function api.shl(x, y)
	return bit.lshift(x*0x10000, y)/0x10000
end

function api.shr(x, y)
	return bit.arshift(x*0x10000, y)/0x10000
end

function api.lshr(x, y)
	return bit.rshift(x*0x10000, y)/0x10000
end

function api.rotl(x, y)
	return bit.rol(x*0x10000, y)/0x10000
end

function api.rotr(x, y)
	return bit.ror(x*0x10000, y)/0x10000
end

function api.loadcart(filename)
	local hasloaded = _load(filename)
	if hasloaded then
		love.window.setTitle(string.upper(cartname) .. " (PICOLÖVE)")
	end
	return hasloaded
end

function api.savecart()
	-- TODO: implement this
end

-- evaluate single lua expression in cart context
function api.eval(code)
    local function try_load_single_expression(code)
        local func, err = loadstring("return " .. code, "api.eval")
        if func then
            return func  -- Return the function directly if it's a single expression
        end
        return nil, err
    end

    code = code or "nil"

    local f, err = try_load_single_expression(code)
    if not f then
        -- If it's not a single expression, load it as a full code block
        f, err = loadstring(code, "api.eval")
        if not f then
            print("eval error: " .. (err or "nil"))
            return false, err  -- Return failure status and error message
        end
    end

    -- setfenv(f, pico8.cart)
	setfenv(f, pico8.cart._ENV)

    -- Execute the function in protected mode to catch errors
    local result = api.pack( pcall(f) )
	local success = table.remove(result, 1)
    if not success then
        print("eval runtime error: ", unpack(result))
    end

    return success, unpack(result)
end

-- set value in global pico8 cart namespace by string path, for example api.evalset("view.groundColor", 3, true)
function api.evalset(fieldString, value, createFields)
    local current = pico8.cart._ENV
    local lastPart

    for part in string.gmatch(fieldString, "[^.]+") do
        if lastPart then
            -- If the field doesn't exist, create it if createFields is true
            if not current[lastPart] then
                if createFields then
                    current[lastPart] = {}
                else
                    return false, "Field path is invalid"
                end
            end
            current = current[lastPart]
        end
        lastPart = part
    end

    -- Set the final part to the desired value
    current[lastPart] = value
    return true
end

-- get value in global pico8 cart namespace by string path, for example api.evalget("view.groundColor")
function api.evalget(fieldString)
    local current = pico8.cart._ENV

    for part in string.gmatch(fieldString, "[^.]+") do
        current = current[part]
        if not current then
            return nil, "Field path is invalid"
        end
    end

    return current
end

function api.run()
	if not cartname then
		return
	end
	host_time = 0
	api.setPicoCanvas()
	love.graphics.setShader(pico8.draw_shader)
	restore_clip()
	love.graphics.origin()

	api.clip()
	pico8.cart = new_sandbox()

	pico8.can_pause = true
	pico8.can_shutdown = false

	for addr = 0x4300, 0x5e00 - 1 do
		pico8.usermemory[addr - 0x4300] = 0
	end

	for i = 0, 63 do
		pico8.cartdata[i] = 0
	end

	local ok, f, e = pcall(load, loaded_code, cartname)
	if not ok or f == nil then
		-- log("=======8<========")
		-- log(loaded_code)
		-- log("=======>8========")
		error("Error loading lua: " .. tostring(e))
	else
		setfenv(f, pico8.cart)
		love.graphics.setShader(pico8.draw_shader)
		api.setPicoCanvas()
		love.graphics.origin()
		restore_clip()
		
		if __no_pcall then
			f() 
		else
			ok, e = pcall(f)
		end

		if not ok then
			print("cartname" .. cartname)
			error("Error running lua: " .. tostring(e))
		else
			log("lua completed")
		end
	end
	if pico8.cart._init then
		log("INITIALIZING")
		pico8.cart._init()
		log("INITIALIZED")
	end
	if pico8.cart._update60 then
		setfps(60)
	else
		setfps(30)
	end
end

function api.stop(message, x, y, col) -- luacheck: no unused
	print(message)
	love.event.quit() 
end

function api.reboot()
	love.window.setTitle("UNTITLED.P8 (PICOLÖVE)")
	_load("nocart.p8")
	api.run()
	cartname = nil
end

function api.shutdown()
	if pico8.can_shutdown then
		love.event.quit()
	end
end

api.exit = api.shutdown

function api.info()
	-- TODO: implement this
end

function api.export()
	-- TODO: implement this
end

function api.import()
	-- TODO: implement this
end

-- TODO: dummy api implementation should just return return null
--function api.help()
--	return nil
--end
-- TODO: move implementatn into nocart
function api.help()
	local commandKey = "ctrl"
	if love.system.getOS() == "OS X" then
		commandKey = "control"
	end

	api.rectfill(0, api._getcursory(), 128, 128, 0)
	api.print("")
	api.color(12)
	api.print("commands")
	api.print("")
	api.color(6)
	api.print("load <filename>  save <filename>")
	api.print("run              resume")
	api.print("shutdown         reboot")
	api.print("install_demos    ls")
	api.print("cd <dirname>     mkdir <dirname>")
	api.print("cd ..     to go up a directory")
	api.print("")
	api.print("alt+enter to toggle fullscreen")
	api.print("alt+f4 or " .. commandKey .. "+q to fastquit")
	api.print("")
	api.color(12)
	api.print("see readme.md for more info")
	api.print("or visit: github.com/picolove")
	api.print("")
end

function api.ht()
    return host_time
end

function api.time()
	return pico8.frames/(pico8.fps or 30)
	-- return host_time
end
api.t = api.time

function api.login()
	return nil
end

function api.logout()
	return nil
end

function api.bbsreq()
	return nil
end

function api.scoresub()
	return nil, 0
end

function api.extcmd(_)
	-- TODO: Implement this?
end

function api.radio()
	return nil, 0
end

-- returns true is mouse button (1,2,3) was pressed this frame
function api.mousePressed(b)
	b = b or 0
	b = api.shl(1,b-1)
	return bit.band(pico8.mouseButtonsStatePrev,b)==0 and bit.band(pico8.mouseButtonsState,b)~=0
end

-- returns true is mouse button (1,2,3) was released this frame
function api.mouseReleased(b)
	b = b or 0
	b = api.shl(1,b-1)
	return bit.band(pico8.mouseButtonsStatePrev,b)~=0 and bit.band(pico8.mouseButtonsState,b)==0
end

-- checks if the game window has keyboard focus.
function api.hasFocus()
	return love.window.hasFocus()
end

function api.isDown(...)
	for i, arg in ipairs({...}) do
		if arg=="mouse1" or arg=="mouse2" or arg=="mouse3" or arg=="mouse4" or arg=="mouse5" then 
			if     arg=="mouse1" and love.mouse.isDown(1) then return true 
			elseif arg=="mouse2" and love.mouse.isDown(2) then return true 
			elseif arg=="mouse3" and love.mouse.isDown(3) then return true 
			elseif arg=="mouse4" and love.mouse.isDown(4) then return true 
			elseif arg=="mouse5" and love.mouse.isDown(5) then return true end
		elseif arg=="shift" then
			if pico8.keys["lshift"] or pico8.keys["rshift"] then return true end
		elseif arg=="alt" then
			if pico8.keys["lalt"] or pico8.keys["ralt"] then return true end
		elseif arg=="ctrl" then
			if pico8.keys["lctrl"] or pico8.keys["rctrl"] then return true end
		elseif pico8.keys[arg] then return true end
	end
	return false
end

-- clears pressed key state, no arg will clear all keys
function api.unpress(...)
	if select("#",...)==0 then
		pico8.keys = {}
		pico8.last_keys = {}
		return
	end
	for i, arg in ipairs({...}) do pico8.keys[arg]=nil end
end

function api.isPressed(...)
	for i, arg in ipairs({...}) do
	  if arg == "mouse1" or arg == "mouse2" or arg == "mouse3" or arg == "mouse4" or arg == "mouse5" then 
		if     arg == "mouse1" and api.mousePressed(1) then return true 
		elseif arg == "mouse2" and api.mousePressed(2) then return true 
		elseif arg == "mouse3" and api.mousePressed(3) then return true 
		elseif arg == "mouse4" and api.mousePressed(4) then return true 
		elseif arg == "mouse5" and api.mousePressed(5) then return true end
	  elseif pico8.keys[arg] and not pico8.last_keys[arg] then return true end
	end
	return false
end

function api.isReleased(...)
	for i, arg in ipairs({...}) do
	  if arg == "mouse1" or arg == "mouse2" or arg == "mouse3" or arg == "mouse4" or arg == "mouse5" then 
		if     arg == "mouse1" and api.mouseReleased(1) then return true 
		elseif arg == "mouse2" and api.mouseReleased(2) then return true 
		elseif arg == "mouse3" and api.mouseReleased(3) then return true 
		elseif arg == "mouse4" and api.mouseReleased(4) then return true 
		elseif arg == "mouse5" and api.mouseReleased(5) then return true end
	  elseif not pico8.keys[arg] and pico8.last_keys[arg] then return true end
	end
	return false
end
  
function api.btn(i, p)
	if i ~= nil or p ~= nil then
		i = flr(tonumber(i) or 0)
		p = flr(tonumber(p) or 0)
		if pico8.keymap[p] and pico8.keymap[p][i] then
			return pico8.keypressed[p][i] ~= nil
		end
		return false
	else
		-- return bitfield of buttons
		local bitfield = 0
		for j = 0, 7 do
			if pico8.keypressed[0][j] then
				bitfield = bitfield + bit.lshift(1, j)
			end
		end
		for j = 0, 7 do
			if pico8.keypressed[1][j] then
				bitfield = bitfield + bit.lshift(1, j + 8)
			end
		end
		return bitfield
	end
end


function api.btnp(i, p)
	if i ~= nil or p ~= nil then
		i = flr(tonumber(i) or 0)
		p = flr(tonumber(p) or 0)
		if pico8.keymap[p] and pico8.keymap[p][i] then
			local v = pico8.keypressed[p][i]
			if v and (v == 0 or (v >= 12 and v % 4 == 0)) then
				return true
			end
		end
		return false
	else
		-- return bitfield of buttons
		local bitfield = 0
		for j = 0, 7 do
			if pico8.keypressed[0][j] then
				bitfield = bitfield + bit.lshift(1, j)
			end
		end
		for j = 0, 7 do
			if pico8.keypressed[1][j] then
				bitfield = bitfield + bit.lshift(1, j + 8)
			end
		end
		return bitfield
	end
end
-- GTODO: button glyphs

function api.cartdata(id) -- luacheck: no unused
	-- TODO: handle global cartdata properly
	-- TODO: handle cartdata() from console should not work
	pico8.can_cartdata = true
	-- if cartdata exists
	-- return true
	return false
end

function api.dget(index)
	-- TODO: handle global cartdata properly
	-- TODO: handle missing cartdata(id) call
	index = flr(tonumber(index) or 0)
	if not pico8.can_cartdata then
		api.print("** dget called before cartdata()", 6)
		return ""
	end
	if index < 0 or index > 63 then
		warning("cartdata index out of range")
		return 0
	end
	return pico8.cartdata[index]
end

function api.dset(index, value)
	-- TODO: handle global cartdata properly
	-- TODO: handle missing cartdata(id) call
	index = flr(tonumber(index) or 0)
	if not pico8.can_cartdata then
		api.print("** dget called before cartdata()", 6)
		return ""
	end
	if value >= 0x8000 or value < -0x8000 then
		value = -0x8000
	end
	if index < 0 or index > 63 then
		warning("cartdata index out of range")
		return
	end
	pico8.cartdata[index] = value
end

local tfield = { [0] = "year", "month", "day", "hour", "min", "sec" }
function api.stat(x)
	-- TODO: implement this
	x = flr(tonumber(x) or 0)
	if x == 0 then
		return 0 -- TODO memory usage
	elseif x == 1 then
		return 0 -- TODO total cpu usage
	elseif x == 2 then
		return 0 -- TODO system cpu usage
	elseif x == 3 then
		return 0 -- TODO current display (0..3)
	elseif x == 4 then
		return pico8.clipboard
	elseif x == 5 then
		return 33 -- pico-8 version - using latest
	elseif x == 7 then
		return pico8.fps -- current fps
	elseif x == 8 then
		return pico8.fps -- target fps
	elseif x == 9 then
		return love.timer.getFPS()
	elseif x == 30 then
		return #pico8.kbdbuffer ~= 0
	elseif x == 31 then
		return (table.remove(pico8.kbdbuffer, 1) or "")
	elseif x == 32 then
		return getmousex()
	elseif x == 33 then
		return getmousey()
	elseif x == 34 then
		local btns = 0
		for i = 0, 2 do
			if love.mouse.isDown(i + 1) then
				btns = bit.bor(btns, bit.lshift(1, i))
			end
		end
		return btns
	elseif x == 36 then
		return pico8.mwheel
	elseif (x >= 80 and x <= 85) or (x >= 90 and x <= 95) then
		local tinfo
		if x < 90 then
			tinfo = os.date("!*t")
		else
			tinfo = os.date("*t")
		end
		return tinfo[tfield[x % 10]]
	elseif x == 100 then
		return nil -- TODO: breadcrumb not supported
	elseif x == 101 then
		return nil -- TODO: bbs id not supported
	elseif x == 102 then
		return 0 -- TODO: bbs site not supported
	elseif x == 103 then -- UNKNOWN
		return "0000000000000000000000000000000000000000"
	elseif x == 104 then -- UNKNOWN
		return false
	elseif x == 106 then -- UNKNOWN
		return "0000000000000000000000000000000000000000"
	elseif x == 122 then -- UNKNOWN
		return false
	end

	return 0
end

function api.holdframe()
	-- TODO: Implement this
end

function api.menuitem(index, label, fn) -- luacheck: no unused
	-- TODO: implement this
end

api.sub = string.sub
api.pairs = pairs
api.ipairs = ipairs
api.type = type
api.assert = assert
api.setmetatable = setmetatable
api.getmetatable = getmetatable
api.cocreate = coroutine.create
api.coresume = coroutine.resume
api.yield = coroutine.yield
api.costatus = coroutine.status
api.trace = debug.traceback
api.rawset = rawset
api.rawget = rawget
function api.rawlen(table) -- luacheck: no unused
	-- TODO: implement this
end
api.rawequal = rawequal
api.next = next
api.unpack = unpack
api.pack = function (...)
    return {__size = select('#', ...), ...}
end

function api.all(a)
	if a == nil then
		return function() end
	end

	local i = 0
	local prev
	return function()
		if a[i] == prev then i = i + 1 end
		while a[i] == nil and i <= #a do
			i = i + 1
		end
		prev = a[i]
		return a[i]
	end
end

function api.foreach(a, f)
	if not a then
		-- warning("foreach got a nil value")
		return
	end

	for v in api.all(a) do
		f(v)
	end
end

-- legacy function
--   Counts elements in a table.
--   - If `val` is provided, it counts the number of times that value appears in the table.
--   - If `val` is nil, it counts the total number of key-value pairs in the table.
--   Works with both array-like (indexed) and associative tables.
function api.count(a, val)
	local count = 0
	if val ~= nil then
		-- Count specific values: Iterate through all values in the table.
		-- `pairs` is used to ensure we check every key-value pair, not just the array part.
		for _, v in pairs(a) do
			if v == val then
				count = count + 1
			end
		end
	else
		-- Count total elements: Iterate through all keys to get the total count.
		-- The `#` operator would not work for associative tables.
		for _ in pairs(a) do
			count = count + 1
		end
	end
	return count
end

function api.add(a, v, index)
	if a == nil then
		warning("add to nil")
		return
	elseif index == nil then
		table.insert(a, v)
	else
		-- table.insert(a, tonumber(index), v)
		table.insert(a, index, v) -- extra tonumber convertsion seems unnecessary
	end
	return v
end

function api.del(a, dv)
	if a == nil then
		warning("del from nil")
		return
	end
	for i, v in ipairs(a) do
		if v == dv then
			table.remove(a, i)
			return dv
		end
	end
end

-- faster api.del() but not maintaining order
function api.del2(a, dv)
	if a == nil then
		warning("del from nil")
		return
	end
	local n = #a
	for i=1,n do
		if a[i]==dv then
			a[i]=a[n]
			a[n]=nil
			return dv
		end
	end
end

function api.deliOLD(...)
	local argc = select("#", ...)
	local a = select(1, ...)
	local index = select(2, ...)

	if argc == 0 or type(a) ~= "table" or #a < 1 then
		return
	end

	if argc == 1 then
		return table.remove(a, #a)
	end

	index = tonumber(index)
	if type(index) ~= "number" then
		return
	end

	local len = #a
	for i = 1, len do
		if i == index then
			return table.remove(a, i)
		end
	end
end

-- optimized deli
function api.deli(t, index)
    if type(t) ~= "table" or #t < 1 then
        return
    end

    index = index or #t  -- default index to length of table if not provided

    if type(index) ~= "number" then
        return
    end

    return table.remove(t, index)
end

-- fast but not maintaining order, returns nothing
function api.deli2(t, index)
	local size = #t
	if #t==0 or index>#t then return end
	t[index]=t[size]
	t[size]=nil
end

api.select = select

function api.lastof(...)
    if select("#",...)==0 then return nil end
	return select(-1,...)
end

function api.lastofNEW(...)
	-- return (({...})[#{...}]) -- this is slower thatn select("#",...)
	local i = select("#",...)
	if i==0 then return nil end
	return select(i,...) or {}
end

function api.serial(channel, address, length) -- luacheck: no unused
	-- TODO: implement this
end

-- split string into table, default separator is comma
function api.split(str, sep, conv_nums)
	if type(str) ~= "string" and type(str) ~= "number" then
		return nil
	end
	str = tostring(str)
	sep=sep or ","
	str=str..sep
    if sep == "." then sep = "%." end -- escape the dot character in the pattern
	conv_nums=(conv_nums==nil) and true or conv_nums
	local tbl={}
	if sep=="" then sep = "." else sep = "(.-)"..sep end
	for val in string.gmatch(str, sep) do
		if conv_nums  and tonumber(val) ~= nil then
			val=tonumber(val)
		end
		table.insert(tbl,val)
	end
	return tbl
end

function api.writeFile(name, contents, mode)
    mode = mode or "w"
	local file = love.filesystem.newFile(name, mode)
    file:write(contents)
    file:close()
end

function api.readFile(filename)
	if love.filesystem.getInfo(filename) then
		local file = love.filesystem.newFile(filename, "r")
		local contents = file:read()
		file:close()
		return contents
	end
	return nil
end

function api.manualGC(time_budget, memory_ceiling, disable_otherwise)
	-- log("manualGC",time_budget, memory_ceiling, disable_otherwise)
	time_budget = time_budget or 1e-3
	memory_ceiling = memory_ceiling or math.huge
	local max_steps = pico8.__stats.maxGCsteps or 100
	local steps = 0
	local start_time = love.timer.getTime()
	while love.timer.getTime() - start_time < time_budget and steps < max_steps do
		collectgarbage("step", 1)
		steps = steps + 1
	end
	pico8.__stats.lastGCsteps = steps
	pico8.__stats:updateGCStats(steps,time_budget)
	-- log(steps,love.timer.getTime(),love.timer.getTime() - start_time,time_budget)
	-- log(time_budget,steps)
	--safety net
	if memory_ceiling~=math.huge and collectgarbage("count") / 1024 > memory_ceiling then
		log("GARBAGE COLLECT, exceeded "..memory_ceiling.."MB")
		collectgarbage("collect")
		log("GARBAGE COLLECT DONE")
	end
	--don't collect gc outside this margin
	if disable_otherwise then
		collectgarbage("stop")
	end
end

local file_cache = {}

local function getSourceLines(source)
	if source:sub(1, 1) ~= "@" then source = "@"..source end
    if file_cache[source] then
        return file_cache[source]
    end

    local lines = {}
    if source:sub(1, 1) == "@" then
        local filename = source:sub(2)
        local file = io.open(filename, "r")
		-- print("READ",filename)
        if file then
            for line in file:lines() do
                table.insert(lines, line)
            end
            file:close()
            file_cache[source] = lines
        end
    else
        for l in source:gmatch("(.-)\n") do
            table.insert(lines, l)
        end
        file_cache[source] = lines
    end
    return lines
end

api.traceDebugOn = function(maxlevel, minlevel)
    -- Disable JIT so that the hook works as expected.
    api.jit.off()
    print("---@diagnostic disable")

    -- Helper function to determine the current stack depth for the traced function.
    -- We start at level 2 because level 1 is the hook function itself.
    local function getCurrentStackLevel()
        local level = 2
        local count = 0
        while api.debug.getinfo(level) do
            count = count + 1
            level = level + 1
        end
        return count
    end

    -- Set a debug hook that triggers on each executed line.
    api.debug.sethook(function(event, line)
        -- Get the current stack level (excluding the hook function itself).
        local currentLevel = getCurrentStackLevel()
        -- If minlevel is given and currentLevel is lower than minlevel, skip logging.
        if minlevel and currentLevel < minlevel then
            return
        end
        -- If maxlevel is given and currentLevel is higher than maxlevel, skip logging.
        if maxlevel and currentLevel > maxlevel then
            return
        end

        local info = api.debug.getinfo(2, "nSl")
        if info then
            local source = info.source or "[unknown]"
            -- (funcname is available as info.name but not used in the print below)
            local src_lines = getSourceLines(source)
            local executing_line = src_lines[info.currentline] or "[line unavailable]"
            print(string.format("--[[%s:%d]] %s", source, info.currentline, executing_line))
        end
    end, "l")
end

api.traceDebugOff = function()
    api.debug.sethook()
    api.jit.on()
    -- print("JIT enabled, tracing disabled")
end

-- api.log = io.write
api.lognl = io.write

api.api = api -- self reference

return api
