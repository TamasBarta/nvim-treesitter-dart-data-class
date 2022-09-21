local ts_utils = require("nvim-treesitter.ts_utils")
local M = {}

local get_node_contents = function(node)
  local buf = vim.api.nvim_get_current_buf()
  local sl, sc, el, ec = node:range()
  local contents = vim.api.nvim_buf_get_text(buf, sl, sc, el, ec, {})[1]
  return contents
end

local find_children_by_type = function(node, type_name)
  local children = {}

  for i = 0, node:child_count() - 1, 1 do
    local child = node:child(i)
    if child:type() == type_name then
      table.insert(children, child)
    end
  end

  return children
end

local is_node_data_class = function(node)
  if "class_definition" ~= node:type() then
    return false
  end
  return true
end

local find_data_class_node = function()
  local node = ts_utils.get_node_at_cursor()

  if node == nil then
    return
  end

  local is_data_class = is_node_data_class(node)

  while not is_data_class and node ~= nil do
    ---@diagnostic disable-next-line: need-check-nil
    node = node:parent()
    is_data_class = is_node_data_class(node)
  end

  return node
end

local find_class_name = function(class_node)
  return get_node_contents(class_node:field("name")[1])
end

local find_fields_of_data_class = function(class_node)
  local class_body = class_node:field("body")[1]

  local fields = {}

  for i = 0, class_body:child_count() - 1, 1 do
    local child = class_body:child(i)

    if child:child_count() > 0 and child:child(child:child_count() - 1):type() == "initialized_identifier_list" then
      local type = get_node_contents(find_children_by_type(child, "type_identifier")[1])
      for _, initialized_identifier in ipairs(find_children_by_type(find_children_by_type(child, "initialized_identifier_list")[1], "initialized_identifier")) do
        local field = {}
        field.type = type
        field.identifier = get_node_contents(find_children_by_type(initialized_identifier, "identifier")[1])
        table.insert(fields, field)
      end
    end
  end

  return fields
end

local generate_equals_lines = function(class_name, fields)
  local ret = {}
  ret.marker_annotation = { "", "  @override" }
  ret.method_signature = { "  bool operator ==(Object other)" }
  ret.function_body = { "=>", "      identical(this, other) ||", "      other is " .. class_name .. " &&" }
  for i, field in ipairs(fields) do
    if i == table.maxn(fields) then
      table.insert(ret.function_body, "          other." .. field.identifier .. " == " .. field.identifier .. ";")
    else
      table.insert(ret.function_body, "          other." .. field.identifier .. " == " .. field.identifier .. " &&")
    end
  end
  return ret

end

local generate_hash_code_lines = function(fields)
  local ret = {}
  ret.marker_annotation = { "", "  @override" }
  ret.method_signature = { "  int get hashCode" }
  ret.function_body = { "=>" }
  for i, field in ipairs(fields) do
    if i == table.maxn(fields) then
      table.insert(ret.function_body, "      " .. field.identifier .. ".hashCode;")
    else
      table.insert(ret.function_body, "      " .. field.identifier .. ".hashCode +")
    end
  end
  return ret
end

local generate_to_string_lines = function(class_name, fields)

  local string = class_name .. "["

  local field_strings = {}

  for _, field in ipairs(fields) do
    local field_name = field.identifier
    table.insert(field_strings, field_name .. "=$" .. field_name)
  end

  string = string .. table.concat(field_strings, ", ")

  string = string .. "]"

  local ret = {}
  ret.marker_annotation = { "", "  @override" }
  ret.method_signature = { "  String toString()" }
  ret.function_body = { "=>", "      '" .. string .. "';" }
  return ret
end

local prepend_nodes_last_line_with_lines = function(node, new_lines)
  local buf = vim.api.nvim_get_current_buf()

  local _, _, end_, _ = node:range()
  local old_lines = vim.api.nvim_buf_get_lines(buf, end_, end_, true)
  local lines = {}
  for _, line in ipairs(new_lines) do
    table.insert(lines, line)
  end
  for _, line in ipairs(old_lines) do
    table.insert(lines, line)
  end
  vim.api.nvim_buf_set_lines(buf, end_, end_, true, lines)
end

