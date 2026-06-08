-- Use participant login entry to avoid outage landing page
local url="https://www.equateplus.com/EquatePlusParticipant2/?login"

function rnd()
  return math.random(10000000,99999999)
end

local baseurl=""
local dcHost = "https://www.equateplus.com"
local reportOnce
local Version=4.00
local CSRF_TOKEN=nil
local CSRF2_TOKEN=nil
local connection
local debugging=true
local nosecrets=true
local cummulate=false
local html
local cId="eqp."..rnd()
local session_id
local QR  -- defined at end of file

-- Generates the challenge image from the raw API response.
-- raw: either a URL (string starting with http) or base64-encoded PNG data.
-- To replace QR generation with a MoneyMoney API call: change only this function.
local function generate_challenge_image(raw)
  if string.match(raw, "^https?://") then
    lprint("QR: URL length=" .. #raw .. " preview=" .. string.sub(raw, 1, 60))
    return MM.imageResize(QR.encode_fit(raw, 240), 240, 240)
  else
    return MM.imageResize(MM.base64decode(raw), 240, 240)
  end
end

-- State for SMS-OTP authentication flow
local awaitingOtp=false
local otpPageHtml=nil

function startsWith(String,Start)
  return string.sub(String,1,string.len(Start))==Start
end

function split(inputstr, sep)
  if sep == nil then
     sep = "%s"
  end
  local t={}
  for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
     table.insert(t, str)
  end
  return t
end

function connectWithCSRF(method, url, postContent, postContentType, headers)
  -- Normalize URL to selected datacenter host
  local function normalize(u)
    local host = dcHost or "https://www.equateplus.com"
    u = u or ""
    if string.match(u, "^https?://") then
      -- absolute URL: replace host only
      local path = string.match(u, "^https?://[^/]+(.*)$") or "/"
      return host .. path
    elseif string.sub(u, 1, 1) == "?" then
      -- query-relative (e.g. "?login" from form action="?login"):
      -- resolve against /EquatePlusParticipant2/ so we get the correct full path
      return host .. "/EquatePlusParticipant2/" .. u
    else
      if string.sub(u, 1, 1) ~= "/" then u = "/" .. u end
      return host .. u
    end
  end

  local content
  local respHeaders

  -- Support Request object from HTML:submit()
  if type(method) ~= 'string' then
    local req = method
    local u = normalize(req and req.url or url or "/")
    local m = (req and req.method) or 'GET'
    local body = (req and (req.postContent or req.body)) or postContent or ""
    local ct = (req and (req.postContentType or req.mimeType)) or postContentType or "application/x-www-form-urlencoded"
    local h = {}
    -- Start from request headers if present
    if req and req.headers then
      for k, v in pairs(req.headers) do h[k] = v end
    end
    -- Merge explicit headers
    if headers then
      for k, v in pairs(headers) do h[k] = v end
    end
    h["Accept"] = h["Accept"] or "*/*"
    -- For login orchestration endpoints, request JSON and mark XHR
    if string.find(u, "?login") then
      h["Accept"] = "application/json, text/plain, */*"
      h["X-Requested-With"] = h["X-Requested-With"] or "XMLHttpRequest"
      if h["Referer"] == nil then
        h["Referer"] = (dcHost or "https://www.equateplus.com") .. "/eqlogin/"
      end
    end
    if string.find(u, "/EquatePlusParticipant2/services/") and h["Referer"] == nil then
      h["Referer"] = (dcHost or "https://www.equateplus.com") .. "/EquatePlusParticipant2/"
    end
    if CSRF_TOKEN ~= nil then h['csrfpId']=CSRF_TOKEN else if debugging then print("without CSRF_TOKEN") end end
    if CSRF2_TOKEN ~= nil then h["EQUATE-CSRF2-TOKEN-PARTICIPANT2"]=CSRF2_TOKEN end

    content, charset, mimeType, filename, respHeaders = connection:request(m, u, body, ct, h)
  else
    -- Classic call signature
    url = normalize(url)
    postContentType=postContentType or "application/json"
    if headers == nil then headers={} end
    headers["Accept"] = headers["Accept"] or "*/*"
    -- For login orchestration endpoints, request JSON and mark XHR
    if string.find(url, "?login") then
      headers["Accept"] = "application/json, text/plain, */*"
      headers["X-Requested-With"] = headers["X-Requested-With"] or "XMLHttpRequest"
      if headers["Referer"] == nil then
        headers["Referer"] = (dcHost or "https://www.equateplus.com") .. "/eqlogin/"
      end
    end
    if string.find(url, "/EquatePlusParticipant2/services/") and headers["Referer"] == nil then
      headers["Referer"] = (dcHost or "https://www.equateplus.com") .. "/EquatePlusParticipant2/"
    end
    if CSRF_TOKEN ~= nil then headers['csrfpId']=CSRF_TOKEN else if debugging then print("without CSRF_TOKEN") end end
    if CSRF2_TOKEN ~= nil then headers["EQUATE-CSRF2-TOKEN-PARTICIPANT2"]=CSRF2_TOKEN end
    if method == 'POST' then
      if postContent == nil then postContent="" end
    end
    content, charset, mimeType, filename, respHeaders = connection:request(method, url, postContent, postContentType, headers)
  end
  -- Try to extract CSRF token from JSON and HTML patterns
  local csrfpIdTemp = string.match(content, '"csrfpId"%s*:%s*"([^"]+)"')
  if csrfpIdTemp == nil or csrfpIdTemp == '' then
    csrfpIdTemp = string.match(content, 'csrfRegisterAjax%(%s*"csrfpId"%s*,%s*"([^"]+)"')
  end
  if csrfpIdTemp == nil or csrfpIdTemp == '' then
    csrfpIdTemp = string.match(content, 'csrfModifyLinks%(%s*"csrfpId"%s*,%s*"([^"]+)"')
  end
  if csrfpIdTemp ~= nil and csrfpIdTemp ~= '' then
    CSRF_TOKEN=csrfpIdTemp
  end
  -- Try multiple patterns to extract CSRF2
  local csrf2Temp
  csrf2Temp = string.match(content, "['\"]equateCsrfToken2['\"]%s*:%s*['\"]([^'\"]+)['\"]")
  if csrf2Temp == nil or csrf2Temp == '' then
    csrf2Temp = string.match(content, "name=['\"]EQUATE%-CSRF2%-TOKEN%-PARTICIPANT2['\"]%s+value=['\"]([^'\"]+)['\"]")
  end
  if csrf2Temp ~= nil and csrf2Temp ~= '' then
    CSRF2_TOKEN = csrf2Temp
  end
  if debugging then
    local headersToLog = {}
    for k, v in pairs(respHeaders or {}) do
      local kl = string.lower(tostring(k))
      if nosecrets and (
        kl == "set-cookie" or kl == "cookie" or kl == "authorization" or
        kl == "equate-csrf2-token-participant2" or kl == "csrfpid" or
        kl == "x-csrf-token" or kl == "x-auth-token"
      ) then
        headersToLog[k] = "<redacted>"
      else
        headersToLog[k] = v
      end
    end
    tprint(headersToLog)
    -- lprint(content)
  end
  return content
end

WebBanking{
  version=Version,
  url=url,
  services={"EquatePlus"},
  description = "EquatePlus portfolio"
}


function SupportsBank (protocol, bankCode)
  return  protocol == ProtocolWebBanking and (
    bankCode == "EquatePlus" or
    bankCode == "EquatePlus SE" or
    bankCode == "EquatePlus (cumulative)" or
    bankCode == "EquatePlus SE (cumulative)"
  )
end

function lprint(text)
  repeat
    print("  ",string.sub(text,1,60))
    text=string.sub(text,61)
  until text == ''
end

function tprint (tbl, indent)
  if debugging then
    if not indent then indent = 3 end
    for k, v in pairs(tbl) do
      local formatting = string.rep(" ", indent) .. k .. ": "
      if type(v) == 'table' and indent < 9 then
        print(formatting .. "table")
        tprint(v,indent+3)
      elseif type(v) == 'string' then
        if nosecrets then
          print(formatting .. "string'<redacted>'")
        else
          print(formatting .. "string'"..v.."'")
        end
      else
        print(formatting .. type(v))
      end
    end
  end
end

function InitializeSession2 (protocol, bankCode, step, credentials, interactive)

  if step==1 then
    -- Login.
    baseurl=""
    debugging=false
    cummulate=true
    CSRF_TOKEN=nil
    CSRF2_TOKEN=nil
    connection = Connection()

    username=credentials[1]
    password=credentials[2]

    if string.sub(username,1,1) == '#' then
      print("Debugging, remove # char from username!")
      username=string.sub(username,2)
      debugging=true
    end

    if string.sub(username,1,1) == '#' then
      print("Debugging, remove # chars from username!")
      username=string.sub(username,2)
      nosecrets=true
    end

    -- Helper to detect presence of login form or username field
    local function hasLoginForm(doc)
      return (doc:xpath("//*[@id='loginForm']"):length() > 0) or (doc:xpath("//input[@name='isiwebuserid']"):length() > 0)
    end

    -- get login page (avoid outage page). Try primary + datacenter fallbacks.
    local function tryLoadLogin(u)
      return HTML(connectWithCSRF("GET", u))
    end

    dcHost = "https://www.equateplus.com"
    html = tryLoadLogin(url)
    if not hasLoginForm(html) then
      -- Outage screen or changed landing; attempt geo DCs
      local tried = {
        "https://www.emea.equateplus.com/EquatePlusParticipant2/?login",
        "https://www.na.equateplus.com/EquatePlusParticipant2/?login",
        "https://participant.tst.equateplus.com/EquatePlusParticipant2/?login" -- BT1 fallback (rare)
      }
      for _, u in ipairs(tried) do
        -- Pin host to the candidate datacenter
        dcHost = string.match(u, "^(https?://[^/]+)") or dcHost
        baseurl = "" -- reset baseurl so relative paths work
        local candidate = tryLoadLogin(u)
        if hasLoginForm(candidate) then
          html = candidate
          break
        end
      end
    end
    if not hasLoginForm(html) then
      return "EquatePlus plugin error: No login mask found!"
    end

    -- first login stage
    -- print("login first stage")
    html:xpath("//*[@id='eqUserId']"):attr("value", username)
    html:xpath("//*[@id='submitField']"):attr("value","Continue Login")
    html= HTML(connectWithCSRF(html:xpath("//*[@id='loginForm']"):submit()))
    if not hasLoginForm(html) then return "EquatePlus plugin error: No login mask found!" end

    -- second login stage: manual POST to include CSRF token in body
    -- (HTML:submit() misses JS-injected hidden fields like csrfpId)
    local function urlEncode(s)
      return (s:gsub("([^%w%-%.%_%~ ])", function(c)
        return string.format("%%%02X", string.byte(c))
      end):gsub(" ", "+"))
    end
    local postBody = "isiwebuserid=" .. urlEncode(username) ..
                     "&isiwebpasswd=" .. urlEncode(password) ..
                     "&result=Continue"
    if CSRF_TOKEN then
      postBody = postBody .. "&csrfpId=" .. urlEncode(CSRF_TOKEN)
    end
    local content = connectWithCSRF(
      "POST",
      dcHost .. "/EquatePlusParticipant2/?login",
      postBody,
      "application/x-www-form-urlencoded"
    )
    html = HTML(content)

    -- Detect SMS OTP flow
    if string.find(content, 'id="otpCodeId"') or string.find(content, 'class="otpCodeSms"') or string.find(content, 'Security Step Code') then
      awaitingOtp = true
      otpPageHtml = html

      -- Prompt for OTP via interactive callback if available
      if interactive ~= nil then
        local otp = nil
        -- Simple string prompt
        local ok1, val1 = pcall(function() return interactive("Please enter the SMS code.") end)
        if ok1 and val1 and val1 ~= '' then otp = val1 end
        -- Alternative prompt (some MoneyMoney versions)
        if (not otp or otp == '') then
          local ok2, val2 = pcall(function() return interactive({ title = "Security Code", challenge = "Please enter the SMS code." }) end)
          if ok2 and val2 and val2 ~= '' then otp = val2 end
        end
        -- Submit OTP and continue
        if otp and otp ~= '' then
          otpPageHtml:xpath("//*[@id='otpCodeId']"):attr("value", otp)
          otpPageHtml:xpath("//*[@id='submitField']"):attr("value","verify")
          local afterContent = connectWithCSRF(otpPageHtml:xpath("//*[@id='loginForm']"):submit())
          local after = HTML(afterContent)
          local errTxt = after:xpath("//*[@id='ErrorMsg']"):text()
          local otpErrTxt = after:xpath("//*[@id='OtpErrorMsg']"):text()
          if (errTxt and errTxt ~= "") or (otpErrTxt and otpErrTxt ~= "") or string.find(afterContent, 'id="otpCodeId"') then
            local msg = otpErrTxt or errTxt or "Verification failed."
            return "Operation failed: " .. msg
          end
          awaitingOtp=false
          otpPageHtml=nil
          -- Finalize login like in the QR flow
          connectWithCSRF("POST","https://www.equateplus.com/EquatePlusParticipant2/?login&_cId="..cId.."&_rId="..rnd(), "result=Continue", "application/x-www-form-urlencoded")
          -- Seed CSRF2 by loading the participant home
          connectWithCSRF("GET","https://www.equateplus.com/EquatePlusParticipant2/")
          return nil
        end
      end

      -- Fallback: open 2FA dialog; step 2 will read input
      return {
        title = "Security Code",
        challenge = "Please enter the SMS code.",
        label = "Code",
        password = true,
        default = ""
      }
    end

    -- Fallback to FIDO/QR flow (ensure client/session ids for JSON orchestration)
    local resp = connectWithCSRF(
      "POST",
      "https://www.equateplus.com/EquatePlusParticipant2/?login&_cId="..cId.."&_rId="..rnd(),
      "isiwebuserid="..username.."&isiwebpasswd=null&result=null",
      "application/x-www-form-urlencoded"
    )
    local ok, json = pcall(function() return JSON(resp):dictionary() end)
    if not ok or not json or not json["dispatchTargets"] or not json["dispatchTargets"][1] then
      return "Operation failed: Unexpected authentication method (no dispatchTargets)."
    end
    local target = json["dispatchTargets"][1]

    -- get qr code
    json = JSON(connectWithCSRF("GET","https://www.equateplus.com/EquatePlusParticipant2/?login&o.dispatchTargetId.v="..target["id"].."&_cId="..cId.."&_rId="..rnd())):dictionary()
    session_id = json["sessionId"]
    local qr_code = json["dispatcherInformation"]["response"]

    local challenge_image = generate_challenge_image(qr_code)

    -- request authentication
    return {
      title=target["name"],
      challenge=challenge_image,
    }

  else
    -- Handle second step for SMS-OTP if required
    if awaitingOtp and otpPageHtml ~= nil then
      -- Read OTP from MoneyMoney's challenge response (usually credentials[1])
      local otp = nil
      if credentials then
        -- Common positions/keys
        otp = credentials[1] or credentials["otp"] or credentials["tan"] or credentials[3]
      end
      -- As fallback (older MoneyMoney), ask via interactive dialog
      if (not otp or otp == "") and interactive ~= nil then
        local ok, value = pcall(function() return interactive("Please enter the SMS code.") end)
        if ok then otp = value end
      end
      -- If still no OTP, request input (do not clear awaitingOtp)
      if not otp or otp == "" then
        return {
          title = "Security Code",
          challenge = "Please enter the SMS code.",
          label = "Code",
          password = true,
          default = ""
        }
      end
      otpPageHtml:xpath("//*[@id='otpCodeId']"):attr("value", otp)
      otpPageHtml:xpath("//*[@id='submitField']"):attr("value","verify")
      local content = connectWithCSRF(otpPageHtml:xpath("//*[@id='loginForm']"):submit())
      local after = HTML(content)

      local errTxt = after:xpath("//*[@id='ErrorMsg']"):text()
      local otpErrTxt = after:xpath("//*[@id='OtpErrorMsg']"):text()
      if (errTxt and errTxt ~= "") or (otpErrTxt and otpErrTxt ~= "") or string.find(content, 'id="otpCodeId"') then
        local msg = otpErrTxt or errTxt or "Verification failed."
        return "Operation failed: " .. msg
      end

      awaitingOtp=false
      otpPageHtml=nil
      -- Finalize login like in the QR flow
      connectWithCSRF("POST","https://www.equateplus.com/EquatePlusParticipant2/?login&_cId="..cId.."&_rId="..rnd(), "result=Continue", "application/x-www-form-urlencoded")
      -- Seed CSRF2 by loading the participant home
      connectWithCSRF("GET","https://www.equateplus.com/EquatePlusParticipant2/")
      return nil
    end

    -- Wait up to 30 seconds for verification (FIDO/QR)
    local count = 0
    while count < 30 do
      json = JSON(connectWithCSRF("GET","https://www.equateplus.com/EquatePlusParticipant2/?login&o.fidoUafSessionId.v="..session_id.."&_cId="..cId.."&_rId="..rnd())):dictionary()
      if json["status"] == "succeeded" then
        -- Complete login after verification
        connectWithCSRF("POST","https://www.equateplus.com/EquatePlusParticipant2/?login&_cId="..cId.."&_rId="..rnd(), "result=Continue", "application/x-www-form-urlencoded")
        -- Seed CSRF2 by loading the participant home
        connectWithCSRF("GET","https://www.equateplus.com/EquatePlusParticipant2/")
        return nil
      end
      if json["status"] == "failed_retry_please" then
        return "Operation failed: Please retry."
      end
      if json["status"] == "failed" then
        return "Operation failed"
      end
      MM.sleep(1)
      count = count + 1
    end
  end

  return "Operation failed: Authentication was not confirmed"
end

function ListAccounts (knownAccounts)
  local user=JSON(connectWithCSRF("GET","https://www.equateplus.com/EquatePlusParticipant2/services/user/get?_cId="..cId.."&_rId="..rnd())):dictionary()

  if debugging then tprint (user) end
  -- Return array of accounts.
  reportOnce=true
  local account
  local status,err = pcall( function()
    account = {
      name = "Equateplus "..user["companyId"],
      --owner = user["participant"]["firstName"]["displayValue"].." "..user["participant"]["lastName"]["displayValue"],
      accountNumber = user["participant"]["userId"],
      bankCode = "equatePlus",
      currency = user["reportingCurrency"]["code"],
      portfolio = true,
      type = AccountTypePortfolio
    }
  end)--pcall
  bugReport(status,err,user)
  return {account}
end

local function isLoginRedirect(content)
  return content ~= nil and (
    string.find(content, "eqp-login-application") ~= nil or
    string.find(content, 'id="loginForm"') ~= nil or
    string.find(content, 'id="eqUserId"') ~= nil
  )
end

function RefreshAccount (account, since)
  -- Try POST (preferred on some backends)
  local summaryContent = connectWithCSRF(
    "POST",
    "https://www.equateplus.com/EquatePlusParticipant2/services/planSummary/get?_cId="..cId.."&_rId="..rnd(),
    "{\"$type\":\"Object\"}",
    "application/json;charset=UTF-8"
  )

  -- Detect session expiry / login redirect (April 2026 EquatePlus change)
  if isLoginRedirect(summaryContent) then
    print("EquatePlus: session expired or auth failed — got login page instead of portfolio data.")
    print("Please trigger a new sync to re-authenticate.")
    return {securities={}, balance=0}
  end

  local summary = JSON(summaryContent):dictionary()
  -- Fallback to GET if no entries
  if not summary or not summary["entries"] or #summary["entries"] == 0 then
    local getContent = connectWithCSRF("GET","https://www.equateplus.com/EquatePlusParticipant2/services/planSummary/get?_cId="..cId.."&_rId="..rnd())
    if isLoginRedirect(getContent) then
      print("EquatePlus: GET also returned login page — session invalid.")
      return {securities={}, balance=0}
    end
    summary = JSON(getContent):dictionary()
  end

  if not summary then
    print("EquatePlus: planSummary response could not be parsed as JSON.")
    return {securities={}, balance=0}
  end
  if not summary["entries"] then
    print("EquatePlus: planSummary has no 'entries' field — API may have changed.")
    print("Response keys:")
    for k, _ in pairs(summary) do print("  key: " .. tostring(k)) end
    return {securities={}, balance=0}
  end

  if debugging then tprint (summary) end
  local securities = {}
  reportOnce=true

  local status,err = pcall( function()
    for k,v in pairs(summary["entries"]) do
      local details=JSON(connectWithCSRF("POST","https://www.equateplus.com/EquatePlusParticipant2/services/planDetails/get?_cId="..cId.."&_rId="..rnd(),"{\"$type\":\"EntityIdentifier\",\"id\":\""..v["id"].."\"}","application/json;charset=UTF-8")):dictionary()
      if debugging then tprint (details) end
      local planNameFallback = (details and details["name"]) or v["name"] or "EquatePlus Position"
      local status,err = pcall( function()
        for k,v in pairs(details["entries"]) do
          local status,err = pcall( function()
            for k,v in pairs(v["entries"]) do
              local status,err = pcall( function()
                local marketName=v["marketName"]
                local marketPrice=v["marketPrice"]["amount"]
                local pendingShare = (v["canTrade"] == false)
                for k,v in pairs(v["entries"]) do
                  local status,err = pcall( function()
                    -- Support multiple quantity keys
                    local quantityKeyList = nil
                    quantityKeyList = {next = quantityKeyList, value = "QUANTITY"}
                    quantityKeyList = {next = quantityKeyList, value = "AVAIL_QTY"}
                    quantityKeyList = {next = quantityKeyList, value = "UNITS"}
                    quantityKeyList = {next = quantityKeyList, value = "AVAILABLE_UNITS"}
                    quantityKeyList = {next = quantityKeyList, value = "NET_UNITS"}
                    quantityKeyList = {next = quantityKeyList, value = "TOTAL_UNITS"}
                    quantityKeyList = {next = quantityKeyList, value = "LOCKED_QTY"}
                    quantityKeyList = {next = quantityKeyList, value = "LOCKED_PERF_QTY"}

                    local quantity = 0
                    local quantityKey = quantityKeyList
                    while quantityKey do
                      if v[quantityKey.value] and v[quantityKey.value]["amount"] then
                        quantity = v[quantityKey.value]["amount"]
                        break
                      end
                      quantityKey = quantityKey.next
                    end

                    -- Support multiple price keys
                    local purchasePrice = nil
                    local currencyOfPrice = nil
                    local priceKeyList = nil
                    priceKeyList = {next = priceKeyList, value = "SELL_PURCHASE_PRICE"}
                    priceKeyList = {next = priceKeyList, value = "COST_BASIS"}
                    priceKeyList = {next = priceKeyList, value = "MARKET_PRICE"}
                    priceKeyList = {next = priceKeyList, value = "PURCHASE_PRICE"}
                    local priceKey = priceKeyList
                    while priceKey do
                      if v[priceKey.value] and v[priceKey.value]["amount"] then
                        purchasePrice = v[priceKey.value]["amount"]
                        currencyOfPrice = v[priceKey.value]["unit"] and v[priceKey.value]["unit"]["code"] or nil
                        break
                      end
                      priceKey = priceKey.next
                    end

                    if purchasePrice ~= nil or quantity > 0 then
                      -- Support multiple date keys
                      local tradeTimestamp = nil
                      local dateKeyList = nil
                      dateKeyList = {next = dateKeyList, value = "ALLOC_DATE"}
                      dateKeyList = {next = dateKeyList, value = "TRANSACTION_DATE"}
                      local dateKey = dateKeyList
                      while dateKey do
                        if v[dateKey.value] and v[dateKey.value]["date"] then
                          -- Example: "2016-02-12T00:00:00.000"
                          local year, month, day = v[dateKey.value]["date"]:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
                          -- print(year .. "-" .. month .. "-" .. day)
                          tradeTimestamp=os.time({year=year,month=month,day=day})
                          break
                        end
                        dateKey = dateKey.next
                      end

                      -- Support multiple name keys
                      local name = nil
                      local nameKeyList = nil
                      nameKeyList = {next = nameKeyList, value = "VEHICLE"}
                      nameKeyList = {next = nameKeyList, value = "VEHICLE_DESCRIPTION"}
                      nameKeyList = {next = nameKeyList, value = "SECURITY"}
                      nameKeyList = {next = nameKeyList, value = "VEHICLE_NAME"}
                      local nameKey = nameKeyList
                      while nameKey and name == nil do
                        name = v[nameKey.value]
                        nameKey = nameKey.next
                      end

                      local secName = name or planNameFallback or "EquatePlus Position"

                      -- Future feature for MoneyMoney (confirmed 2022-02-10 by MRH):
                      -- requires a property similar to "booked" for accounts
                      if pendingShare then
                        print("These shares are not tradable: " .. tostring(secName))
                      end

                      local security = {
                        -- String name: Security name
                        name=secName,

                        -- String isin: ISIN
                        -- String securityNumber: WKN
                        -- String market: Exchange
                        market=marketName,

                        -- String currency: Currency for nominal or nil for units
                        -- Number quantity: Nominal amount or units
                        quantity=quantity,

                        -- Number amount: Position value in account currency
                        -- Number originalCurrencyAmount: Position value in original currency
                        -- Number exchangeRate: FX rate

                        -- Number tradeTimestamp: Quote timestamp (POSIX)
                        tradeTimestamp=tradeTimestamp,

                        -- Number price: Current price
                        price=marketPrice,

                        -- String currencyOfPrice: Price currency (if different)
                        currencyOfPrice=currencyOfPrice,

                        -- Number purchasePrice: Purchase price
                        purchasePrice=purchasePrice,

                      -- String currencyOfPurchasePrice: Purchase price currency (if different)

                      }
                      if cummulate then
                        if securities[secName] == nil then
                          if security['purchasePrice'] ~= nil then
                            security['sumPrice']=security['purchasePrice']*quantity
                          end
                          securities[secName]=security
                          table.insert(securities,security)
                        else
                          securities[secName]['quantity']=securities[secName]['quantity']+quantity
                          if security['purchasePrice'] ~= nil and securities[secName]['sumPrice'] ~= nil then
                            securities[secName]['sumPrice']=securities[secName]['sumPrice']+security['purchasePrice']*quantity
                            securities[secName]['purchasePrice']=securities[secName]['sumPrice']/securities[secName]['quantity']
                          else
                            securities[secName]['sumPrice']=nil
                            securities[secName]['purchasePrice']=nil
                          end
                        end
                      else
                        table.insert(securities,security)
                      end
                    end
                  end) --pcall
                  bugReport(status,err,v)
                end
              end)--pcall
              bugReport(status,err,v)
            end
          end) --pcall
          bugReport(status,err,v)
        end
      end) --pcall
      bugReport(status,err,v)
    end
  end) --pcall
  bugReport(status,err,details)
  return {securities=securities}
end

function FetchStatements (accounts, knownIdentifiers)
  local statements = {}

  -- Load postbox page.
  local libraryContent = connectWithCSRF("POST","https://www.equateplus.com/EquatePlusParticipant2/services/documents/library?_cId="..cId.."&_rId="..rnd(),"{\"$type\":\"Object\"}","application/json;charset=UTF-8")
  if isLoginRedirect(libraryContent) then
    print("EquatePlus: FetchStatements — session expired, got login page.")
    return {statements={}}
  end
  local library = JSON(libraryContent):dictionary()
  if not library or not library["documents"] then
    print("EquatePlus: documents/library has no 'documents' field — API may have changed.")
    if library then for k, _ in pairs(library) do print("  key: " .. tostring(k)) end end
    return {statements={}}
  end

  local pattern = "(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)"
  for k,document in pairs(library["documents"]) do
    local statement = {}
    local year, month, day, hour, minute, second = document["date"]:match(pattern)
    statement.creationDate = os.time({year=year,month=month,day=day})
    statement.name = document["description"]
    statement.identifier = document["id"]
    statement.filename = (document["description"] .. "(" .. MM.localizeDate(statement.creationDate) .. ").pdf"):gsub("/", "-")
    if not knownIdentifiers[statement.identifier] then
      if debugging then print("Downloading statement: " .. statement.filename) end
      statement.pdf = connectWithCSRF("GET", "https://www.equateplus.com/EquatePlusParticipant2/services/statements/download?documentId="..statement.identifier.."&downloadType=inline&source=LIBRARY")
      if startsWith(statement.pdf, "{\"$type\":\"TechnicalError\"") then
        print("error downloading statement")
      else
        table.insert(statements, statement)
      end
    end
  end

  return {statements=statements}
end

function bugReport(status,err,v)
  if not status and reportOnce then
    reportOnce=false
    print (string.rep('#',25).." 8< please report this bug = '"..err.."' >8 "..string.rep('#',25))
    tprint(v)
    print (string.rep('#',25).." 8< please report this bug version="..Version.." >8 "..string.rep('#',25))
  end
end

function EndSession ()
  -- Logout.
  connectWithCSRF("GET","https://www.equateplus.com/EquatePlusParticipant2/services/participant/logout")
end

-- ════════════════════════════════════════════════════════════════════════════
-- QR Code Engine (pure Lua, standalone, no external dependencies)
-- Public API: QR.encode(text, scale) → PNG binary string
-- This entire section can be removed once MoneyMoney provides a native QR API.
-- The only integration point in plugin code is generate_challenge_image() above.
-- ════════════════════════════════════════════════════════════════════════════
QR = (function()

-- Pure Lua QR Code Generator (byte mode, version auto-select, ECC level L)
-- Output: uncompressed PNG binary string (no external dependencies)
-- Compatible with Lua 5.3+ (uses native bitwise operators)

local QR = {}

-- ── GF(2^8) arithmetic ────────────────────────────────────────────────────────
-- Primitive polynomial: x^8+x^4+x^3+x^2+1 = 0x11d

local GF_EXP, GF_LOG = {}, {}
do
  local x = 1
  for i = 0, 254 do
    GF_EXP[i] = x
    GF_LOG[x] = i
    x = x << 1
    if x & 0x100 ~= 0 then x = x ~ 0x11d end
    x = x & 0xff
  end
  GF_EXP[255] = GF_EXP[0]
end

local function gf_mul(a, b)
  if a == 0 or b == 0 then return 0 end
  return GF_EXP[(GF_LOG[a] + GF_LOG[b]) % 255]
end

local function gf_poly_mul(p, q)
  local r = {}
  for i = 1, #p + #q - 1 do r[i] = 0 end
  for i = 1, #p do
    for j = 1, #q do
      r[i + j - 1] = r[i + j - 1] ~ gf_mul(p[i], q[j])
    end
  end
  return r
end

-- Generator polynomial for n ECC bytes
local function rs_generator(n)
  local g = {1}
  for i = 0, n - 1 do
    g = gf_poly_mul(g, {1, GF_EXP[i]})
  end
  return g
end

-- Remainder (ECC bytes) of message divided by generator
local function rs_remainder(msg, n)
  local gen = rs_generator(n)
  local r = {}
  for i = 1, #msg do r[i] = msg[i] end
  for i = 1, n do r[#r + 1] = 0 end
  for i = 1, #msg do
    local coef = r[i]
    if coef ~= 0 then
      for j = 1, #gen do
        r[i + j - 1] = r[i + j - 1] ~ gf_mul(gen[j], coef)
      end
    end
  end
  local ecc = {}
  for i = #msg + 1, #msg + n do ecc[#ecc + 1] = r[i] end
  return ecc
end

-- ── QR version tables (capacity in bytes, L error correction) ─────────────────
-- [version] = {data_codewords, ec_codewords_per_block, blocks_group1, blocks_group2, data_per_block_g1, data_per_block_g2}
-- Simplified: only store total data capacity (bytes) and EC info for L
local VERSION_DATA = {
  -- v  dc   ec_cw  b1  b2  d1  d2
  {  1,  19,  7,  1, 0, 19,  0},
  {  2,  34, 10,  1, 0, 34,  0},
  {  3,  55, 15,  1, 0, 55,  0},
  {  4,  80, 20,  1, 0, 80,  0},
  {  5, 108, 26,  1, 0,108,  0},
  {  6, 136, 18,  2, 0, 68,  0},
  {  7, 156, 20,  2, 0, 78,  0},
  {  8, 194, 24,  2, 0, 97,  0},
  {  9, 232, 30,  2, 0,116,  0},
  { 10, 274, 18,  2, 2, 68, 69},
  { 11, 324, 20,  4, 0, 81,  0},
  { 12, 370, 24,  2, 2, 92, 93},
  { 13, 428, 26,  4, 0,107,  0},
  { 14, 461, 30,  3, 1,115,116},
  { 15, 523, 22,  5, 1, 87, 88},
  { 16, 589, 24,  5, 1, 98, 99},
  { 17, 647, 28,  1, 5, 107,108},
  { 18, 721, 30,  5, 1,120,121},
  { 19, 795, 28,  3, 4,113,114},
  { 20, 861, 28,  3, 5,107,108},
  { 21, 932, 28,  4, 4,116,117},
  { 22,1006, 28,  2, 7,111,112},
  { 23,1094, 30,  4, 5,121,122},
  { 24,1174, 30,  6, 4,117,118},
  { 25,1276, 26,  8, 4,106,107},
  { 26,1370, 28,  10,2,114,115},
  { 27,1468, 30,  8, 4,122,123},
  { 28,1531, 30,  3, 10,117,118},
  { 29,1631, 30,  7, 7,116,117},
  { 30,1735, 30,  5, 10,115,116},
  { 31,1843, 30,  13,3,115,116},
  { 32,1955, 30,  17,0,115,  0},
  { 33,2071, 30,  17,1,115,116},
  { 34,2191, 30,  13,6,115,116},
  { 35,2306, 30,  12,7,121,122},
  { 36,2434, 30,  6, 14,121,122},
  { 37,2566, 30,  17,4,122,123},
  { 38,2702, 30,  4, 18,122,123},
  { 39,2812, 30,  20,4,117,118},
  { 40,2956, 30, 19, 6,118,119},
}

-- Alignment pattern center coordinates (version 2+)
local ALIGNMENT = {
  [2]={6,18}, [3]={6,22}, [4]={6,26}, [5]={6,30},
  [6]={6,34}, [7]={6,22,38}, [8]={6,24,42}, [9]={6,26,46},
  [10]={6,28,50}, [11]={6,30,54}, [12]={6,32,58}, [13]={6,34,62},
  [14]={6,26,46,66}, [15]={6,26,48,70}, [16]={6,26,50,74},
  [17]={6,30,54,78}, [18]={6,30,56,82}, [19]={6,30,58,86},
  [20]={6,34,62,90}, [21]={6,28,50,72,94}, [22]={6,26,50,74,98},
  [23]={6,30,54,78,102}, [24]={6,28,54,80,106}, [25]={6,32,58,84,110},
  [26]={6,30,58,86,114}, [27]={6,34,62,90,118},
  [28]={6,26,50,74,98,122}, [29]={6,30,54,78,102,126},
  [30]={6,26,52,78,104,130}, [31]={6,30,56,82,108,134},
  [32]={6,34,60,86,112,138}, [33]={6,30,58,86,114,142},
  [34]={6,34,62,90,118,146}, [35]={6,30,54,78,102,126,150},
  [36]={6,24,50,76,102,128,154}, [37]={6,28,54,80,106,132,158},
  [38]={6,32,58,84,110,136,162}, [39]={6,26,54,82,110,138,166},
  [40]={6,30,58,86,114,142,170},
}

-- Format info strings (ECC L = 01) XOR mask 101010000010010
local FORMAT_INFO = {
  [0]=0x77C4, [1]=0x72F3, [2]=0x7DAA, [3]=0x789D,
  [4]=0x662F, [5]=0x6318, [6]=0x6C41, [7]=0x6976,
}

-- Version info BCH strings for versions 7-40 (18-bit: 6-bit version + 12-bit BCH)
-- Generator: x^12 + x^11 + x^10 + x^9 + x^8 + x^5 + x^2 + 1 = 0b1111100100101
local VERSION_INFO = {
  [7]=0x07C94,  [8]=0x085BC,  [9]=0x09A99,  [10]=0x0A4D3,
  [11]=0x0BBF6, [12]=0x0C762, [13]=0x0D847, [14]=0x0E60D,
  [15]=0x0F928, [16]=0x10B78, [17]=0x1145D, [18]=0x12A17,
  [19]=0x13532, [20]=0x149A6, [21]=0x15683, [22]=0x168C9,
  [23]=0x177EC, [24]=0x18EC4, [25]=0x191E1, [26]=0x1AFAB,
  [27]=0x1B08E, [28]=0x1CC1A, [29]=0x1D33F, [30]=0x1ED75,
  [31]=0x1F250, [32]=0x209D5, [33]=0x216F0, [34]=0x228BA,
  [35]=0x2379F, [36]=0x24B0B, [37]=0x2542E, [38]=0x26A64,
  [39]=0x27541, [40]=0x28C69,
}

-- ── Matrix construction ───────────────────────────────────────────────────────

local function new_matrix(size)
  local m = {}
  for r = 1, size do
    m[r] = {}
    for c = 1, size do m[r][c] = -1 end  -- -1 = unset
  end
  return m
end

local function place_finder(m, row, col)
  for r = 0, 6 do
    for c = 0, 6 do
      local v = (r == 0 or r == 6 or c == 0 or c == 6 or (r >= 2 and r <= 4 and c >= 2 and c <= 4)) and 1 or 0
      m[row + r][col + c] = v
    end
  end
end

local function place_alignment(m, row, col)
  for r = -2, 2 do
    for c = -2, 2 do
      local v = (math.abs(r) == 2 or math.abs(c) == 2 or (r == 0 and c == 0)) and 1 or 0
      m[row + r][col + c] = v
    end
  end
end

local function is_finder_area(r, c, size)
  return (r <= 9 and c <= 9) or (r <= 9 and c >= size - 8) or (r >= size - 8 and c <= 9)
end

local function is_alignment_area(m, r, c)
  return m[r][c] ~= -1
end

local function place_format(m, mask_id, size)
  local fi = FORMAT_INFO[mask_id]
  local bits = {}
  for i = 14, 0, -1 do bits[15 - i] = (fi >> i) & 1 end

  -- Copy 1: row 9, col 9 (1-indexed); row 8, col 8 is the separator
  local hi = 0
  for _, col in ipairs({1,2,3,4,5,6,8,9}) do
    hi = hi + 1
    m[9][col] = bits[hi]
  end
  for _, row in ipairs({8,6,5,4,3,2,1}) do
    hi = hi + 1
    m[row][9] = bits[hi]
  end

  -- Copy 2 top-right: b7..b0 at cols size-7..size
  local fi2 = 8
  for col = size - 7, size do
    m[9][col] = bits[fi2]; fi2 = fi2 + 1
  end

  -- Copy 2 bottom-left: dark module + b8..b14 going down
  m[size - 7][9] = 1  -- dark module (always 1)
  local fi3 = 7
  for row = size - 6, size do
    m[row][9] = bits[fi3]; fi3 = fi3 - 1
  end
end

local function build_matrix(version, data_bits)
  local size = 4 * version + 17
  local m = new_matrix(size)

  -- Finder patterns + separators
  place_finder(m, 1, 1)
  place_finder(m, 1, size - 6)
  place_finder(m, size - 6, 1)
  -- Separators (only finder-adjacent modules, not full row/col)
  for c = 1, 9 do  -- top-left horizontal (row 8, cols 1-9)
    if m[8][c] == -1 then m[8][c] = -2 end
  end
  for r = 1, 9 do  -- top-left vertical (col 8, rows 1-9)
    if m[r][8] == -1 then m[r][8] = -2 end
  end
  for c = size - 7, size do  -- top-right horizontal (row 8, cols size-7..size)
    if m[8][c] == -1 then m[8][c] = -2 end
  end
  for r = 1, 9 do  -- top-right vertical (col size-7, rows 1-9)
    if m[r][size - 7] == -1 then m[r][size - 7] = -2 end
  end
  for c = 1, 9 do  -- bottom-left horizontal (row size-7, cols 1-9)
    if m[size - 7][c] == -1 then m[size - 7][c] = -2 end
  end
  for r = size - 7, size do  -- bottom-left vertical (col 8, rows size-7..size)
    if m[r][8] == -1 then m[r][8] = -2 end
  end

  -- Alignment patterns: skip centers on timing row (row 7, 1-indexed) or timing col
  -- (col 7, 1-indexed), and skip centers that overlap finder patterns.
  if version >= 2 and ALIGNMENT[version] then
    local ap = ALIGNMENT[version]
    for _, r0 in ipairs(ap) do
      for _, c0 in ipairs(ap) do
        local r, c = r0 + 1, c0 + 1  -- ALIGNMENT table is 0-indexed; matrix is 1-indexed
        local ok = true
        for dr = -2, 2 do
          for dc = -2, 2 do
            local nr, nc = r + dr, c + dc
            if nr < 1 or nr > size or nc < 1 or nc > size or m[nr][nc] ~= -1 then
              ok = false; break
            end
          end
          if not ok then break end
        end
        if ok then place_alignment(m, r, c) end
      end
    end
  end

  -- Timing patterns (placed after alignment; timing does not overwrite alignment modules)
  for i = 7, size - 8 do
    if m[7][i] == -1 then m[7][i] = (i % 2 == 1) and 1 or 0 end
    if m[i][7] == -1 then m[i][7] = (i % 2 == 1) and 1 or 0 end
  end

  -- Version info (version >= 7): reserve and fill 6x3 blocks top-right and bottom-left
  if version >= 7 and VERSION_INFO[version] then
    local vi = VERSION_INFO[version]
    for i = 0, 17 do
      local bit = (vi >> i) & 1
      -- Top-right block: row=i//3, col=size-11+i%3 (0-indexed) → 1-indexed: row=i//3+1, col=size-10+i%3
      m[math.floor(i/3) + 1][size - 10 + (i % 3)] = bit
      -- Bottom-left block: row=size-11+i%3 (0-indexed) → 1-indexed: row=size-10+i%3, col=i//3+1
      m[size - 10 + (i % 3)][math.floor(i/3) + 1] = bit
    end
  end

  -- Dark module
  m[size - 8 + 1][9] = 1

  -- Reserve format info positions (row 9 / col 9, 1-indexed)
  for _, c in ipairs({1,2,3,4,5,6,8,9}) do
    if m[9][c] == -1 then m[9][c] = -2 end
  end
  for _, r in ipairs({8,6,5,4,3,2,1}) do
    if m[r][9] == -1 then m[r][9] = -2 end
  end
  for c = size - 7, size do
    if m[9][c] == -1 then m[9][c] = -2 end
  end
  for r = size - 6, size do
    if m[r][9] == -1 then m[r][9] = -2 end
  end

  -- Build function module map before data placement
  local func = {}
  for r = 1, size do
    func[r] = {}
    for c = 1, size do func[r][c] = (m[r][c] ~= -1) end
  end

  -- Place data bits
  local bit_idx = 1
  local col = size
  local going_up = true
  while col >= 1 do
    if col == 7 then col = col - 1 end  -- skip timing column (col 7 = 1-indexed timing strip)
    for row_iter = 1, size do
      local r = going_up and (size + 1 - row_iter) or row_iter
      for dc = 0, 1 do
        local c = col - dc
        if c >= 1 and m[r][c] == -1 then
          m[r][c] = bit_idx <= #data_bits and data_bits[bit_idx] or 0
          bit_idx = bit_idx + 1
        end
      end
    end
    going_up = not going_up
    col = col - 2
  end

  return m, size, func
end

-- Masking functions
local MASK_FN = {
  function(r,c) return (r + c) % 2 == 0 end,
  function(r,_) return r % 2 == 0 end,
  function(_,c) return c % 3 == 0 end,
  function(r,c) return (r + c) % 3 == 0 end,
  function(r,c) return (math.floor(r/2) + math.floor(c/3)) % 2 == 0 end,
  function(r,c) return (r*c)%2 + (r*c)%3 == 0 end,
  function(r,c) return ((r*c)%2 + (r*c)%3) % 2 == 0 end,
  function(r,c) return ((r+c)%2 + (r*c)%3) % 2 == 0 end,
}

local function apply_mask(m, mask_id, size, func)
  local fn = MASK_FN[mask_id + 1]
  local result = {}
  for r = 1, size do
    result[r] = {}
    for c = 1, size do
      local v = m[r][c]
      if (v == 0 or v == 1) and not func[r][c] then
        result[r][c] = fn(r - 1, c - 1) and (1 - v) or v
      else
        result[r][c] = v
      end
    end
  end
  return result
end

local function penalty(m, size)
  local score = 0
  -- N1: 5+ in a row same color
  for r = 1, size do
    local run, cur = 0, -1
    for c = 1, size do
      local v = m[r][c] == 1 and 1 or 0
      if v == cur then run = run + 1 else run = 1; cur = v end
      if run == 5 then score = score + 3 elseif run > 5 then score = score + 1 end
    end
  end
  for c = 1, size do
    local run, cur = 0, -1
    for r = 1, size do
      local v = m[r][c] == 1 and 1 or 0
      if v == cur then run = run + 1 else run = 1; cur = v end
      if run == 5 then score = score + 3 elseif run > 5 then score = score + 1 end
    end
  end
  -- N2: 2x2 blocks
  for r = 1, size - 1 do
    for c = 1, size - 1 do
      local v = m[r][c] == 1 and 1 or 0
      if v == (m[r+1][c]==1 and 1 or 0) and v == (m[r][c+1]==1 and 1 or 0) and v == (m[r+1][c+1]==1 and 1 or 0) then
        score = score + 3
      end
    end
  end
  return score
end

-- ── Data encoding ─────────────────────────────────────────────────────────────

local function encode_data(version, data_bytes)
  local vd = VERSION_DATA[version]
  local total_dc = vd[2]
  local ec_per_block = vd[3]
  local b1 = vd[4]; local b2 = vd[5]
  local d1 = vd[6]; local d2 = vd[7]
  local total_blocks = b1 + b2

  -- Build bit stream: mode indicator (0100 = byte), length, data, terminator, padding
  local bits = {}
  local function push_bits(val, n)
    for i = n - 1, 0, -1 do
      bits[#bits + 1] = (val >> i) & 1
    end
  end

  local char_count_bits = version <= 9 and 8 or 16
  push_bits(4, 4)  -- byte mode
  push_bits(#data_bytes, char_count_bits)
  for _, b in ipairs(data_bytes) do push_bits(b, 8) end

  -- Terminator
  local max_bits = total_dc * 8
  for _ = 1, math.min(4, max_bits - #bits) do bits[#bits + 1] = 0 end

  -- Byte-align
  while #bits % 8 ~= 0 do bits[#bits + 1] = 0 end

  -- Pad bytes
  local pad = {0xEC, 0x11}
  local pi = 1
  while #bits < max_bits do
    push_bits(pad[pi], 8)
    pi = pi % 2 + 1
  end

  -- Convert bits to codewords
  local cw = {}
  for i = 1, #bits, 8 do
    local b = 0
    for j = 0, 7 do b = (b << 1) | (bits[i + j] or 0) end
    cw[#cw + 1] = b
  end

  -- Split into blocks and compute ECC
  local blocks = {}
  local idx = 1
  for block = 1, total_blocks do
    local dlen = (block <= b1) and d1 or d2
    local dc = {}
    for i = 1, dlen do dc[i] = cw[idx]; idx = idx + 1 end
    local ec = rs_remainder(dc, ec_per_block)
    blocks[block] = {dc = dc, ec = ec}
  end

  -- Interleave data codewords
  local interleaved = {}
  local max_d = b2 > 0 and d2 or d1
  for i = 1, max_d do
    for _, blk in ipairs(blocks) do
      if blk.dc[i] then interleaved[#interleaved + 1] = blk.dc[i] end
    end
  end
  -- Interleave ECC codewords
  for i = 1, ec_per_block do
    for _, blk in ipairs(blocks) do
      interleaved[#interleaved + 1] = blk.ec[i]
    end
  end

  -- Convert to bit array
  local data_bits = {}
  for _, b in ipairs(interleaved) do
    for i = 7, 0, -1 do data_bits[#data_bits + 1] = (b >> i) & 1 end
  end

  return data_bits
end

-- ── PNG output ────────────────────────────────────────────────────────────────

local function crc32(data)
  local crc = 0xFFFFFFFF
  local t = {}
  for i = 0, 255 do
    local c = i
    for _ = 1, 8 do
      if c & 1 == 1 then c = (c >> 1) ~ 0xEDB88320
      else c = c >> 1 end
    end
    t[i] = c
  end
  for i = 1, #data do
    local byte = data:byte(i)
    crc = t[(crc ~ byte) & 0xFF] ~ (crc >> 8)
  end
  return (~crc) & 0xFFFFFFFF
end

local function u32be(n)
  return string.char(
    (n >> 24) & 0xFF, (n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF
  )
end

local function png_chunk(type_str, data)
  local chunk = type_str .. data
  return u32be(#data) .. chunk .. u32be(crc32(chunk))
end

local function matrix_to_png(m, size, scale)
  scale = scale or 4
  local quiet = 4  -- quiet zone in modules
  local img_size = (size + 2 * quiet) * scale

  -- IHDR
  local ihdr_data = u32be(img_size) .. u32be(img_size) ..
    string.char(8, 2, 0, 0, 0)  -- 8-bit RGB
  local ihdr = png_chunk("IHDR", ihdr_data)

  -- Build raw image rows
  local rows = {}
  -- Top quiet zone
  local white_px = string.char(255, 255, 255)
  local black_px = string.char(0, 0, 0)
  local white_row = string.char(0)  -- filter byte
  for _ = 1, img_size do white_row = white_row .. white_px end
  for _ = 1, quiet * scale do rows[#rows + 1] = white_row end

  for r = 1, size do
    local row_pixels = {string.char(0)}  -- filter byte: None
    for _ = 1, quiet * scale do row_pixels[#row_pixels + 1] = white_px end
    for c = 1, size do
      local v = (m[r][c] == 1) and black_px or white_px
      for _ = 1, scale do row_pixels[#row_pixels + 1] = v end
    end
    for _ = 1, quiet * scale do row_pixels[#row_pixels + 1] = white_px end
    local row = table.concat(row_pixels)
    for _ = 1, scale do rows[#rows + 1] = row end
  end

  -- Bottom quiet zone
  for _ = 1, quiet * scale do rows[#rows + 1] = white_row end

  -- Uncompressed DEFLATE (stored blocks)
  local raw = table.concat(rows)
  local BLOCK_SIZE = 65535
  local deflate_blocks = {}
  local pos = 1
  while pos <= #raw do
    local chunk_data = raw:sub(pos, pos + BLOCK_SIZE - 1)
    local last = pos + #chunk_data - 1 >= #raw and 1 or 0
    local len = #chunk_data
    local nlen = (~len) & 0xFFFF
    deflate_blocks[#deflate_blocks + 1] = string.char(last,
      len & 0xFF, (len >> 8) & 0xFF,
      nlen & 0xFF, (nlen >> 8) & 0xFF) .. chunk_data
    pos = pos + BLOCK_SIZE
  end

  -- zlib wrapper
  local deflate_data = table.concat(deflate_blocks)
  -- Adler-32
  local s1, s2 = 1, 0
  for i = 1, #raw do
    s1 = (s1 + raw:byte(i)) % 65521
    s2 = (s2 + s1) % 65521
  end
  local adler = u32be((s2 << 16) | s1)
  local zlib_data = string.char(0x78, 0x01) .. deflate_data .. adler

  local idat = png_chunk("IDAT", zlib_data)
  local iend = png_chunk("IEND", "")

  return "\x89PNG\r\n\x1a\n" .. ihdr .. idat .. iend
end

-- ── Public API ────────────────────────────────────────────────────────────────

function QR.encode(text, scale)
  local data_bytes = {}
  for i = 1, #text do data_bytes[i] = text:byte(i) end

  -- Auto-select version
  local version = nil
  for v = 1, 40 do
    local cap_bits = (VERSION_DATA[v][2]) * 8
    local char_count_bits = v <= 9 and 8 or 16
    local needed = 4 + char_count_bits + #data_bytes * 8
    if needed <= cap_bits then
      version = v
      break
    end
  end
  if not version then error("Data too long for QR code") end

  local data_bits = encode_data(version, data_bytes)
  local size = 4 * version + 17

  -- Try all 8 masks, pick best
  local base_m, _, func = build_matrix(version, data_bits)
  local best_m, best_score, best_mask = nil, math.huge, 0
  for mask_id = 0, 7 do
    local masked = apply_mask(base_m, mask_id, size, func)
    -- Apply format info
    place_format(masked, mask_id, size)
    local s = penalty(masked, size)
    if s < best_score then
      best_score = s; best_m = masked; best_mask = mask_id
    end
  end

  return matrix_to_png(best_m, size, scale or 4)
end

-- Encodes text into a PNG that fits within max_px × max_px.
-- Computes the largest integer scale such that (qr_size + 8) * scale <= max_px.
-- No external resize needed — output is pixel-perfect.
function QR.encode_fit(text, max_px)
  local data_bytes = {}
  for i = 1, #text do data_bytes[i] = text:byte(i) end

  local version = nil
  for v = 1, 40 do
    local cap_bits = VERSION_DATA[v][2] * 8
    local char_count_bits = v <= 9 and 8 or 16
    if 4 + char_count_bits + #data_bytes * 8 <= cap_bits then
      version = v; break
    end
  end
  if not version then error("Data too long for QR code") end

  local data_bits = encode_data(version, data_bytes)
  local size = 4 * version + 17
  local scale = math.floor(max_px / (size + 8))
  if scale < 1 then scale = 1 end
  lprint("QR: v" .. version .. " size=" .. size .. "x" .. size .. " scale=" .. scale .. " → " .. (size+8)*scale .. "px")

  local base_m, _, func = build_matrix(version, data_bits)
  local best_m, best_score, best_mask = nil, math.huge, 0
  for mask_id = 0, 7 do
    local masked = apply_mask(base_m, mask_id, size, func)
    place_format(masked, mask_id, size)
    local s = penalty(masked, size)
    if s < best_score then
      best_score = s; best_m = masked; best_mask = mask_id
    end
  end

  return matrix_to_png(best_m, size, scale)
end

return QR

end)()
