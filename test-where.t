local sql_traversal = require("sql-push-traversal")
local mm = require'mm'

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
local callback = terra( year : uint32, price : uint32)
    c.printf("row: %d, %d\n", year, price)
end

import "sql-language"

local query = select Price, Year from source where Year.x < 2000 and Price > 34.5 or just_x

mm(query)

local request = {
    parameters = {},    -- argvs command-line parameters
    env = {},
    scope = {},
    source = source,
    schema = schema,
    query = query,
    callback = callback
}

local q = sql_traversal(request)

--print("--------------------------------------------------------------")
--q:printpretty()
--print("--------------------------------------------------------------")

--q(5, nil)


