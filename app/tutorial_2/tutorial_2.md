In this tutorial, we will look at different styles of sinatra app, sinatra extension system, and sinatra middlware. You may find that the sections "Rack Middleware", "Sinatra::Base - Middleware, Libraries, and Modular Apps" and "Scopes and Binding" in sinatra README may help to understand the topic.

In tutorial_1 we learned the basic form of sinatra apps: require the sinatra library and define routes directly in the same file. This is referred to as the "classic" style (see classic.rb). The other style is called "modular" style (see modular.rb).

Let's see an example of a modular app. In modular.rb, first Sinatra::Base is imported by `require 'sinatra/base'`. We define our app inside the Modular class, which is a subclass of Sinatra::Base. When subclassing `Sinatra::Base.inherited` is triggered and it calls the `subclass.reset!`. Note `subclass.reset!` is calling the inherited `Sinatra::Base.reset!`. Even the subclass has its own reset! method it won't be called because the content of the subclass is empty at this point. The `inherited` method then calls `super` which triggers the `inherited` method on the super class if there is one. In the case of our Modular class, it inherits from Sinatra::Base, which doesn't inherit from other classes, so the the super in the `inherited` method does not do anything. If another app Modular2 inherits from class AnotherClass that in turn inherits from Sinatra::Base, then the `inherits` method on Sinatra::Base would first reset AnotherClass; after AnotherClass is defined, Modular2 is reset by calling AnotherClass.reset!. 

```ruby
  def inherited(subclass)
    subclass.reset!
    super
  end
```

Now let's see what does `reset!` do. As the name suggests it resets everything and make current app a blank state. This is important because Sinatra::Base can be the super class of a number of modular apps or middleware. We know the `set` method defines settings on the app's singleton class, so settings are unique for each app; however, as we will see in the next tutorial, instance variables like @routes are defined on Sinatra::Base's singleton class,
so multiple apps subclassing from Sinatra::Base may share states, which we don't want. We will explain what those instance variables mean in later tutorials. For now knowing `reset!` empty them is enough.

```ruby
  attr_reader :routes, :filters, :templates, :errors

  # Removes all routes, filters, middleware and extension hooks from the
  # current class (not routes/filters/... defined by its superclass).
  def reset!
    @conditions     = []
    @routes         = {}
    @filters        = {:before => [], :after => []}
    @errors         = {}
    @middleware     = []
    @prototype      = nil
    @extensions     = []

    if superclass.respond_to?(:templates)
      @templates = Hash.new { |hash,key| superclass.templates[key] }
    else
      @templates = {}
    end
  end
```

We continue to look at the route definition in modular.rb. We define routes as instance methods inside the Modular class. It makes perfect sense because the route definition methods like `get` are defined as class methods on Sinatra::Base, so they are available in the class scope on the Modular. 

Next let's see how to start a modular app. There are two ways. First we can use the `run!` method as we talked in tutorial_1 and just throw it in after the routes like this:

```ruby
require 'sinatra/base'
class Modular < Sinatra::Base
  get '/' do
    'Hello world!'
  end
  run!
end
```

Then `run!` will fire up a rack handler by calling its run method and pass in `self`, i.e. Sinatra::Base.

Second, we can use a ru file to start it. A ru file is also called the rackup file that is used to configure for example the rack middlware, mapping url to rack endpoints, and start the rack server etc. We will just use the very basic ru file for now. If you look at modular.ru, we just require the modular app we defined and call `Rack::Builder.run` with Sinatra::Base or Modular as the parameter. 

```ruby
require File.expand_path(File.dirname(__FILE__) + '/modular')
run Sinatra::Base
# or run Modular
```

Of course we can have a ru file for classic sinatra app like classic.ru.

Here it's a bit different from how we run a regular rack app. Normally a rack app is a class that has an instance method `call`.  handler would expect an instance of a rack app; when we run the rack app, we make a instance of the class and run it like this `run SomeRackApp.new`. In ru file we run the class like run Modular instead of the instance of the class. We will see why is that later in this tutorial.

Now we finish the definition of a modular app, and our conclusion is that the modular style apps have nothing to do with the Sinatra::Application. A modular app is self-contained in its own scope. As a contrast the classic style app delegates it's calls to Sinatra::Application, the subclass of Sinatra::Base.

