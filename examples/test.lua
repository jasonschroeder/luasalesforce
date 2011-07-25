local salesforceapi = require('salesforce')

local session = salesforceapi.login{username = 'user@host.com',
                                    password = 'password'}

-- Get a list of Salesforce REST API resources:
print ("Resources: " .. json.encode(session:getResources()))

-- Create a new Contact:
response = session:createUpdateRecord('Contact', {FirstName = 'Joe',
                                                  LastName  = 'User'})
print ("Record created: " .. response.id)

-- Update a record:
response = session:createUpdateRecord('Contact', {Title = 'Joseph'}, response.id)
print ("Record updated: " .. response.id)
