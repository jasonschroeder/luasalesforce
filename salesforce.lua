-----------------------------------------------------------------------------
-- luaSalesforce: Salesforce REST API support for the Lua language.
-- salesforce Module.
-- Author: Jason Schroeder
-- Version: 1.0
-- This module is released under the MIT License (MIT).
-- Please see LICENCE.txt for details.
--
-- USAGE:

--
-- REQUIREMENTS:
--   compat-5.1 if using Lua 5.0
--   luasocket
--   ltn12
--   ssl (luasec)
--
-- CHANGELOG
--	 0.1 Initial availability.
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------
-- Dependencies
-----------------------------------------------------------------------------
local http   = require "socket.http"
local socket = require "socket"
local ltn12  = require "ltn12"
local ssl    = require "ssl"

-----------------------------------------------------------------------------
-- Imports
-----------------------------------------------------------------------------
local json = require('json')
local urlencoding = require "urlencoding"

-- Feel free to change the OAuth 2.0 client ID and secret. These default to the "luaSalesforce" application.
local oauth = {oauth_client_id = "3MVG9Km_cBLhsuPzGokY_8EYSdZAMFVxEfU3FjlZ_S8QtzthoQOkKdBPmGdRYxnpYjD7W16AsC1F9QNjKBlhM",
               oauth_secret = "2008518770313085301"}

-- magic for SSL.
-- http://lua-users.org/lists/lua-l/2009-02/msg00270.html
local params = {
    mode = "client",
    protocol = "sslv23",
    cafile = "/opt/local/share/curl/curl-ca-bundle.crt",
    verify = "peer",
    options = "all",
}

local try = socket.try
local protect = socket.protect

function create()
    local t = {c=try(socket.tcp())}

    function idx (tbl, key)
        --print("idx " .. key)
        return function (prxy, ...)
                   local c = prxy.c
                   return c[key](c,...)
               end
    end


    function t:connect(host, port)
        -- print ("proxy connect ", host, port)
        try(self.c:connect(host, port))
        -- print ("connected")
        self.c = try(ssl.wrap(self.c,params))
        -- print("wrapped")
        try(self.c:dohandshake())
        -- print("handshaked")
        return 1
    end

    return setmetatable(t, {__index = idx})
end



salesforce = {}
-- "Constructor"
function salesforce:new (o)
   o = o or {}   -- create object if user does not provide one
   setmetatable(o, self)
   self.__index = self
   return o
end


--- Login to Salesforce
-- @param credentials A table with either (refresh_token) or (username and password)
-- @see https://login.salesforce.com/help/doc/en/remoteaccess_oauth_username_password_flow.htm
-- @see https://login.salesforce.com/help/doc/en/remoteaccess_oauth_refresh_token_flow.htm
function salesforce.login(credentials)
   assert (type(credentials) == 'table', 'Expected a Table argument')
   local loginHost = credentials.login_host or "login.salesforce.com"
   local tokenUrl = 'https://' .. loginHost .. ':443/services/oauth2/token'

   local postParams = {                        
      client_id = oauth.oauth_client_id,
      client_secret = oauth.oauth_secret,
      format = "json"
   }

   if (credentials.refresh_token) then
      postParams.grant_type = "refresh_token"
      postParams.refresh_token = credentials.refresh_token
   elseif (credentials.username and credentials.password) then
      print ('username is ' .. credentials.username)
      postParams.grant_type = "password"
      postParams.username = credentials.username
      postParams.password = credentials.password
   else 
      error "Missing credentials. Provide either refresh_token, OR (username and password)"
   end

   local postBody = encode(postParams)
   local headers = {['Content-Length'] = #postBody,
                    ['Content-Type'] = "application/x-www-form-urlencoded",}
   local response_body = {}
   local body, status, headers = http.request{
      url = tokenUrl,
      method = 'POST',
      headers = headers,
      source = ltn12.source.string(postBody),
      sink = ltn12.sink.table(response_body),
      create = create,
   }

   local result = json.decode(table.concat(response_body))
   if (_G['sha2'] and _G['mime']) then
      -- signature—Base64-encoded HMAC-SHA256 signature signed with
      -- the consumer's private key containing the concatenated ID and issued_at.
      -- This can be used to verify the identity URL was not modified since it
      -- was sent by the server.
      local actual_hmac = mime.b64(hmac.sha256(result.id .. result.issued_at,oauth.oauth_secret))
      assert (result.signature == actual_hmac, 'HMAC-SHA256 mismatch!')
   end
   local s =  salesforce:new{instance_url = result.instance_url .. ":443",
                             session_id = result.access_token}
   -- get API versions, and use the latest.
   local versions = s:getVersions()
   s.api_version = versions[1].version
   return s
end



-- Returns a list of Salesforce versions, sorted latest to oldest.
function salesforce:getVersions()
   -- this call does not require authentication.
   local url = 'http://na1.salesforce.com/services/data.json'
   -- the simple form returns the response body as a string,
   -- followed by the response status code,
   -- the response headers and the response status line
   local body, status, headers = http.request(url)
   v = json.decode(body)
   -- sort the response array by version number, descending.
   table.sort(v, function(a, b)
                    return tonumber(a.version) > tonumber(b.version)
                 end
           )
   --for k,v in ipairs(v) do
   --   print (v.label .. ": " .. v.version)
   --end
   return v
end

function salesforce:_doGet(url)
   local sendHeaders = {Authorization = "OAuth " .. self.session_id}
   local response_body = {}
   local body, status, headers = http.request{
      url = url,
      headers = sendHeaders,
      sink = ltn12.sink.table(response_body),
      create = create,
   }

   return json.decode(table.concat(response_body))
end

function salesforce:getResources()
   local url = self.instance_url .. '/services/data/v' .. self.api_version .. '/'
   return self:_doGet(url)
end

function salesforce:describeGlobal()
   return self:_get(self.instance_url .. '/services/data/v' .. self.api_version ..'/objects/')
end

function salesforce:describeSObject(objectType)
   return self:_get(self.instance_url .. '/services/data/v' .. self.api_version ..'/sobjects/' .. objectType .. '/')
end

function salesforce:createUpdateRecord(objectType, values, recordid)
   local postUrl = self.instance_url .. '/services/data/v' .. self.api_version ..'/sobjects/' .. objectType .. '/'
   local method = 'POST'
   if (recordid) then
      postUrl = postUrl .. recordid .. '/'
      method = 'PATCH'
   end
   local postBody = json.encode(values)
   local headers = {Authorization = "OAuth " .. self.session_id, 
                    ['Content-Length'] = #postBody,
                    ['Content-Type'] = "application/json",}
   local response_body = {}

   local body, status, headers = http.request{
      url = postUrl,
      method = method,
      headers = headers,
      source = ltn12.source.string(postBody),
      sink = ltn12.sink.table(response_body),
      create = create,
   }
   local jsonResponse = table.concat(response_body)
   print ('Response: ' , jsonResponse, "status=", status)
   if status == 201 then -- 201 Created (insert)
      return json.decode(jsonResponse)
   end
   if (recordid and status == 204) then -- 204 Updated
      return {id = recordid}
   end
   -- there was an error.
   -- See http://www.salesforce.com/us/developer/docs/api_rest/Content/errorcodes.htm
   error (json.decode(jsonResponse).message)
end

function salesforce:deleteRecord(objectType, recordid)
   error "not yet implemented"
end

return salesforce