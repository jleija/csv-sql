local c = terralib.includec("stdio.h")
local std = terralib.includec("stdlib.h")

local terra_type = {
    uint32 = uint32,
    float = float
}

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

local function new_csv_sql(config)
    config = config or {}
    config.new_line = string.byte(config.new_line or "\n")

    local stencil = require("stencil")()
    local m = require("match")

    local N = m.namespace()
    local K = N.keys
    local V = N.vars

    stencil.rule{
        {
            target = "field_getter",
            field = { type = "uint32" },
            K.scope
        },
        function(v, e)
            return quote
                @([v.scope.buffer] + [v.scope.length]) = 0
                var [v.scope.field_var] = std.atoi([v.scope.buffer])
                c.printf("[n%u]", v.scope.field_var)
            end
        end
    }

    stencil.rule{
        {
            target = "field_getter",
            field = { type = "float" },
            K.scope
        },
        function(v, e)
            return quote
                @([v.scope.buffer] + [v.scope.length]) = 0
                var [v.scope.field_var] = std.atof([v.scope.buffer])
                c.printf("[f%f]", [v.scope.field_var])
            end
        end
    }

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
            target = "record",
            K.request,
            K.scope,
        },
        function(v, e)
            local var_pos = symbol(uint64, "pos")
            local var_length = symbol(uint64, "length")
            local var_field_buffer = symbol(rawstring, "field_buffer")

            local projections = {
                quote
                    var [var_pos] = 0
                    var [var_length] = 0
                    var [var_field_buffer] = nil
                end
            }
            local field_vars = {}
            for _, field in ipairs(v.request.schema.fields) do
                local schema_field = m.match({ name = field.name }, v.request.query.select)
                table.insert(projections, quote
                    [var_length] = next_comma_pos([v.scope.buffer] + [var_pos] + 1)
                    [var_field_buffer] = [v.scope.buffer] + [var_pos] + 1
                end)


                if schema_field then
                    local var_field = symbol(terra_type[field.type], schema_field.name)
                    field_vars[field.name] = var_field
                    table.insert(projections, stencil.apply{
                                target = "field_getter",
                                field = field,
                                scope = {
                                    buffer = var_field_buffer,
                                    length = var_length,
                                    field_var = var_field
                                }
                            })
                end
                table.insert(projections, quote
                    [var_pos] = [var_pos] + [var_length] + 1
                end)
            end
            local fields = {}
            for _, field in ipairs(v.request.query.select) do
                table.insert(fields, `[field_vars[field.name]])
            end
            table.insert(projections, quote [v.request.callback]([fields]) end)
--            table.insert(projections, quote c.printf("\n") end)

            return projections
        end
    }

    stencil.rule{
        { 
            target = "loop", 
            request = V.request{
                   source = { 
                       K.file
                   } 
            },
            K.scope
        },
        function(v, e)
            return quote
                var [v.scope.buffer] = nil
                var [v.scope.buffer_size] = 0

                var fp = c.fopen([v.file], "r")

                -- read headers
                var read_bytes = c.getdelim(
                                    &[v.scope.buffer], 
                                    &[v.scope.buffer_size],
                                    config.new_line, 
                                    fp)

                while c.feof(fp) == 0 do
                    var read_bytes = c.getdelim(
                                        &[v.scope.buffer], 
                                        &[v.scope.buffer_size],
                                        config.new_line, 
                                        fp)
                    if read_bytes == -1 then std.exit(2) end

                    [ stencil.apply{
                        target = "record",
                        request = v.request,
                        scope= v.scope
                    } ]
                end
                c.fclose(fp)
            end
        end
    }

    stencil.rule{
        { target = "program", K.request },
        function(v)
            local var_buffer = symbol(rawstring, "buffer")
            local var_buffer_size = symbol(uint64, "buffer_size")
            return terra(argc : int, argv : &rawstring)
--                c.printf("args# %d\n", argc)
--                c.printf("argv[0]=[%s]\n", argv[0])
--                c.printf("argv[1]=[%s]\n", argv[1])
--                c.printf("argv[2]=[%s]\n", argv[2])
                [ stencil.apply{
                    target = "loop",
                    request = v.request,
                    scope = {
                        buffer = var_buffer,
                        buffer_size = var_buffer_size
                    }
                } ]
            end
        end
    }

    local function csv_sql(request)

        local program = stencil.apply{ 
                            target = "program",
                            request = request}
        return program
    end

    return csv_sql
end

return new_csv_sql
