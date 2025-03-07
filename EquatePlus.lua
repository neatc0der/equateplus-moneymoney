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
  csrfpIdTemp=string.match(content,"\"csrfpId\" *, *\"([^\"]+)\"")
  if csrfpIdTemp ~= nil and csrfpIdTemp ~= '' then
    CSRF_TOKEN=csrfpIdTemp
  end
  csrf2Temp=string.match(content,"\"equateCsrfToken2\":\"([^\"]+)\"")
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
  description = "Depot von EquatePlus"
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

    content, charset, mimeType, filename, headers = connectWithCSRF(html:xpath("//*[@id='loginForm']"):submit())
    html = HTML(content)

    -- get first device id
    json = JSON(connectWithCSRF("POST","https://www.equateplus.com/EquatePlusParticipant2/?login","isiwebuserid="..username.."&isiwebpasswd=null&result=null", "application/x-www-form-urlencoded")):dictionary()
    target = json["dispatchTargets"][1]

    -- get qr code
    json = JSON(connectWithCSRF("GET","https://www.equateplus.com/EquatePlusParticipant2/?login&o.dispatchTargetId.v="..target["id"].."&_cId="..cId.."&_rId="..rnd())):dictionary()
    session_id = json["sessionId"]
    qr_code = json["dispatcherInformation"]["response"]

    -- request authentication
    return {
      title=target["name"],
      challenge=MM.imageResize(MM.base64decode(qr_code),240,240),
    }

  else
    -- wait up to 30 seconds for verification
    count = 0
    while count < 30 do
      json = JSON(connectWithCSRF("GET","https://www.equateplus.com/EquatePlusParticipant2/?login&o.fidoUafSessionId.v="..session_id.."&_cId="..cId.."&_rId="..rnd())):dictionary()
      print(json["status"])
      if json["status"] == "succeeded" then
        -- complete login after verification
        connectWithCSRF("POST","?login&_cId="..cId.."&_rId="..rnd(), "result=Continue", "application/x-www-form-urlencoded")
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
  local user=JSON(connectWithCSRF("GET","services/user/get")):dictionary()

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
  local summary = JSON(connectWithCSRF("GET","https://www.equateplus.com/EquatePlusParticipant2/services/planSummary/get?_cId="..cId.."&_rId="..rnd())):dictionary()
  if debugging then tprint (summary) end
  local securities = {}
  reportOnce=true

  local status,err = pcall( function()
    for k,v in pairs(summary["entries"]) do
      local details=JSON(connectWithCSRF("POST","https://www.equateplus.com/EquatePlusParticipant2/services/planDetails/get?_cId="..cId.."&_rId="..rnd(),"{\"$type\":\"EntityIdentifier\",\"id\":\""..v["id"].."\"}","application/json;charset=UTF-8")):dictionary()
      if debugging then tprint (details) end
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
                    -- allow multiple quantity keywords
                    local quantityKeyList = nil
                    quantityKeyList = {next = quantityKeyList, value = "QUANTITY"}
                    quantityKeyList = {next = quantityKeyList, value = "AVAIL_QTY"}
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

                    -- allow multiple price keywords
                    local purchasePrice = nil
                    local currencyOfPrice = nil
                    local priceKeyList = nil
                    priceKeyList = {next = priceKeyList, value = "SELL_PURCHASE_PRICE"}
                    priceKeyList = {next = priceKeyList, value = "COST_BASIS"}
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
                      -- allow multiple date keywords
                      local tradeTimestamp = nil
                      local dateKeyList = nil
                      dateKeyList = {next = dateKeyList, value = "ALLOC_DATE"}
                      dateKeyList = {next = dateKeyList, value = "TRANSACTION_DATE"}
                      local dateKey = dateKeyList
                      while dateKey do
                        if v[dateKey.value] and v[dateKey.value]["date"] then
                          -- "date": "2016-02-12T00:00:00.000",
                          local year, month, day = v[dateKey.value]["date"]:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
                          -- print(year .. "-" .. month .. "-" .. day)
                          tradeTimestamp=os.time({year=year,month=month,day=day})
                          break
                        end
                        dateKey = dateKey.next
                      end

                      -- allow multiple name keywords
                      local name = nil
                      local nameKeyList = nil
                      nameKeyList = {next = nameKeyList, value = "VEHICLE"}
                      nameKeyList = {next = nameKeyList, value = "VEHICLE_DESCRIPTION"}
                      local nameKey = nameKeyList
                      while nameKey and name == nil do
                        name = v[nameKey.value]
                        nameKey = nameKey.next
                      end

                      -- feature for future version of MoneyMoney (request confirmed on 2022-02-10 by MRH)
                      -- requires a property similar to "booked" for accounts
                      if pendingShare then
                        print("these shares are not tradable: " .. name)
                      end

                      local security = {
                        -- String name: Bezeichnung des Wertpapiers
                        name=name,

                        -- String isin: ISIN
                        -- String securityNumber: WKN
                        -- String market: Börse
                        market=marketName,

                        -- String currency: Währung bei Nominalbetrag oder nil bei Stückzahl
                        -- Number quantity: Nominalbetrag oder Stückzahl
                        quantity=quantity,

                        -- Number amount: Wert der Depotposition in Kontowährung
                        -- Number originalCurrencyAmount: Wert der Depotposition in Originalwährung
                        -- Number exchangeRate: Wechselkurs

                        -- Number tradeTimestamp: Notierungszeitpunkt; Die Angabe erfolgt in Form eines POSIX-Zeitstempels.
                        tradeTimestamp=tradeTimestamp,

                        -- Number price: Aktueller Preis oder Kurs
                        price=marketPrice,

                        -- String currencyOfPrice: Von der Kontowährung abweichende Währung des Preises.
                        currencyOfPrice=currencyOfPrice,

                        -- Number purchasePrice: Kaufpreis oder Kaufkurs
                        purchasePrice=purchasePrice,

                      -- String currencyOfPurchasePrice: Von der Kontowährung abweichende Währung des Kaufpreises.

                      }
                      if cummulate then
                        if securities[name] == nil then
                          if security['purchasePrice'] ~= nil then
                            security['sumPrice']=security['purchasePrice']*quantity
                          end
                          securities[name]=security
                          table.insert(securities,security)
                        else
                          securities[name]['quantity']=securities[name]['quantity']+quantity
                          if security['purchasePrice'] ~= nil and securities[name]['sumPrice'] ~= nil then
                            securities[name]['sumPrice']=securities[name]['sumPrice']+security['purchasePrice']*quantity
                            securities[name]['purchasePrice']=securities[name]['sumPrice']/securities[name]['quantity']
                          else
                            securities[name]['sumPrice']=nil
                            securities[name]['purchasePrice']=nil
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

-- SIGNATURE: MCwCFAf5dPf+zi2l1NSWRHsSzplHaJyLAhQZSM+ssqOMG1BBGvMO2OTFeWkfbA==
