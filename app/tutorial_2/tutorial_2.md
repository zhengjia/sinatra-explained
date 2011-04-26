In this tutorial, we will look different styles of sinatra app and the the sinatra extension system. You may find that reading the sections "Rack Middleware", "Sinatra::Base - Middleware, Libraries, and Modular Apps" and "Scopes and Binding" in sinatra README may help to understand the topic.

In tutorial_1 we saw a basic form of sinatra app: require the sinatra library and define routes directly in the same file. This is referred to as the "classic" style(see classic.rb). As a contrast the other style is called "modular" style(see modular.rb).

In modular.rb, first Sinatra::Base is required by require 'sinatra/base'. Then we define our app by making Modular class a subclass of Sinatra::Base. We can define routes as instance methods inside the Modular class. This makes perfect sense because the route definition methods like `get` are defined on Sinatra::Base. When running the modular app, we can just call the `run!` method on Sinatra::Base and it will fire up the server. So the first conclusion is the modular style app has nothing to do with the Sinatra::Application. Everything is contained in the modular app in its own scope; as a contrast the classic style app uses Delegator module to define a set of methods on the top level.


As stated by the source annotation, the extensions method returns an array of registered extensions that are stored in @extensions.

  # Extension modules registered on this class and all superclasses.
  # def extensions
  #   if superclass.respond_to?(:extensions)
  #     (@extensions + superclass.extensions).uniq
  #   else
  #     @extensions
  #   end
  # end


use method Rack::Builder
 
use Rack::Auth::Basic do |username, password|
  username == 'admin' && password == 'secret'
end