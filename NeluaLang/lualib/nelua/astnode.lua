--[[
ASTNode class

The ASTNode class is used to form the AST (abstract syntax tree)
while compiling.
]]

local pegger = require 'nelua.utils.pegger'
local class = require 'nelua.utils.class'
local errorer = require 'nelua.utils.errorer'
local iters = require 'nelua.utils.iterators'
local traits = require 'nelua.utils.traits'
local except = require 'nelua.utils.except'
local sstream = require 'nelua.utils.sstream'
local stringer = require 'nelua.utils.stringer'
local console = require 'nelua.utils.console'
local tabler = require'nelua.utils.tabler'
local shaper = require 'nelua.utils.shaper'
local Attr = require 'nelua.attr'
local lpegrex = require 'nelua.thirdparty.lpegrex'
local config = require 'nelua.configer'.get()

-- AST node class.
local ASTNode = class()

-- Base shape of an ASTNode.
ASTNode.baseshape = shaper.shape{
  -- Tag of the node.
  tag = shaper.string,
  -- Unique identifier of the node.
  uid = shaper.number:is_optional(),
  -- Position in a source file where the text chunk of the node begins.
  pos = shaper.number:is_optional(),
  -- Position in a source file where the text chunk of the node ends.
  endpos = shaper.number:is_optional(),
  -- Source where the node was parsed.
  src = shaper.shape{
    -- Source file name.
    name = shaper.string:is_optional(),
    -- Source file contents.
    content = shaper.string:is_optional(),
  }:is_optional(),
  --[[
  Attributes of the node.
  This can be shared across different nodes.
  If the node is reference to a symbol, then it will be promoted to a symbol.
  ]]
  attr = shaper.attr + shaper.symbol,
  --[[
  Table of persistent attributes.
  When a node is cloned all attributes are discarded,
  but values from `pattr` are copied into `attr` of the new cloned node.
  ]]
  pattr = shaper.table:is_optional(),
  -- Preprocess function to executed before analyzing, set to nil after preprocess is finished.
  preprocess = shaper["function"]:is_optional(),
  -- Whether the node was preprocessed (set to `true` after executing `preprocess`).
  preprocessed = shaper.boolean:is_optional(),
  -- Whether the node is completely analyzed (this is not set by all nodes).
  done = shaper.any,
  -- Whether the node is completely type checked (this is not set by all nodes).
  checked = shaper.boolean:is_optional(),
  -- Scope where the node is defined.
  scope = shaper.scope:is_optional(),
  funcdefn = shaper.boolean:is_optional(),
  funcdecl = shaper.boolean:is_optional(),
}

-- Tag for a generic ASTNode.
ASTNode.tag = 'Node'
-- Used to quickly check whether a table is an ASTNode.
ASTNode._astnode = true

-- Localize some functions used in hot code paths (optimization).
local tabler_update = tabler.update
local coroutine_yield, coroutine_wrap = coroutine.yield, coroutine.wrap
local clone_nodes, clone_node

-- Unique id counter for AST nodes.
local uid = 0

--[[
Creates an AST node with metatable `mt` filled with values `...`.
Called internally when creating or generating AST nodes.
]]
function ASTNode._create(mt, ...)
  local nuid = uid + 1
  uid = nuid
  return setmetatable({
    attr = setmetatable({}, Attr),
    uid = nuid,
    ...
  }, mt)
end

-- Allows calling ASTNode to create a new node.
getmetatable(ASTNode).__call = ASTNode._create

--[[
Creates an AST node with metatable `mt` from table `node`.
Called for every AST node initialization while parsing.
]]
function ASTNode.create_from(mt, node)
  local nuid = uid + 1
  uid = nuid
  node.uid = nuid
  node.attr = setmetatable({}, Attr)
  return setmetatable(node, mt)
end

-- Clones a list of nodes.
function ASTNode.clone_nodes(t)
  local ct = {}
  for i=1,#t do
    local v = t[i]
    if v._astnode then -- node
      ct[i] = clone_node(v)
    else -- list of nodes
      ct[i] = clone_nodes(v)
    end
  end
  return ct
end
clone_nodes = ASTNode.clone_nodes

