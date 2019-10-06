local mm = require'mm'

local stencil = require("stencil")()
local m = require("match")

local N = m.namespace()
local K = N.keys
local V = N.vars

local function ref(key, parent)     -- {{{
    local reference = {
        ref = key,
        parent = parent
    }
    local mt = {
        __index = function(t, k)
            t.subkey = k
            t.subref = ref(k, t)

            return t.subref
        end
    }
    setmetatable(reference, mt)

    return reference
end

local function collect_references(terra_expr)
    local references = {}

    local env = {}
    local mt = { 
        __index = function(t, k)
            if k == "terra" then return terralib end
            if k == "_G" then return _G end
            if k == "getfenv" then return getfenv end
            local new_ref = ref(k)
            references[k] = new_ref
            return new_ref
        end
    }
    setmetatable(env, mt)

    local terra_ast = terra_expr(env)

    return references, terra_ast
end

-- }}}

stencil.rule{
    { target = "collect_fields", K.refs, K.request },
    function(v, e)
    end
}

stencil.rule{
    { 
        query = { K.where },
        K.parameters,
        K.schema,
        K.scope,
        K.env
    },
    function(v, e)
          local refs, ast = collect_references(v.where)

          mm(ast)
          print("refs: ---------------------------------------------")
          mm(refs)
--        local x = terra()
--            [where_expansion] 
--        end
--        x()
    end
}

-- NOTE: this goes with a general source iterator???
--stencil.rule{
--   { source = is_file },
--   function(v, e)
--   end
--}

return stencil.apply