As we discussed Sinatra::Application is split in two files. Let's list the full Sinatra::Application code here. Following code is in sinatra/lib/sinatra/main.rb, which we already discussed in detail in tutorial_1.

```ruby
  module Sinatra
    class Application < Base

      # we assume that the first file that requires 'sinatra' is the
      # app_file. all other path related options are calculated based
      # on this path by default.
      set :app_file, caller_files.first || $0

      set :run, Proc.new { $0 == app_file }

      if run? && ARGV.any?
        require 'optparse'
        OptionParser.new { |op|
          op.on('-x')        {       set :lock, true }
          op.on('-e env')    { |val| set :environment, val.to_sym }
          op.on('-s server') { |val| set :server, val }
          op.on('-p port')   { |val| set :port, val.to_i }
          op.on('-o addr')   { |val| set :bind, val }
        }.parse!(ARGV.dup)
      end
    end

    at_exit { Application.run! if $!.nil? && Application.run? }
  end
```

Following code is in sinatra/lib/sinatra/base.rb. Let's look at it in detail. `set :logging, Proc.new { ! test? }` determines whether or not to do logging based on result of the test? method. Note that development?, test?, production? are methods defined on Sinatra::Base and are delegated in the classic style sinatra apps.

```ruby
  # Execution context for classic style (top-level) applications. All
  # DSL methods executed on main are delegated to this class.
  #
  # The Application class should not be subclassed, unless you want to
  # inherit all settings, routes, handlers, and error pages from the
  # top-level. Subclassing Sinatra::Base is heavily recommended for
  # modular applications.
  class Application < Base
    set :logging, Proc.new { ! test? }
    set :method_override, true
    set :run, Proc.new { ! test? }

    def self.register(*extensions, &block) #:nodoc:
      added_methods = extensions.map {|m| m.public_instance_methods }.flatten
      Delegator.delegate(*added_methods)
      super(*extensions, &block)
    end
  end
```

The definitions of development?, test?, production? are pretty simple. The environment is another setting `set :environment, (ENV['RACK_ENV'] || :development).to_sym`, which will default to 'development' if ENV['RACK_ENV'] is not set. 

```ruby
  def development?; environment == :development end
  def production?;  environment == :production  end
  def test?;        environment == :test        end
```

`set :method_override, true` will determine whether the sinatra app will use `Rack::MethodOverride` as a middleware. What Rack::MethodOverride does is just detect the _method param passed in by browsers to support HTTP method like PUT and DELETE. 

`set :run, Proc.new { ! test? }` defines the run setting. As we have seen in sinatra/lib/sinatra/main.rb the line `set :run, Proc.new { $0 == app_file }` has already set the `run` setting; the run setting is set twice in two spots. And why Sinatra::Application is separated in two files in the first place? Users can do something like in classic_2.rb, which is also a classic sinatra app. The difference than classic.rb is that in classic_2.rb you have to do `include Sinatra::Delegator` and run the server by calling `Sinatra::Application.run!` explicitly. Let's look back at the Sinatra::Application in sinatra/lib/sinatra/main.rb. What it does is just parsing the command line arguments and run the server. So we can think sinatra/lib/sinatra/main.rb is just a convenient way of defining a sinatra app and get it running. Back to our original question, the reason that `run` is set twice is that they are used in different context. The `set :run, Proc.new { ! test? }` will be overridden if sinatra/lib/sinatra/main.rb is required after sinatra/lib/sinatra/base.rb, and by setting the `run` as true if it's not test environment, it will prevent another classic sinatra app from running.

Now let's see the `Sinatra::Applocation.register`. To summarize what it does, it gets the all public instance methods of the extension array passed to it and delegate them to the top level, i.e. defines instance methods on top level and delegate them to Sinatra::Application. Then it calls the `register` method of its super class Sinatra::Base shown below.

```ruby
  # Register an extension. Alternatively take a block from which an
  # extension will be created and registered on the fly.
  def register(*extensions, &block)
    extensions << Module.new(&block) if block_given?
    @extensions += extensions
    extensions.each do |extension|
      extend extension
      extension.registered(self) if extension.respond_to?(:registered)
    end
  end
```

