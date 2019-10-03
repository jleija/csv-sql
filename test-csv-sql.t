local csv_sql = require("csv-sql")()
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

local query = {
    select = {
        { name = "Price" },
        { name = "Year" },
--        { name = "Baths" },
    }
}

local c = terralib.includec("stdio.h")
local callback = terra( year : uint32, price : uint32)
    c.printf("row: %d, %d\n", year, price)
end

local request = {
    source = source,
    schema = schema,
    query = query,
    callback = callback
}

local q = csv_sql(request)

--mm(q)
--print(q)
print("--------------------------------------------------------------")
q:printpretty()
print("--------------------------------------------------------------")

--terralib.saveobj("test-csv-sql.bc", { main = q })
terralib.saveobj("test-csv-sql", { main = q })

q(5, nil)