-- Clones a node, copying only necessary values.
function ASTNode.clone(node)
  local nuid = uid + 1
  uid = nuid
  local pattr = node.pattr
  local attr = setmetatable({}, Attr)
  local cloned = setmetatable({
    attr = attr,
    pattr = pattr,
    uid = nuid,
    pos = node.pos,
    endpos = node.endpos,
    src = node.src,
    preprocess = node.preprocess,
    nil,nil,nil,nil,nil,nil -- preallocate array part (optimization)
  }, getmetatable(node))
  if pattr then -- copy persistent attributes
    tabler_update(attr, pattr)
  end
  for i=1,#node do
    local v = node[i]
    if type(v) == 'table' then
      if v._astnode then -- node
        v = clone_node(v)
      elseif v.n then -- table or arguments
        v = tabler.copy(v)
      else -- list of nodes
        v = clone_nodes(v)
      end
    end
    cloned[i] = v
  end
  return cloned
end
clone_node = ASTNode.clone

-- Helper for `ASTNode.pretty`.
local function astnode_pretty(node, indent, ss)
  if node.tag then
    ss:addmany(indent, node.tag, '\n')
  else
    ss:addmany(indent, '-', '\n')
  end
  indent = indent..'| '
  for i=1,#node do
    local child = node[i]
    local ty = type(child)
    if ty == 'table' then
      astnode_pretty(child, indent, ss)
    elseif ty == 'string' then
      ss:addmany(indent, pegger.double_quote_lua_string(child), '\n')
    else
      ss:addmany(indent, tostring(child), '\n')
    end
  end
end