The register method on Sinatra::Base basically extends all the extensions, i.e. add the instance methods of the extensions as class methods to Sinatra::Base. If any blocks are passed in to the register method, the methods defined inside the blocks are also added as class methods to Sinatra::Base. It then calls the `registered` method on each of the extensions as sort of callbacks. Note the self i.e. the current class is passed to the `registered` method. So if an extension defines a `registered` class method, it can do something with the current app like set some settings, define some routes etc. 

A sinatra app uses an @extension instance variable to store all the extensions that are used in the current app. `extension` method gets all its super classes' extensions including its own extensions, which means all extensions used by super classes are added as class methods to the current app.

```ruby
  # Extension modules registered on this class and all superclasses.
  def extensions
    if superclass.respond_to?(:extensions)
      (@extensions + superclass.extensions).uniq
    else
      @extensions
    end
  end
```

Let's see what an sinatra extension looks like. A sinatra extension is just a module with sinatra DSL available to it. I take an example from sinatra documentation.

```ruby
require 'sinatra/base'

module Sinatra
  module LinkBlocker
    def block_links_from(host)
      before {
        halt 403, "Go Away!" if request.referer.match(host)
      }
    end
  end

  register LinkBlocker
end
```

This is how to use it in a classic sinatra app:

```ruby
require 'sinatra'
require 'sinatra/linkblocker'

block_links_from 'digg.com'

get '/' do
  "Hello World"
end
```

We can see that the register method in the extension will be evaluated when the extension is required by `require 'sinatra/linkblocker'`, and when it's required it will define `block_links_from` on the top level, and also define `block_links_from` as class methods on Sinatra::Base.

This is how to use it in a modular sinatra app:

```ruby
require 'sinatra/base'
require 'sinatra/diggblocker'

class Hello < Sinatra::Base
  register Sinatra::LinkBlocker

  block_links_from 'digg.com'

  get '/' do
    "Hello World"
  end
end
```

Here the `regisiter` method in the extension doesn't have effect to the modular app in that they are not in the same scope. So the modular app calls the register method on Sinatra::Base which defines `block_links_from` as class methods on Sinatra::Base.

Now we know the `register` and extensions, it's easier to understand a similar concept sinatra Helpers. 

```ruby
# Makes the methods defined in the block and in the Modules given
# in `extensions` available to the handlers and templates
def helpers(*extensions, &block)
  class_eval(&block)  if block_given?
  include(*extensions) if extensions.any?
end
```

As you may already guess `helpers` just add the instance methods on extensions as well as the methods defined in the block passed to helpers method call as instance methods to the current app so that they can be used in routing handlers, filters, templates and other helpers etc.

Let's explore the question we just asked: why we do `run Modular` instead of `run Modular.new` in the ru file. Let's see how an sinatra app acts as a rack app. By rack app I mean the class that defines the rack app. We know an instance of rack app responds to call method. Take our modular.rb as an example, rack handler would expect Modular.new responds to `call`. There are several call methods defined on Sinatra::Base. First one is an instance method that is used as the regular rack interface. It duplicates the instance of current app and call the `call!` method, which is the actual place requests are routed and response is generated. `call!` is a rather long method and we will explain it in detail in later tutorials. So our app does have a `call` instance method.

```ruby
  # Rack call interface.
  def call(env)
    dup.call!(env)
  end
```

Before we continue, why the current app needs to be duplicated before routes are processed and response is generated? We know `dup` method make a copy of all instance variables, so apparently we are trying to avoid messing up the instance variables here. How instance variables can be possibly messed up? 

I am not really sure at this time. This is when tests may help to figure out. So I remove the dup and run the test with `rack test`. The modified `call` method is like this:

```ruby
def call(env)
  call!(env)
end
```

There are two failures:

  1) Failure:
test_does_not_maintain_state_between_requests(BaseTest::TestSinatraBaseSubclasses) [/Users/zjia/code/sinatra-explained/sinatra/test/base_test.rb:42]:
<"Foo: new"> expected but was
<"Foo: discard">.

  2) Failure:
test_allows_custom_route_conditions_to_be_set_via_route_options(RoutingTest) [/Users/zjia/code/sinatra-explained/sinatra/test/routing_test.rb:941]:
Failed assertion, no message given.

Let's just look at the first failure. The last assertation in base_test.rb failed:

```ruby
  it 'does not maintain state between requests' do
    request = Rack::MockRequest.new(TestApp)
    2.times do
      response = request.get('/state')
      assert response.ok?
      assert_equal 'Foo: new', response.body
    end
  end
```

