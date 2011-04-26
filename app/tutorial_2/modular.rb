require 'sinatra/base'

class Modular < Sinatra::Base
  
  get '/' do
    'Hello world!'
  end
  
  run!
end