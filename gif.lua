-- GIF encoder specialized for PICO-8
-- by gamax92.
-- rostok: extended to 32 colors so hidden PICO-8 palette can be used
-- https://www.w3.org/Graphics/GIF/spec-gif89a.txt

local palmap={}

for i=0, 31 do -- larger pal
	local palette=pico8.palette[i]
	local value=bit.lshift(palette[1], 16)+bit.lshift(palette[2], 8)+palette[3]
	palmap[i]=value
	palmap[value]=i
end


local function num2str(data)
	return string.char(bit.band(data, 0xFF), bit.rshift(data, 8))
end

local gif={}

function gif:frame(data)
	self.file:write("\33\249\4\4\3\0\0\0")
	local last=self.last
	local x0, y0, x1, y1=0, 0, pico8.resolution[1]-1, pico8.resolution[2]-1 -- no x2 scaling

	self.file:write("\44"..num2str(x0)..num2str(y0)..num2str(x1-x0+1)..num2str(y1-y0+1).."\0\5")
	local trie={}
	for i=0, 31 do
		trie[i]={[-1]=i}
	end
	local last=33
	local trie_ptr=trie
	local stream={32}
	for y=y0, y1 do
		for x=x0, x1 do
			local r, g, b=data:getPixel(x, y)
			r, g, b=r*255, g*255, b*255
			local index=palmap[bit.lshift(r, 16)+bit.lshift(g, 8)+b]
			if trie_ptr[index] then
				trie_ptr = trie_ptr[index]
			else
				stream[#stream+1]=trie_ptr[-1]
				last=last+1
				if last<4095 then
					trie_ptr[index]={[-1]=last}
				else
					stream[#stream+1]=32
					trie={}
					for i=0, 31 do
						trie[i]={[-1]=i}
					end
					last=33
				end
				trie_ptr=trie[index]
			end
		end
	end
	stream[#stream+1]=trie_ptr[-1]
	stream[#stream+1]=33

	local output={}
	local size=6
	local bits=0
	local pack=0
	local base=-32
	for i=1, #stream do
		pack=pack+bit.lshift(stream[i], bits)
		bits=bits+size
		while bits>=8 do
			bits=bits-8
			output[#output+1]=string.char(bit.band(pack, 0xFF))
			pack=bit.rshift(pack, 8)
		end
		if i-base>=2^size then
			size=size+1
		end
		if stream[i]==32 then
			base=i-33
			size=6
		end
	end
	while bits>0 do
		bits=bits-8
		output[#output+1]=string.char(bit.band(pack, 0xFF))
		pack=bit.rshift(pack, 8)
	end
	output=table.concat(output)
	while #output>0 do
		self.file:write(string.char(math.min(#output, 255))..output:sub(1, 255))
		output=output:sub(256)
	end
	self.file:write("\0")
	self.last=data
end

function gif:close()
	self.file:write("\59")
	self.file:close()
	self.file=nil
	self.last=nil
end

local gifmt={
	__index=function(t, k)
		return gif[k]
	end
}

local giflib={}

function giflib.new(filename)
	local file, err=love.filesystem.newFile(filename, "w")
	if not file then
		return nil, err
	end
	file:write("GIF89a"..num2str(pico8.resolution[1])..num2str(pico8.resolution[2]).."\244\0\0") 
	for i=0, 31 do
		local palette=pico8.palette[i]
		file:write(string.char(palette[1], palette[2], palette[3]))
	end
	file:write("\33\255\11NETSCAPE2.0\3\1\0\0\0")
	local last=love.image.newImageData(pico8.resolution[1], pico8.resolution[2])
	return setmetatable({filename=filename, file=file, last=last, first=true}, gifmt)
end

return giflib