This is how TestApp defined:

```ruby
  class TestApp < Sinatra::Base
    get '/state' do
      @foo ||= "new"
      body = "Foo: #{@foo}"
      @foo = 'discard'
      body
    end
  end
```

The failure is cased because the @foo instance variable is shared between two requests. On the first request, @foo is assigned to "discard" after the request is processed; on the second request, since @foo has a value, it's not assigned to "new" again. Now we know the cause of the failure, it's clear that the `dup` method makes sure that each request has its own set of instance variables. 

There is another `call` class method on Sinatra::Base. Remember in the ru file, we run the app by something like `run Sinatra::Base`. The rack handler actually calls this `call` method. 

```ruby
  def call(env)
    synchronize { prototype.call(env) }
  end
```

It uses the `synchronize` method on Sinatra::Base. Mutex is imported by `require 'thread'`. We make an instance of Mutex as a class variable. The reason is that class variable is inherited by subclasses so all of them share the same @@mutex, which ensures that only one lock exists on the class hierarchy.

```ruby
  @@mutex = Mutex.new
  def synchronize(&block)
    if lock?
      @@mutex.synchronize(&block)
    else
      yield
    end
  end
```

We can see that if the lock? setting is true, then it will use Mutex#synchronize method to place a lock on every request to avoid race conditions among threads. If your sinatra app is multithreaded and not thread safe, or any gems you use is not thread safe, you would want to do `set :lock, true` so that only one request is processed at a given time. I don't have a good example for demonstration at the moment. Otherwise by default `lock` is false, which means the `synchronize` would yield to the block directly.

Inside the block, the class method call uses `prototype` method. 

```ruby
  # The prototype instance used to process requests.
  def prototype
    @prototype ||= new
  end
```

Inside the `prototype` method it calls the `new` method if our app isn't already initialized. The `Sinatra::Base.new` uses the `build` method to initialize a middleware stack that is used to process requests.   

```ruby
  # Create a new instance of the class fronted by its middleware
  # pipeline. The object is guaranteed to respond to #call but may not be
  # an instance of the class new was called on.
  def new(*args, &bk)
    build(*args, &bk).to_app
  end
```
  
We can see the the build method first initializes a Rack::Builder. 

```ruby
  # Creates a Rack::Builder instance with all the middleware set up and
  # an instance of this class as end point.
  def build(*args, &bk)
    builder = Rack::Builder.new
    builder.use Rack::MethodOverride if method_override?
    builder.use ShowExceptions       if show_exceptions?
    setup_logging  builder
    setup_sessions builder
    middleware.each { |c,a,b| builder.use(c, *a, &b) }
    builder.run new!(*args, &bk)
    builder
  end
```

To understand what the build method does, I list an abridged version of Rack::Builder here all at once.

```ruby
  module Rack
  
    class Builder

      def initialize(&block)
        @ins = []
        instance_eval(&block) if block_given?
      end
      
      def self.app(&block)
        self.new(&block).to_app
      end

      def use(middleware, *args, &block)
        @ins << lambda { |app| middleware.new(app, *args, &block) }
      end

      def run(app)
        @ins << app #lambda { |nothing| app }
      end
      
      def map(path, &block)
        if @ins.last.kind_of? Hash
          @ins.last[path] = self.class.new(&block).to_app
        else
          @ins << {}
          map(path, &block)
        end
      end

      def to_app
        @ins[-1] = Rack::URLMap.new(@ins.last)  if Hash === @ins.last
        inner_app = @ins.last
        @ins[0...-1].reverse.inject(inner_app) { |a, e| e.call(a) }
      end

    end
  end
```

As we know middlewares are in stack and process requests in layers. When Rack::Builder is initialized, it assigns an empty array to the instance variable @ins. If any block is given it's also evaluated on the Rack::Builder instance. Next if the setting `method_override?` is true then our app will use Rack::MethodOverride middleware by calling `builder.use Rack::MethodOverride`. By default, in classic form sinatra app the `method_override?` is enabled, while in modular form sinatra app, the setting is disabled. The `use` method basically wraps the `middleware.new` in a proc and lazy evaluates the initialization of the middleware it uses. If any arguments or block are passed to the `use`, it will be passed to the middleware initialization process. Then if the `show_exceptions?` setting is true then we use the ShowExceptions middleware defined in `sinatra/lib/sinatra/showexceptions.rb`. By default :show_exceptions is true in development mode.

