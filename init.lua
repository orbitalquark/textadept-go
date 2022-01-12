-- Copyright 2022 Mitchell. See LICENSE.

local M = {}

--[[ This comment is for LuaDoc.
---
-- The go module.
-- It provides utilities for editing Go code.
-- @field autocomplete_snippets (boolean)
--   Whether or not to include snippets in autocompletion lists.
--   The default value is `true`.
module('_M.go')]]

-- Autocompletion and documentation.

---
-- List of ctags files to use for autocompletion in addition to the current project's top-level
-- *tags* file or the current directory's *tags* file.
-- @class table
-- @name tags
M.tags = {_HOME .. '/modules/go/tags', _USERHOME .. '/modules/go/tags'}

M.autocomplete_snippets = true

-- LuaFormatter off
local XPM = textadept.editing.XPM_IMAGES
local xpms = setmetatable({p=XPM.NAMESPACE,c=XPM.VARIABLE,v=XPM.VARIABLE,t=XPM.STRUCT,n=XPM.TYPEDEF,w=XPM.VARIABLE,e=XPM.VARIABLE,m=XPM.METHOD,r=XPM.SLOT,f=XPM.METHOD },{__index=function()return 0 end})
-- LuaFormatter on

-- Attempts to identify the type of the given symbol.
-- Also indicates if the symbol type is inferred from the result of a function call.
-- @param symbol The symbol to identify the type of.
-- @return string symbol type and whether or not it should be inferred from a function call
local function get_type(symbol)
  local symbol_patt = symbol:gsub('%p', '%%%0')
  local arg_patt = '[^%w_]' .. symbol_patt .. '%s+[%*&]?([%w_%.]+)'
  local var_patt = '^%s*var%s+' .. symbol_patt .. '%s+[%*&]?([%w_%.]+)'
  local var_patt2 = '^%s*var%s+' .. symbol_patt .. '%s*=%s*[%*&]?([%w_%.]+)'
  local infer_patt = '^%s*.-' .. symbol_patt .. '%f[^%w_].-:=%s*[%*&]?([%w_%.]+)%('
  local infer_patt2 = '^%s*.-' .. symbol_patt .. '%f[^%w_].-:=%s*[%*&]?([%w_%.]+)'
  local import_patt = '^%s*' .. symbol_patt .. '%s*"[^"]-([^"/]+)"%s+$'
  for i = buffer:line_from_position(buffer.current_pos) - 1, 1, -1 do
    local line = buffer:get_line(i)
    if line:find('^%s*//') then goto continue end -- ignore comments
    local type = line:match(arg_patt) or line:match(var_patt) or line:match(var_patt2)
    if type then return type, false end
    type = line:match(infer_patt)
    if type then return type, true end
    type = line:match(infer_patt2)
    if type then return type, false end
    type = line:match(import_patt) -- named import
    if type then return type, false end
    ::continue::
  end
end

textadept.editing.autocompleters.go = function()
  -- Retrieve the symbol behind the caret.
  local line, pos = buffer:get_cur_line()
  local symbol, part = line:sub(1, pos - 1):match('([%w_]-)%.?([%w_]*)$')
  if symbol == '' and part == '' then return nil end -- nothing to complete
  local infer_from_func, current_package_name
  if symbol ~= '' then
    -- Attempt to identify the symbol type.
    local type, infer = get_type(symbol)
    if type then symbol, infer_from_func = type, infer end
  else
    -- Autocompleting from the current namespace.
    -- Determine this file's package name so all symbols from this package can be found.
    for i = 1, buffer.line_count do
      current_package_name = buffer:get_line(i):match('^%s*package%s+([%w_]+)')
      if current_package_name then break end
    end
  end
  -- Search through ctags for completions for that symbol.
  local tags_files = {}
  for i = 1, #M.tags do tags_files[#tags_files + 1] = M.tags[i] end
  tags_files[#tags_files + 1] = (io.get_project_root(buffer.filename) or lfs.currentdir()) ..
    '/tags'
  local name_patt = '^' .. part
  local sep = string.char(buffer.auto_c_type_separator)
  local function add_tag(list, name, kind)
    list[#list + 1], list[name] = name .. sep .. xpms[kind], true
  end
  ::retry::
  local list = {}
  for _, filename in ipairs(tags_files) do
    if not lfs.attributes(filename) then goto continue end
    for tag_line in io.lines(filename) do
      if tag_line:find('^!') then goto continue end
      local name = tag_line:match('^%S+')
      if not name:find(name_patt) or list[name] then goto continue end
      local path, kind, fields = tag_line:match('^%S+\t([^\t]+)%.go\t[^;]+;"\t(.)\t(.+)$')
      if kind == 'i' then goto continue end -- ignore imports
      if symbol ~= '' and kind == 'p' then goto continue end -- ignore packages in this context
      -- Show top-level package completions.
      if kind == 'p' then
        add_tag(list, name, kind)
        goto continue
      end
      -- Show ctype and ntype member completions.
      local type = fields:match('ctype:(%S+)') or fields:match('ntype:(%S+)')
      if symbol:find('%.') and not infer_from_func then
        -- type is not fully qualified like foo.Bar. It just has the last part.
        symbol = symbol:match('[^%.]+$')
      end
      if type == symbol then
        add_tag(list, name, kind)
        goto continue
      end
      -- Determine which package(s) this tag could be in for subsequent processing.
      local packages = {}
      if path:find('^std/') then
        packages[path:match('[^/]+$')] = true
      else
        -- Strip platform and arch information from paths for determining package names.
        path = path:gsub('_(%a+)_?%w*$', {darwin = '', linux = '', windows = ''})
        -- Consider each part of a path to be a package and submembers to be members of parent
        -- packages. This is a simplification to show more completion possibilities.
        -- For example, given foo/bar/baz, each is a package and baz's public members will show
        -- up as completions in bar.
        for package_name in path:gmatch('[^/]+') do packages[package_name] = true end
      end
      -- Show package member completions (and builtins when possible).
      local in_a_package = packages[symbol]
      local in_this_package = packages[current_package_name]
      local show_builtin = packages.builtin and symbol == ''
      if (in_a_package or in_this_package or show_builtin) and (not type or kind == 'f') then
        add_tag(list, name, kind)
        goto continue
      end
      -- Show completions for inferred return type of function symbol.
      if infer_from_func and (kind == 'f' or kind == 'm') then
        local package_name, func_name = symbol:match('([^%.]*)%.?([^%.]+)$')
        if name == func_name and packages[package_name] then
          -- For simplicity, assume the first returned value type is it.
          -- TODO: positional type
          symbol = fields:match('type:[%*&%[%]]?([%w_]+)')
          if symbol then goto retry end
        end
      end
      ::continue::
    end
    ::continue::
  end
  if symbol == '' and M.autocomplete_snippets then
    local _, snippets = textadept.editing.autocompleters.snippet()
    for i = 1, #snippets do list[#list + 1] = snippets[i] end
  end
  return #part, list
end

for _, tags in ipairs(M.tags) do
  table.insert(textadept.editing.api_files.go, (tags:gsub('tags$', 'api')))
end

return M
