--
-- @name wrk stats
-- @author Ali Norouzi
-- @url  https://github.com/anio/wrk-utils
--


local __debug__             = os.getenv('WRK_DEBUG') == 'true'
-- set it to true to have live stats in log files
local __livestats__         = os.getenv('WRK_LIVESTATS') == 'true'
local __logheaders__        = os.getenv('WRK_LOGHEADERS') == 'true'

local livestats_interval    = 5 -- seconds
local livestats_filename    = ''
local livestats_file        = nil -- io object
local headers_logfile       = nil -- io object


-- Optional Slack webhook to have results there
local slack_webhook         = os.getenv('SLACK_WEBHOOK')
if __debug__ then
    slack_webhook           = os.getenv('SLACK_WEBHOOK_DBG')
end


threads                     = {}
thread_counter              = 1000
thread_id                   = nil
counter                     = {requests = 0, responses = 0}
status_counter              = {}

ip                          = nil
url                         = nil


start_time                  = nil -- timestamp
log_tracker                 = {}


local function get_ip()
    return os.getenv('NODE_IP')
end


-- Send result to Slack using curl
local function alert(message)

    if not slack_webhook then
        print("Slack webhook is not provided!")
        return
    end

    local mode = ''

    if __debug__ then
        mode = ' (debug mode)'
    end

    message = string.format(
        [[%s%s:\n```%s```\n%s]],
        ip, mode,
        message, os.date()
    )

    local cmd = string.format(
        [[curl -s %s -d '{"text": "%s"}']],
        slack_webhook, message
    )

    local handle = io.popen(cmd)
    local result = handle:read("*a")
    handle:close()

    if __debug__ then
        print(cmd, result)
    end

    return result
end


local function get_ts()
    return os.time(os.date("!*t"))
end


local function get_time_diff()
    return (get_ts() - start_time)
end


local function is_time_to_log(_type)
    local diff = get_time_diff()
    local status = (diff % livestats_interval) == 0
    local key = string.format("%d-%s", diff, _type)

    if log_tracker[key] then
        return false
    end

    if status then
        log_tracker[key] = true
    end

    return status
end


function request_logger(active)
    counter.requests = counter.requests + 1

    if __livestats__ and active and is_time_to_log("request") then
        local output = string.format(
            '{"event": "request", "node": "%s", "thread_id": %d, "count": %d}',
            ip, thread_id, counter.requests)

        livestats_file = io.open(livestats_filename, "a+")
        livestats_file:write(output .. '\n')
        livestats_file:close()
    end

end


function response_logger(status, headers)

    if __logheaders__ then
        if status >= 500 or (status >= 300 and status < 400) then
            headers_logfile:write(
                string.format('status: %d, node: %s\n',
                    status, ip)
            )
            for hn, hv in pairs(headers) do
                headers_logfile:write(string.format('%s: %s',
                    hn, hv) .. '\n')
            end
            headers_logfile:write('\n\n')
        end
    end

    counter.responses = counter.responses + 1

    if not status_counter[status] then
        status_counter[status] = 1
    else
        status_counter[status] = status_counter[status] + 1
    end

    if __livestats__ and is_time_to_log("response") then

        local output = string.format(
            [["event": "response", "node": "%s", "thread_id": %d, "count": %d]],
            ip, thread_id, counter.responses
        )
        
        local status_codes = {}
        for key, value in pairs(status_counter) do
            table.insert(status_codes, string.format('"%d": %d', key, value))
            if key >= 500 then
                print(string.format("%d Errors count: %d -- node: %s",
                                    key, status_counter[key], ip)
                )
            end

        end
        output = string.format(
            [[{%s, "status": {%s}}]],
            output, table.concat(status_codes, ", ")
        )

        livestats_file = io.open(livestats_filename, "a+")
        livestats_file:write(output .. '\n')
        livestats_file:close()
    end
end


----------------- Request handler
function request()
    request_logger(false)
    return wrk.request()
end


----------------- Response handler
function response(status, headers, body)
    response_logger(status, headers)
end


----------------- Summary on exit
function done(summary, latency, requests)

    print(string.format([[%s Done!]], ip))

    local duration = (summary.duration / 1000000)
    local total_requests = 0
    local total_responses = 0
    local total_by_status = {}

    for i, thread in ipairs(threads) do
        if not url then
            url = thread:get("url")
        end

        local counter = thread:get("counter")
        if counter.requests then
            total_requests = total_requests + counter.requests
        end

        if counter.responses then
            total_responses = total_responses + counter.responses
        end

        local status_counter = thread:get("status_counter")
        for key, value in pairs(status_counter) do
            if not total_by_status[key] then
                total_by_status[key] = 0
            end

            total_by_status[key] = total_by_status[key] + value
        end

    end
    local output = string.format(
        [["event": "done", "start_time": %d, "node": "%s", ]] ..
        [["target_url": "%s", ]] ..
        [["total_completed_requests": %d, "total_sent_requests": %d, ]] ..
        [["total_timeouts": %d, ]] ..
        [["connect_error": %d, ]] ..
        [["socket_status_error": %d, ]] ..
        [["read_error": %d, ]] ..
        [["write_error": %d, ]] ..
        [["duration": "%s", ]] ..
        [["rps": %4.2f, ]] ..
        [["recv_bytes": "%04.2fmb"]],
        start_time,
        ip,
        url,
        summary.requests,
        total_requests,
        summary["errors"]["timeout"],
        summary["errors"]["connect"],
        summary["errors"]["status"],
        summary["errors"]["read"],
        summary["errors"]["write"],
        duration,
        summary.requests / duration,
        summary["bytes"] / (1024 * 1024)
    )

    local status_codes = {}
    for key, value in pairs(total_by_status) do
        table.insert(status_codes, string.format('"%d": %d', key, value))
    end
    output = string.format(
        [[{%s, "status": {%s}}]],
        output,
        table.concat(status_codes, ", ")
    )

    if __debug__ then
        print(output)
    end

    local log = io.open(string.format("wrk-done.log", start_time), "a")
    log:write(output .. '\n')
    log.close()

    local message = string.format("%q", output):sub(2, -2)
    alert(message)
end


----------------- Setup threads
function setup(thread)

    table.insert(threads, thread)

    if not ip then
        ip = get_ip()
    end

    if not start_time then
        start_time = get_ts()
    end

    thread:set("thread_id", thread_counter)
    thread:set("ip", ip)
    thread:set("start_time", start_time)
    thread_counter = thread_counter + 1
end


function init(args)
    url = args[0]

    if __livestats__ and not livestats_file then
        livestats_filename = string.format("wrk-live-%d.log", start_time)
        livestats_file = io.open(livestats_filename, "w")
        livestats_file:close()
    end

    if __logheaders__ and not headers_logfile then
        headers_logfile = io.open("wrk-headers.log", "w")
    end
end

