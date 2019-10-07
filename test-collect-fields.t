local csv_sql = require("sql-push-traversal")
--local mm = require'mm'

local source = {
    type = "csv",
    file = "zillow.csv"
}

local schema = {
    type = "csv",
    fields = {
        { name = "Index", type = "uint32" },
        { name = "SqFt", type = "uint32" },
        { name = "Beds", type = "uint32" },
        { name = "Baths", type = "float" },
        { name = "Zip", type = "uint32" },
        { name = "Year", type = "uint32" },
        { name = "Price", type = "uint32" },
    }
}

local c = terralib.includec("stdio.h")
local callback = terra( zip : uint32, sqft : uint32)
    c.printf("row: %d, %d\n", zip, sqft)
end

import "sql-language"

local query = select Zip, SqFt from source where Beds <= 3

--mm(query)

local request = {
    parameters = {},    -- argvs command-line parameters
    source = source,
    schema = schema,
    query = query,
    callback = callback
}

local q = csv_sql(request)()

--local terra process_record(buffer : rawstring)
--    [ 
--        csv_sql(request, { buffer = buffer }){
--            target = "record",
--            request = request
--        }
--    ]
--end

print("--------------------------------------------------------------")
q:printpretty()
print("--------------------------------------------------------------")
terralib.saveobj("test-collect-fields", { main = q })

q(5, nil)


