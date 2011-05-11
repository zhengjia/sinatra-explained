require 'sinatra/base'

include Sinatra::Delegator

get '/' do
  'Hello world!'
end

Sinatra::Application.run!
# Sinatra::Base.run!