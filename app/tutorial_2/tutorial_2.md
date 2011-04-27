In this tutorial, we will look different styles of sinatra app and the the sinatra extension system. You may find that reading the sections "Rack Middleware", "Sinatra::Base - Middleware, Libraries, and Modular Apps" and "Scopes and Binding" in sinatra README may help to understand the topic.

In tutorial_1 we saw a basic form of sinatra app: require the sinatra library and define routes directly in the same file. This is referred to as the "classic" style(see classic.rb). As a contrast the other style is called "modular" style(see modular.rb).

In modular.rb, first Sinatra::Base is required by require 'sinatra/base'. Then we define our app by making Modular class a subclass of Sinatra::Base. We can define routes as instance methods inside the Modular class. This makes perfect sense because the route definition methods like `get` are defined on Sinatra::Base. So the first conclusion is the modular style app has nothing to do with the Sinatra::Application. Everything is contained in the modular app in its own scope; as a contrast the classic style app uses the subclass of Sinatra::Base - Sinatra::Application.

Next let's see how to start a modular app. There are two ways. First we can use the `run!` method as we talked in tutorial_1 and throw it after the routes, like this:

require 'sinatra/base'
class Modular < Sinatra::Base
  get '/' do
    'Hello world!'
  end
  run!
end

Then `run!` will just fire up a rack server and pass in `self`, i.e. Sinatra::Base.

Second, we can use a .ru file to start it. If you look at modular.ru, we just require the sinatra

require File.expand_path(File.dirname(__FILE__) + '/modular')
run Sinatra::Base
#run Modular

As stated by the source annotation, the extensions method returns an array of registered extensions that are stored in @extensions.

  # Extension modules registered on this class and all superclasses.
  # def extensions
  #   if superclass.respond_to?(:extensions)
  #     (@extensions + superclass.extensions).uniq
  #   else
  #     @extensions
  #   end
  # end


rack uses config.ru to load and set up rack middleware stack

use method Rack::Builder
 
use Rack::Auth::Basic do |username, password|
  username == 'admin' && password == 'secret'
end