Note here `builder.use ShowExceptions if show_exceptions?` is calling Rack::Builder#use. There is also a `use` method on Sinatra::Base

```ruby
  def use(middleware, *args, &block)
    @prototype = nil
    @middleware << [middleware, args, block]
  end
```  
  
So Sinatra::Base.use collects an array of [middleware, args, block] and store it in @middleware. 

Then we come to this line: `middleware.each { |c,a,b| builder.use(c, *a, &b) }`. For each of the middleware in the @middleware we call Rack::Builder#use to use it. The question is instead of using Rack::Builder#use directly, why do we have an additional step? This is because when we use a new middleware in our sinatra app we want to re-initialize our app so the middleware stack can be rebuilt without restarting the app.

If the logging setting is true, then it will use the Rack::CommonLogger middleware to generates logs. Further if a logging level is given in the logging setting it will be used to set `env['rack.logger']`

```ruby
  def setup_logging(builder)
    if logging?
      builder.use Rack::CommonLogger
      if logging.respond_to? :to_int
        builder.use Rack::Logger, logging
      else
        builder.use Rack::Logger
      end
    else
      builder.use Rack::NullLogger
    end
  end
```

setup_sessions just uses the Rack::Session::Cookie middleware if sessions setting is enabled.

```ruby
  def setup_sessions(builder)
    return unless sessions?
    options = { :secret => session_secret }
    options.merge! sessions.to_hash if sessions.respond_to? :to_hash
    builder.use Rack::Session::Cookie, options
  end
```

Next `builder.run new!(*args, &bk)` calls the `new!` method, which is an alias method of original `new` method. It just create an instance of the current app without building the middleware stack. So the parameter passed to `builder.run` is an instance of of our app. 

```ruby
  # Create a new instance without middleware in front of it.
  alias new! new unless method_defined? :new!
```

The `run` method just adds our app instance to the @ins array, and then it returns the `builder` variable containing the @ins array to the `Sinatra::Base.new` method. `Sinatra::Base.new` calls `to_app` on the returned `builder` to build the middleware calling stack using the @ins array. Here is how `to_app` works. Suppose we have the @ins has middleware proc array [m1, m2, m3]. It first check whether the last element of the @ins array, i.e., our app instance is a hash. Let's assume it's not for now. We will see a bit later how it can be a hash. If it's not a hash, we just get the last element as the inner_app, and for the remaining middleware, we do `@ins[0...-1].reverse.inject(inner_app) { |a, e| e.call(a) }`. What does this do is reversing the middleware sequence, and generating a call something like m1.call(m2.call(m3.call(inner_app))). When this is executed, middleware are initialized in sequence, setting their inner app, and the outermost middleware instance is returned. We can see example outputs of Sinatra::Base.build and Sinatra::Base.new in middleware_stack.rb.

Now let's briefly see how the last element of @ins can be a hash. If in the ru file we have something like

```ruby
use Middleware1
Rack::Builder.app do
  map '/' do
    use Middleware2
    run Heartbeat
  end
end
```

The `Rack::Builder.app` take a block and initialize a Rack::Builder instance, evaluate the block on Rack::Builder, and convert the Rack::Builder instance to a middleware stack with the `to_app` method. Let's see the `Rack::Builder#map` method inside the block. It takes a path parameter and a block. If first check whether the last element is a hash. In our case it is not. If it's not it will make add a empty hash as the last element of @ins, and then call itself `map(path, &block)`. Now the last element is a hash, so it will key on the path parameter and the value is a middleware stack by evaluating the block on Rack::Builder and call `to_app`. 

Back to the ru file, it uses Middleware1 at the top, and the remaining is a just a hash. Then back to the `to_app` method. If the last element of @ins is a hash, it will initialize a Rack::URLMap, which basically does the routing directly in the ru file based on the key of the hash, i.e. the path parameter.

In conclusion the `builder` method ends up with a array with an instance of current app as the last element; `Sinatra::Base.new` ends up with a middleware stack, and the Sinatra::Base.call ends up to `Sinatra::Base#call`.

In the next tutorial, let's see how routing is done.