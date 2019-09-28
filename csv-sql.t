local c = terralib.includec("stdio.h")
local std = terralib.includec("stdlib.h")

local comma = string.byte(",")
local new_line = string.byte("\n")

local terra next_comma_pos( buffer_ref : rawstring )
    var pos = 0
    while @(buffer_ref + pos) ~= comma 
          and @(buffer_ref + pos) ~= new_line
          and @(buffer_ref + pos) ~= 0
          and pos < 1024 do
--        c.printf("c(%c) ", @(buffer_ref + pos))
        pos = pos + 1
    end
--    c.printf("r%d ", pos)
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
            target = "project",
            K.field,
            K.scope
        },
        function(v, e)
            local end_pos = symbol(uint64, "end_pos")
            return quote
                var [end_pos] = next_comma_pos([v.scope.buffer] + [v.scope.pos] + 1)
--                @([v.scope.buffer] + [v.scope.pos] + end_pos + 1) = [string.byte("_")]
--                c.printf("%s\n", [ v.field.name ])
                c.printf("[%.*s]", [end_pos], [v.scope.buffer] + [v.scope.pos] + 1 )
                [v.scope.pos] = [v.scope.pos] + [end_pos] + 1
            end
        end
    }

    stencil.rule{
        {
            target = "record",
            K.request,
            K.scope
        },
        function(v, e)
            local var_pos = symbol(uint64, "pos")

            local projections = {
                quote
                    var [var_pos] = 0
                end
            }
            for _, field in ipairs(v.request.scheme.fields) do
                local scheme_field = m.match({ name = field.name }, v.request.query.select)
                if scheme_field then
                    table.insert(projections, stencil.apply{
                                target = "project",
                                field = scheme_field,
                                scope = {
                                    buffer = v.scope.buffer,
                                    pos = var_pos
                                }
                            })
                else
                    table.insert(projections, quote
                            [var_pos] = [var_pos] + next_comma_pos([v.scope.buffer] + [var_pos] + 1)
                            [var_pos] = [var_pos] + 1
--                            c.printf("p%d ", [var_pos])
                            end)
                end
            end
            table.insert(projections, quote c.printf("\n") end)

            return projections
--            return quote
--                c.printf("> %s", [v.scope.buffer])
--            end
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
--            local new_line = string.byte("\n")
            return quote
                var [v.scope.buffer] : rawstring = nil
                var [v.scope.buffer_size] : uint64 = 0

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

--                    return buffer
--                    var line = readline(fp)
                    [ stencil.apply{
                        target = "record",
                        request = v.request,
                        scope= v.scope } ]
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
                    } } ]
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