local update_equals = function(class_node, fields)
  local class_body = class_node:field("body")[1]

  local buf = vim.api.nvim_get_current_buf()
  local method_signature_index_of_equals = nil

  for i = 0, class_body:child_count() - 1, 1 do
    local child = class_body:child(i)

    if child:type() == "method_signature" then
      local binary_operator = find_children_by_type(child:child(0), "binary_operator")[1]
      if binary_operator == nil then goto continue end
      local operator_name = get_node_contents(binary_operator)
      if operator_name == "==" then
        method_signature_index_of_equals = i
      end
    end
    ::continue::
  end

  local generated = generate_equals_lines(find_class_name(class_node), fields)
  if method_signature_index_of_equals ~= nil then
    if class_body:child(method_signature_index_of_equals - 1):type() ~= "marker_annotation" then
      prepend_nodes_last_line_with_lines(class_body:child(method_signature_index_of_equals), generated.marker_annotation)
    end
    local function_body = class_body:child(method_signature_index_of_equals + 1)
    local sl, sc, el, ec = function_body:range()
    vim.api.nvim_buf_set_text(buf, sl, sc, el, ec, generated.function_body)
  else
    prepend_nodes_last_line_with_lines(class_node, generated.marker_annotation)
    prepend_nodes_last_line_with_lines(class_node, generated.method_signature)
    prepend_nodes_last_line_with_lines(class_node, generated.function_body)
  end
end

local update_hash_code = function(class_node, fields)
  local class_body = class_node:field("body")[1]

  local buf = vim.api.nvim_get_current_buf()
  local method_signature_index_of_hash_code = nil

  for i = 0, class_body:child_count() - 1, 1 do
    local child = class_body:child(i)

    if child:type() == "method_signature" then
      local name = child:child(0):field("name")[1]
      if name == nil then goto continue end
      local method_name = get_node_contents(name)
      if method_name == "hashCode" then
        method_signature_index_of_hash_code = i
      end
    end
    ::continue::
  end

  local generated = generate_hash_code_lines(fields)
  if method_signature_index_of_hash_code ~= nil then
    if class_body:child(method_signature_index_of_hash_code - 1):type() ~= "marker_annotation" then
      prepend_nodes_last_line_with_lines(class_body:child(method_signature_index_of_hash_code), generated.marker_annotation)
    end
    local function_body = class_body:child(method_signature_index_of_hash_code + 1)
    local sl, sc, el, ec = function_body:range()
    vim.api.nvim_buf_set_text(buf, sl, sc, el, ec, generated.function_body)
  else
    prepend_nodes_last_line_with_lines(class_node, generated.marker_annotation)
    prepend_nodes_last_line_with_lines(class_node, generated.method_signature)
    prepend_nodes_last_line_with_lines(class_node, generated.function_body)
  end
end

local update_to_string = function(class_node, fields)
  local class_body = class_node:field("body")[1]

  local buf = vim.api.nvim_get_current_buf()
  local method_signature_index_of_to_string = nil

  for i = 0, class_body:child_count() - 1, 1 do
    local child = class_body:child(i)

    if child:type() == "method_signature" then
      local name = child:child(0):field("name")[1]
      if name == nil then goto continue end
      local method_name = get_node_contents(name)
      if method_name == "toString" then
        method_signature_index_of_to_string = i
      end
    end
    ::continue::
  end


  local generated = generate_to_string_lines(find_class_name(class_node), fields)
  if method_signature_index_of_to_string ~= nil then
    if class_body:child(method_signature_index_of_to_string - 1):type() ~= "marker_annotation" then
      prepend_nodes_last_line_with_lines(class_body:child(method_signature_index_of_to_string), generated.marker_annotation)
    end
    local function_body = class_body:child(method_signature_index_of_to_string + 1)
    local sl, sc, el, ec = function_body:range()
    vim.api.nvim_buf_set_text(buf, sl, sc, el, ec, generated.function_body)
  else
    prepend_nodes_last_line_with_lines(class_node, generated.marker_annotation)
    prepend_nodes_last_line_with_lines(class_node, generated.method_signature)
    prepend_nodes_last_line_with_lines(class_node, generated.function_body)
  end

end

local update_generated_methods_of_data_class = function(class_node, fields)
  update_equals(class_node, fields)
  update_hash_code(class_node, fields)
  update_to_string(class_node, fields)
end


M.generate = function()
  local node = find_data_class_node()
  local fields = find_fields_of_data_class(node)
  update_generated_methods_of_data_class(node, fields)
  vim.lsp.buf.formatting({})
end

return M
