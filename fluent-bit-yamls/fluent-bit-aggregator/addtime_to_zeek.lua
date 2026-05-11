function add_time(tag, timestamp, record)
    -- 원본 ts 보존
    local ts = record["ts"]

    -- Zeek JSON의 ts가 숫자라고 가정
    if ts ~= nil then
        local sec = math.floor(ts)
        local frac = ts - sec
        local usec = math.floor(frac * 1000000)

        -- KST ISO8601
        record["event_datetime"] = os.date("%Y-%m-%dT%H:%M:%S", sec) ..
                                   string.format(".%06d+09:00", usec)

        -- 파티션/조회용 날짜
        record["event_date"] = os.date("%Y-%m-%d", sec)
    end

    -- 수집 시각(aggregator 도착 시각)
    record["ingest_datetime"] = os.date("%Y-%m-%dT%H:%M:%S+09:00")

    -- 태그 기준 메타
    if tag == "zeek.conn" then
        record["log_type"] = "conn"
    elseif tag == "zeek.http" then
        record["log_type"] = "http"
    elseif tag == "zeek.dns" then
        record["log_type"] = "dns"
    else
        record["log_type"] = "unknown"
    end

    return 1, timestamp, record
end