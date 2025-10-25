local url="https://www.equateplus.com"

function rnd()
  return math.random(10000000,99999999)
end

local baseurl=""
local reportOnce
local Version=3.00
local CSRF_TOKEN=nil
local CSRF2_TOKEN=nil
local connection
local debugging=true
local nosecrets=true
local cummulate=false
local html
local cId="eqp."..rnd()
local session_id

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
  url=baseurl..url
  -- print("baseurl="..baseurl)
  postContentType=postContentType or "application/json"
  local content

  if headers == nil then
    headers={}
  end
  headers["Accept"] = "*/*"
  -- Set Referer for service calls; some backends validate it
  if string.find(url, "/EquatePlusParticipant2/services/") and headers["Referer"] == nil then
    headers["Referer"] = "https://www.equateplus.com/EquatePlusParticipant2/"
  end

  if CSRF_TOKEN ~= nil then
    headers['csrfpId']=CSRF_TOKEN
  else
    print("without CSRF_TOKEN")
  end
  if CSRF2_TOKEN ~= nil then
    headers["EQUATE-CSRF2-TOKEN-PARTICIPANT2"]=CSRF2_TOKEN
  end
  if method == 'POST' then
    -- lprint(postContent)
    if postContent == nil then
      postContent=""
    end
  end

  content, charset, mimeType, filename, headers = connection:request(method, url, postContent, postContentType, headers)
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
    tprint(headers)
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
      formatting = string.rep(" ", indent) .. k .. ": "
      if nosecrets and (type(v) == 'string') then
        print(formatting .. type(v).."'"..v.."'")
      else
        print(formatting .. type(v))
      end
      if type(v) == 'table' and indent < 9 then tprint(v,indent+3) end
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

    -- get login page
    html = HTML(connectWithCSRF("GET",url))
    if html:xpath("//*[@id='loginForm']"):text() == '' then return "EquatePlus plugin error: No login mask found!" end

    -- first login stage
    -- print("login first stage")
    html:xpath("//*[@id='eqUserId']"):attr("value", username)
    html:xpath("//*[@id='submitField']"):attr("value","Continue Login")
    html= HTML(connectWithCSRF(html:xpath("//*[@id='loginForm']"):submit()))
    if html:xpath("//*[@id='loginForm']"):text() == '' then return "EquatePlus plugin error: No login mask found!" end

    -- second login stage
    -- print("login second stage")
    html:xpath("//*[@id='eqUserId']"):attr("value", username)
    html:xpath("//*[@id='eqPwdId']"):attr("value", password)
    html:xpath("//*[@id='submitField']"):attr("value","Continue")

    local content = connectWithCSRF(html:xpath("//*[@id='loginForm']"):submit())
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

    -- Fallback to FIDO/QR flow
    local resp = connectWithCSRF("POST","https://www.equateplus.com/EquatePlusParticipant2/?login","isiwebuserid="..username.."&isiwebpasswd=null&result=null", "application/x-www-form-urlencoded")
    local ok, json = pcall(function() return JSON(resp):dictionary() end)
    if not ok or not json or not json["dispatchTargets"] or not json["dispatchTargets"][1] then
      return "Operation failed: Unexpected authentication method (no dispatchTargets)."
    end
    local target = json["dispatchTargets"][1]

    -- get qr code
    json = JSON(connectWithCSRF("GET","https://www.equateplus.com/EquatePlusParticipant2/?login&o.dispatchTargetId.v="..target["id"].."&_cId="..cId.."&_rId="..rnd())):dictionary()
    session_id = json["sessionId"]
    local qr_code = json["dispatcherInformation"]["response"]

    -- request authentication
    return {
      title=target["name"],
      challenge=MM.imageResize(MM.base64decode(qr_code),240,240),
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
    count = 0
    while count < 30 do
      json = JSON(connectWithCSRF("GET","https://www.equateplus.com/EquatePlusParticipant2/?login&o.fidoUafSessionId.v="..session_id.."&_cId="..cId.."&_rId="..rnd())):dictionary()
      print(json["status"])
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

function RefreshAccount (account, since)
  -- Try POST (preferred on some backends)
  local summaryContent = connectWithCSRF(
    "POST",
    "https://www.equateplus.com/EquatePlusParticipant2/services/planSummary/get?_cId="..cId.."&_rId="..rnd(),
    "{\"$type\":\"Object\"}",
    "application/json;charset=UTF-8"
  )
  local summary = JSON(summaryContent):dictionary()
  -- Fallback to GET if no entries
  if not summary or not summary["entries"] or #summary["entries"] == 0 then
    summary = JSON(connectWithCSRF("GET","https://www.equateplus.com/EquatePlusParticipant2/services/planSummary/get?_cId="..cId.."&_rId="..rnd())):dictionary()
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
  local library = JSON(connectWithCSRF("POST","https://www.equateplus.com/EquatePlusParticipant2/services/documents/library?_cId="..cId.."&_rId="..rnd(),"{\"$type\":\"Object\"}","application/json;charset=UTF-8")):dictionary()

  local pattern = "(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)"
  for k,document in pairs(library["documents"]) do
    local statement = {}
    local year, month, day, hour, minute, second = document["date"]:match(pattern)
    statement.creationDate = os.time({year=year,month=month,day=day})
    statement.name = document["description"]
    statement.identifier = document["id"]
    statement.filename = (document["description"] .. "(" .. MM.localizeDate(statement.creationDate) .. ").pdf"):gsub("/", "-")
    if not knownIdentifiers[statement.identifier] then
      print("Downloading statement: " .. statement.filename)
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

-- NOTE: Signature removed due to local modifications.
