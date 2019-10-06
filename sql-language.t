local expression = function(self,lex)
  lex:expect("select") --first token should be "sum"
  local fields = {}
  if not lex:matches("from") then
    repeat
      local field_name = lex:expect(lex.name).value
      local field = {
          name = field_name
      }
      table.insert(fields, field)
    until not lex:nextif(",")
  end

  local source_fn
  if lex:matches("from") then
      lex:next()
      source_fn = lex:luaexpr()
  end

  local where_expr
  if lex:matches("where") then
    lex:next()
    where_expr = lex:terraexpr()
  end

  local callback
  local callback_parameters = {}
  if lex:matches("call") then
      lex:next()
      callback = lex:expect(lex.name).value
      if lex:matches("(") then
        lex:next()
        if lex:matches(lex.name) then
            repeat
                local param = lex:expect(lex.name).value
                table.insert(callback_parameters, param)
            until not lex:nextif(",")
        end
        lex:expect(")")
      end
  end

  local limit_fn
  if lex:matches("limit") then
      lex:next()
      limit_fn = lex:luaexpr()
  end

  return function(environment_function)
    local env = environment_function()

    local env_mt = getmetatable(env)
    local mt = {
        __index = function(t, k)
            if k == "terra" then return terralib end
            if k == "_G" then return _G end
            if k == "getfenv" then return getfenv end
            if rawget(env, k) then
                return rawget(env, k)
            end
        end
    }
    setmetatable(env, mt)

    local source = source_fn and source_fn(env) or "-"
    local limit = limit_fn and limit_fn(env) or false

    return {
        project = fields,
        source = source,
        where = where_expr,
        limit = limit,
        env = env,
        dispatch = {
            callback = callback,
            parameters = callback_parameters
        }
    }
  end
end

return {
  name = "sql",
  entrypoints = {"select"},
  keywords = {"select", "from", "where", "call", "limit"},
  expression = expression
}

