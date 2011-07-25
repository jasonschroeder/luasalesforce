
-- some url encoding helpers from the PIL reference: http://www.lua.org/pil/20.3.html

-- Usage:
--   t = {name = "al",  query = "a+b = c", q="yes or no"}
--   print(encode(t)) --> q=yes+or+no&query=a%2Bb+%3D+c&name=al



function escape (s)
   s = string.gsub(s, "([&=+%c])", function (c)
                                      return string.format("%%%02X", string.byte(c))
                                end)
   s = string.gsub(s, " ", "+")
   return s
end

--The encode function traverses the table to be encoded, building the resulting string:
function encode (t)
   local s = ""
   for k,v in pairs(t) do
      s = s .. "&" .. escape(k) .. "=" .. escape(v)
   end
   return string.sub(s, 2)     -- remove first `&'
end

