local c = terralib.includec("stdio.h")
local std = terralib.includec("stdlib.h")

--local mm = require'mm'

local m = require("match")

local N = m.namespace()
local K = N.keys
local V = N.vars

local function resolve_expr(terra_expr, references)
    local env = {}
    local mt = { 
        __index = function(t, k)
            if k == "terra" then return terralib end
            if k == "_G" then return _G end
            if k == "getfenv" then return getfenv end
            if references[k] then return references[k] end
        end
    }
    setmetatable(env, mt)

    local terra_ast = terra_expr(env)

    return terra_ast
end

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

local function collect_references(terra_expr, references)
    references = references or {}

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

local function project_references(query, refs)
    refs = refs or {}
    for _, field in ipairs(query.project) do
        if field.name then
            refs[field.name] = { ref = field.name }
        elseif field.expr then
            collect_references(field.expr, refs)
        else
            assert(false, "either name or expr")
        end
    end
    return refs
end

local function where_references(query, refs)
    refs = refs or {}
    if query.where then
        return collect_references(query.where, refs)
    end
    return refs
end

local function all_query_references(query)
    local all_refs = {}
    project_references(query, all_refs)
    return where_references(query, all_refs)
end

local function minimum_referenced_schema(refs, schema)
    local minimum_schema = {}
    for k,v in pairs(schema) do
        minimum_schema[k] = v
    end
    minimum_schema.fields = {}
    for i=#schema.fields,1,-1 do
        if refs[schema.fields[i].name] then
            for j=1,i do
                table.insert(minimum_schema.fields, schema.fields[j])
            end
            break
        end
    end
    return minimum_schema
end

-- }}}

local comma = string.byte(",")
local new_line = string.byte("\n")

local terra next_comma_pos( buffer_ref : rawstring )
    var pos = 0
    while @(buffer_ref + pos) ~= comma 
          and @(buffer_ref + pos) ~= new_line
          and @(buffer_ref + pos) ~= 0
          and pos < 1024 do
        pos = pos + 1
    end
    return pos
end

local function row_body(request, config)
    config = config or {}
    config.new_line = string.byte(config.new_line or "\n")

    local stencil = require("stencil")()

    local scope = {}
    local field_index = 1

    stencil.rule{
        {
            target = "field_getter",
            field = { type = "uint32" }
        },
        function(v, e)
            scope[e.field.name] = symbol(uint32, e.field.name)
            return quote
                @([scope[e.field.name.."_end"]]) = 0
                var [scope[e.field.name]] = std.atoi([scope[e.field.name.."_begin"]])
--                c.printf("[%.*s]", [scope[e.field.name.."_end"]] - 
--                        [scope[e.field.name.."_begin"]], [scope[e.field.name.."_begin"]])
            end
        end
    }

--    stencil.rule{
--        {
--            target = "field_getter",
--            field = { type = "float" },
--            K.scope
--        },
--        function(v, e)
--            return quote
--                @([v.scope.buffer] + [v.scope.length]) = 0
--                var [v.scope.field_var] = std.atof([v.scope.buffer])
--                c.printf("[f%f]", [v.scope.field_var])
--            end
--        end
--    }

    stencil.rule{
        {
            target = "field_getter",
            K.field,
            K.scope
        },
        function(v, e)
            return quote
                c.printf("?%.*s?", [v.scope.length], [v.scope.buffer])
            end
        end
    }

    stencil.rule{
        { 
            target = "locate_field", 
            schema_field = { name = V.field_name, K.type },
            K.projected_field
        },
        function(v, e)
            local var_begin_name = v.field_name .. "_begin"
            local var_end_name = v.field_name .. "_end"
            local var_begin = symbol(rawstring, var_begin_name)
            local var_end = symbol(rawstring, var_end_name)
            scope[var_begin_name] = var_begin
            scope[var_end_name] = var_end
            return quote
                var [var_begin] = [scope.buffer]
                var [var_end] = [scope.buffer] + next_comma_pos([scope.buffer])
                [scope.buffer] = [var_end] + 1
            end
        end
    }

    stencil.rule{
        { 
            target = "locate_field", 
            schema_field = { name = V.field_name, K.type }
        },
        function(v, e)
            return quote
                [scope.buffer] = [scope.buffer] + next_comma_pos([scope.buffer]) + 1
            end
        end
    }

    stencil.rule{
        { 
            target = "locate_field", 
        },
        function(v, e)
            print("unmatched rule locate_field")
--            mm(e)
        end
    }


    local function locate_fields(refs, sub_schema)
        local locate_fields = {}
        while field_index <= #sub_schema.fields do
            local field = sub_schema.fields[field_index]
