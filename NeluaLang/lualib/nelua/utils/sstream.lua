--[[
Sstream class

The sstream (stands for string stream) is a utility to compose big strings,
by doing many small string concatenations.
It's used by the compiler to generate large strings.
]]

local class = require 'nelua.utils.class'
local metamagic = require 'nelua.utils.metamagic'
local sstream = class()
local hasmetamethod = metamagic.hasmetamethod
local concat = table.concat

-- Initialize a sstream.
function sstream._init()
  -- nothing to do
end

-- Concatenate many arguments, converting them to a string as needed.
function sstream:add(v)
  self[#self+1] = tostring(v)
end

-- Concatenate many arguments, converting them to a string as needed.
function sstream:addmany(...)
  for i=1,select('#', ...) do
    local v = select(i, ...)
    if type(v) ~= 'table' or hasmetamethod(v, '__tostring') then
      self[#self+1] = tostring(v)
    else
      self:addlist(v)
    end
  end
end

-- Concatenate a list of values using using a separator.
function sstream:addlist(list, sep)
  sep = sep or self.sep or ', '
  for i=1,#list do
    if i > 1 then
      self[#self+1] = sep
    end
    self:add(list[i])
  end
end

-- Build into single string, called when composing the stream.
function sstream:tostring()
  return concat(self)
end

sstream.__tostring = sstream.tostring

return sstream