-- Converts a node into a pretty human readable string.
function ASTNode.pretty(node)
  local ss = sstream()
  astnode_pretty(node, '', ss)
  ss[#ss] = nil -- remove last new line
  return ss:tostring()
end

--[[
Replaces current node values and metatable with the ones from node `node`.
Used to replace a node with a different node while reusing the original node reference.
]]
function ASTNode:transform(node)
  local mt = getmetatable(node)
  setmetatable(self, mt)
  if not mt then -- transforming into a list, must clear all fields
    for k in pairs(self) do
      self[k] = nil
    end
  end
  for i=1,math.max(#self, #node) do
    self[i] = node[i]
  end
  self.attr = node.attr
  self.pattr = node.pattr
  return self
end

--[[
Copies source origin from `node`, so error messages with this node
will print source origin.
Origin is determined by `src`, `pos`, `endpos` fields.
]]
function ASTNode:copy_origin(node)
  self.src = node.src
  self.pos = node.pos
  self.endpos = node.endpos
  return self
end

--[[
Returns a table with source location information for this node.
The following fields may be present:
* `srccode`, complete source code for the file where the node is defined.
* `srcname`, name of the source, usually a file name.
* `pos`, node's position inside `srccode` (inclusive).
* `endpos`, node's end position inside `srccode` (exclusive).
* `line`, node's line content (the first line where the node begins).
* `lineno`, node's line number.
* `linestart`, position where the node's line begins.
* `lineend`, position where the node's line ends.
* `colno`, node's column line number.
* `len`, length (it's `endpos - pos`)
]]
function ASTNode:location()
  local src, pos, endpos = self.src, self.pos, self.endpos
  local loc = {
    srccode=src and src.content,
    srcname=src and src.name,
    pos=pos,
    endpos=endpos
  }
  if src and pos then
    loc.lineno, loc.colno, loc.line, loc.linestart, loc.lineend = lpegrex.calcline(src.content, pos)
  end
  if pos and endpos then
    loc.len = endpos-pos
  end
  return loc
end

--[[
Formats a message with node source information.
Where `category` is the category name to prefix the message (e.g 'warning', 'error' or 'info'),
`message` is the message to be formatted, `...` are arguments to format the message.
]]
function ASTNode:format_message(category, message, ...)
  message = stringer.pformat(message, ...)
  if self and self.src and self.pos then
    return errorer.get_pretty_source_pos_errmsg(self:location(), message, category)
  end
  return category .. ': ' .. message .. '\n'
end

-- Raises an error related to this node using a formatted message.
function ASTNode:raisef(message, ...)
  except.raise(ASTNode.format_message(self, 'error', message, ...), 2)
end

-- Raises an error related to this node using a formatted message if `cond` is false.
function ASTNode:assertraisef(cond, message, ...)
  if not cond then --luacov:disable
    except.raise(ASTNode.format_message(self, 'error', message, ...), 2)
  end --luacov:enable
  return cond
end

-- Shows a warning related to this node using a formatted message.
function ASTNode:warnf(message, ...)
  if not config.no_warning then
    console.logerr(ASTNode.format_message(self, 'warning', message, ...))
  end
end

local ignored_stringfy_keys = {
  src = true,
  pos = true, endpos = true,
  uid = true,
  desiredtype = true,
  preprocess = true, preprocessed = true,
  loadedast = true,
  node = true,
  scope = true,
  done = true,
  untyped = true,
  checked = true,
  usedby = true,
  argattrs = true,
  defnode = true,
}

-- Helper to convert a node value to a string.
local function stringfy_val2str(val)
  local vstr = tostring(val)
  if traits.is_number(val) or traits.is_boolean(val) or val == nil then
    return vstr
  end
  return pegger.double_quote_lua_string(vstr)
end

-- Helper for `ASTNode:__tostring`.
local function stringfy_astnode(node, depth, ss, skipindent)
  local indent = string.rep('  ', depth)
  local isnode = node._astnode
  if not skipindent then
    ss:add(indent)
  end
  if isnode then
    ss:addmany(node.tag, ' ')
  end
  ss:add('{\n')
  for k,v in iters.ospairs(node) do -- use ospairs to enforce order
    if not ignored_stringfy_keys[k] then
      if isnode and k == 'attr' and traits.is_table(v) then
        if next(v) then
          ss:addmany(indent, '  attr = ')
          stringfy_astnode(v, depth+1, ss, true)
          ss:add(',\n')
        end
      else
        ss:addmany(indent, '  ', k, ' = ', stringfy_val2str(v), ',\n')
      end
    end
  end
  local nargs = #node
  if nargs > 0 then
    for i=1,nargs do
      local v = node[i]
      if type(v) == 'table' then
        stringfy_astnode(v, depth+1, ss)
      else
        ss:addmany(indent, '  ', stringfy_val2str(v))
      end
      ss:add(i == nargs and '\n' or ',\n')
    end
  end
  ss:addmany(indent, '}')
end

-- Serializes a node to a string suitable to be used in Lua code.
function ASTNode:tostring()
  local ss = sstream()
  stringfy_astnode(self, 0, ss)
  return ss:tostring()
end

-- Allows to serialize an AST node to a string with `tostring`.
ASTNode.__tostring = ASTNode.tostring

-- Helper for `ASTNode:walk_symbols`.
local function walk_symbols(node)
  if node._astnode then
    local attr = node.attr
    if attr and attr._symbol then
      coroutine_yield(attr)
    end
  end
  for i=1,#node do
    local v = node[i]
    if type(v) == 'table' then
      walk_symbols(v)
    end
  end
end

--[[
Recursively iterates all symbols found in all children nodes (including itself).
Use with `for in` to iterate all children symbols.
]]
function ASTNode:walk_symbols()
  return coroutine_wrap(walk_symbols), self
end

-- Helper for `ASTNode:walk_nodes`.
local function walk_nodes(node, parent, parentindex)
  if node._astnode then
    coroutine_yield(node, parent, parentindex)
  end
  for i=1,#node do
    local v = node[i]
    if type(v) == 'table' then
      walk_nodes(v, node, i)
    end
  end
end

--[[
Recursively iterates all child nodes (including itself).
Use with `for in` to iterate all children.

Each iteration return three values, the node followed by its parent and parent index.
The parent can be either another node or a list of nodes.
]]
function ASTNode:walk_nodes()
  return coroutine_wrap(walk_nodes), self
end

--[[
Recursively iterates child nodes (excluding itself)
where each node tag is present in `tagfilter` table, parents are also traced.
Use with `for in` to iterate children while filtering nodes and tracing parents.

If `filterall` is true, then parents are also filtered, otherwise only the iterated node.
Each iteration return two values, the node followed by a list of its parents.
Each parent can be either another node or a list of nodes.
]]
function ASTNode:walk_trace_nodes(tagfilter, filterall)
  local trace = {}
  local function walk_trace_nodes(node, n)
    local parentpos = #trace+1
    trace[parentpos] = node
    for i=1,n do
      local subnode = node[i]
      if type(subnode) == 'table' then
        if subnode._astnode then
          if tagfilter[subnode.tag] then -- is an accepted astnode
            coroutine_yield(subnode, trace)
          elseif filterall then
            goto next
          end
        end
        local subn = #subnode
        if subn > 0 then
          walk_trace_nodes(subnode, subn)
        end
        ::next::
      end
    end
    trace[parentpos] = nil
  end
  return coroutine_wrap(walk_trace_nodes), self, #self
end

--[[
Recursively search for a child node.
When found, returns its parent table or node and its index.
]]
function ASTNode:recursive_find_child(node)
  for child, parent1, parent1i in self:walk_nodes() do
    if child == node then
      return parent1, parent1i
    end
  end
end

-- Recursively checks if any child contains an attribute with name `attrname`.
function ASTNode:recursive_has_attr(attrname)
  for node in self:walk_nodes() do
    if node.attr[attrname] then
      return true
    end
  end
  return false
end

-- Finds first child with where `fieldname` evaluates to true.
function ASTNode:find_child_with_field(fieldname)
  for i=1,#self do
    local subnode = self[i]
    if type(subnode) == 'table' and subnode[fieldname] then
      return subnode
    end
  end
  return nil
end

--[[
Recursively updates `src`, `pos` and `endpos` in child nodes that are unset.
Used set a source location of generated nodes through metaprogramming.
]]
function ASTNode:recursive_update_location(src, pos, endpos)
  for node in self:walk_nodes() do
    if not node.src then
      node.src = src
      node.pos = pos
      node.endpos = endpos
    end
  end
  return false
end

--[[
Returns a simplified value for this ASTNode, that is:
- If the node holds a compile-time value, then returns it.
- If the node is associated with a symbol, then returns it.
- Otherwise, the node itself.
]]
function ASTNode:get_simplified_value()
  local attr = self.attr
  local value = attr:get_comptime_value()
  if value then
    if traits.is_bn(value) then
      value = value:compress()
    end
    return value
  end
  if attr._symbol then
    return attr
  end
  return self
end

--[[
Checks if all nested block statements ends with a node with the tag `tag`.
Returns true if all last nested block statement matches `tag`.
Usually used to check if a block ends with return statement.

This function has to perform a minimal control flow analysis to
find out if the block ends with a return.
]]
function ASTNode:ends_with(tag)
  assert(self.is_Block)
  local statnodes = self
  local laststat = statnodes[#statnodes]
  if not laststat then return false end
  if laststat.tag == tag then
    return true
  elseif laststat.is_Do then
    return laststat[1]:ends_with(tag)
  elseif laststat.is_If then
    local pairs, elseblock = laststat[1], laststat[2]
    for i=1,#pairs,2 do -- if statements
      local block = pairs[i+1]
      if not block:ends_with(tag) then
        return false
      end
    end
    if elseblock then -- else statement
      return elseblock:ends_with(tag)
    end
  elseif laststat.is_Switch then -- switch statement
    local pairs, elseblock = laststat[2], laststat[3]
    for i=1,#pairs,2 do -- case statements
      local block = pairs[i+1]
      if not block:ends_with(tag) then
        return false
      end
    end
    if elseblock then -- else statement
      return elseblock:ends_with(tag)
    end
  elseif laststat.is_While then
    -- in case of a infinite while loop without breaks, the function could never return
    -- TODO: consider goto statements breaking the loop
    -- TODO: consider infinite repeat loop
    local whilecondattr = laststat[1].attr
    if whilecondattr.comptime and whilecondattr.value == true then -- infinite loop
      for childnode in laststat:walk_trace_nodes({Do=true,If=true,Switch=true,Block=true,Break=true}, true) do
        if childnode.is_Break then
          return false
        end
      end
      return true
    end
  end
  return false
end

return ASTNode