--        for i, field in ipairs(sub_schema.fields) do
            local field_quote = stencil.apply{
                                    target = "locate_field",
                                    refs = request.query.project,
                                    schema_field = field,
                                    projected_field = m.match(
                                            {ref=field.name}, 
                                            refs),
                                }
            table.insert(locate_fields, field_quote)
            field_index = field_index + 1
        end
        return locate_fields
    end

    local function get_fields(refs, schema)
        local field_getters = {}
        local projection_vars = {}
        for _, field in ipairs(schema.fields) do
            if refs[field.name] then
                table.insert(field_getters, stencil.apply{
                                                target = "field_getter",
                                                field = field
                                                })
                table.insert(projection_vars, scope[field.name])
            end
        end
        return field_getters, projection_vars
    end

    stencil.rule{
        {
            target = "record",
            request = { query = { K.where } } 
        },
        function(v, e)
            local all_refs = all_query_references(e.request.query)
            local where_refs = where_references(e.request.query)
            local where_schema = minimum_referenced_schema(where_refs, request.schema)
            local locate_fields_til_where = locate_fields(all_refs, where_schema)
            return quote
                [ locate_fields_til_where ]
                [ get_fields(where_refs, where_schema) ]
                if [ resolve_expr(v.where, scope) ] then
                    [ stencil.apply{ target = "project", request = e.request } ]
                end
            end
        end
    }

    stencil.rule{
        {
            target = "record",
            request = { query = { where = m.missing } } 
        },
        function(v, e)
            return stencil.apply{ target = "project", request = e.request }
        end
    }

    stencil.rule{
        {
            target = "project",
            request = { query = { K.project } } 
        },
        function(v, e)
            local all_refs = all_query_references(e.request.query)
            local project_refs = project_references(e.request.query)
            local project_schema = minimum_referenced_schema(project_refs, request.schema)
            local locate_fields_til_project = locate_fields(all_refs, project_schema)
            local field_getters, projection_vars = get_fields(project_refs, project_schema)
            return quote
                [ locate_fields_til_project ]
                [ field_getters ]
                [e.request.callback]([projection_vars])
            end
        end
    }

    stencil.rule{
        { 
            target = "loop", 
            request = V.request{
                   source = { 
                       K.file
                   } 
            }
        },
        function(v, e)
            return quote
                var [scope.buffer] = nil
                var [scope.buffer_size] = 0

                var fp = c.fopen([v.file], "r")

                -- read headers
                var read_bytes = c.getdelim(
                                    &[scope.buffer], 
                                    &[scope.buffer_size],
                                    config.new_line, 
                                    fp)

                while c.feof(fp) == 0 do
                    var read_bytes = c.getdelim(
                                        &[scope.buffer], 
                                        &[scope.buffer_size],
                                        config.new_line, 
                                        fp)
                    if read_bytes == -1 then std.exit(2) end

                    [ stencil.apply{
                        target = "record",
                        request = v.request
                    } ]
                end
                c.fclose(fp)
            end
        end
    }

    stencil.rule{
        { target = "program", K.request },
        function(v)
            scope.buffer = symbol(rawstring, "buffer")
            scope.buffer_size = symbol(uint64, "buffer_size")

            return terra(argc : int, argv : &rawstring)
--                c.printf("args# %d\n", argc)
--                c.printf("argv[0]=[%s]\n", argv[0])
--                c.printf("argv[1]=[%s]\n", argv[1])
--                c.printf("argv[2]=[%s]\n", argv[2])
                [ stencil.apply{
                    target = "loop",
                    request = v.request
                } ]
            end
        end
    }

    local function csv_sql()

        local program = stencil.apply{ 
                            target = "program",
                            request = request}
        return program
    end

    return csv_sql
end

return row_body
