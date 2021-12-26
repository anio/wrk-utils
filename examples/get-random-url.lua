
require("stats")

request = function()

  request_logger(false)

  wrk.headers["User-Agent"]         = "Mozilla/5.0 (X11; Linux x86_64; rv:70.0)" ..
                                      " Gecko/20100101 Firefox/70.0"

  wrk.headers["Accept"]             = "text/html,application/xhtml+xml," ..
                                      "application/xml;q=0.9,*/*;q=0.8"

  wrk.headers["Accept-Language"]    = "en-US,en;q=0.5"
  wrk.headers["Connection"]         = "Keep-Alive"
  wrk.headers["Accept-Encoding"]    = "gzip, deflate"
  wrk.headers["Referer"]            = "https://www.example.com/"
  wrk.headers["Host"]               = "www.example.com"

  local random_id = math.random(100000, 900000)
  local path = "/p-" .. random_id

  return wrk.format("GET", path)

end


response = function(status, header, body)
    response_logger(status)
end
