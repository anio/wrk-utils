--
-- Using HTTP pipelining to perform screaming fast tests using attack payloads
-- Useful to test WAF
--

require("stats")

local PIPELINE_REQ_NUM = 64

local file_long = 15650
local file_name = 'attack-payloads.lst'

math.randomseed(os.time())

local req

-- you need to run init, setup and done functions if you want to override them
stats_init = init

function init(args)

    stats_init(args)

    local r = {}

    for i=1, PIPELINE_REQ_NUM do

        local payload       = ''
        local line_number   = math.random(1, file_long)
        local random_number = math.random(100000000, 999999999)

        local count = 1
        for line in io.lines(file_name) do
            count = count + 1
            if count == line_number then
                payload = line
            end
        end

        local method        = 'POST'
        local path          = "/?i" .. random_number
        local headers       = {}
        local body          = 'id=' .. payload

        r[i] = wrk.format(method, path, headers, body)

    end

    req = table.concat(r)

end


request = function()
    return req
end

response = function(status, headers, body)
    response_logger(status, headers)
end
