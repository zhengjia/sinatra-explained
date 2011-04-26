We will start the tutorials with a simple four-line sinatra app as shown at the very bottom. The question we are going to solve in the first tutorial is: what will happen when we require sinatra? 

To get a hint, looking at the four line app, apparently the get method is available in the context of the current app. So some methods are "imported" from sinatra to the current app. To get another hint, we create a file which only has one line: `require 'sinatra'`, and run it. We can see a server starts!

This brings out two areas we are going to cover: method lookup and and server startup in sinatra.

First let's see where the get method is defined. get is a class method of Sinatra::Base. Since it's available at the top level in the current app, it can either be a class method or an instance method defined at the top level main object. Let's see which case it is and how get becomes available in the current app. (In case you don't know, methods defined on the top level becomes private instance methods of Object class; class methods defined on top level become singleton methods on the main object, which is an instance of Object.)

If you look at `sinatra/lib/sinatra.rb`, which is the file that is required by the first line `require 'sinatra'`

```ruby
  libdir = File.dirname(__FILE__)
  $LOAD_PATH.unshift(libdir) unless $LOAD_PATH.include?(libdir)
  
  require 'sinatra/base'
  require 'sinatra/main'
  
  enable :inline_templates
```

First two lines add sinatra/lib to $LOAD_PATH. Then `sinatra/lib/sinatra/base.rb`, which is the file contains majority of the code, and `sinatra/lib/sinatra/main.rb` are required. `sinatra/lib/sinatra/base.rb` has a lot of classes and modules defined: `Sinatra::Base`, `Sinatra::Request`, `Sinatra::Response`, `Sinatra::NotFound`, `Sinatra::Helpers`, `Sinatra::Templates`, `Sinatra::Application`, and `Sinatra::Delegator`; among them `Sinatra::Application` is a subclass of `Sinatra::Base`, and it is opened and further defined by `sinatra/lib/sinatra/main.rb`. 

By looking at the top level code, the whole sinatra/base is inside the Sinatra module, so it can be safely passed at this step because it is in it's own scope and can't be automatically hooked to our app. There are two other possibilities: `enable :inline_templates` on the last line of `sinatra/lib/sinatra.rb`, and `include Sinatra::Delegator` on the last line of `sinatra/lib/sinatra/main.rb`. If you grep on 'def enable', it's a class methods of Sinatra::Base. It looks like it has nothing to do with the get method. The only hope is this line: `include Sinatra::Delegator`. We can see :get is passed in as a parameter to the `delegate` method, which looks promising. Let's look at this module in detail. 

Sinatra::Delegator is a module defined in Sinatra::Base:

```ruby
 # Sinatra delegation mixin. Mixing this module into an object causes all
 # methods to be delegated to the Sinatra::Application class. Used primarily
 # at the top-level.
  module Delegator #:nodoc:
    def self.delegate(*methods)
      methods.each do |method_name|
        eval <<-RUBY, binding, '(__DELEGATE__)', 1
          def #{method_name}(*args, &b)
            ::Sinatra::Delegator.target.send(#{method_name.inspect}, *args, &b)
          end
          private #{method_name.inspect}
        RUBY
      end
    end
  
    delegate :get, :patch, :put, :post, :delete, :head, :options, :template, :layout,
             :before, :after, :error, :not_found, :configure, :set, :mime_type,
             :enable, :disable, :use, :development?, :test?, :production?,
             :helpers, :settings
  
    class << self
      attr_accessor :target
    end
  
    self.target = Application
  end
```

When I try to find the executing path of an app or library, I'd look at the hook methods like `Module#included`, `Class#inherited`. But Sinatra::Delegator doesn't have any of those. We know when include 'SomeModule' is called, all instance methods of SomeModule are included in the calling class. At a glance it seems there is no instance methods in Sinatra::Delegator, which is false. I would then look at code that's run immediately, i.e., code not in method definitions. Here the delegate method is run when `require 'sinatra/base'` is called. The delegate method defines on Sinatra::Delegator a bunch of private instance methods including the get method. Note that the scope inside `self.delegate` is still the Delegator class; the newly defined methods become instance methods of Sinatra::Delegator, instead of class methods of `Sinatra::Delegator`. When include Sinatra::Delegator is called these instance methods are included to the top level of current app. This answers the question we asked: the `get` method is available to the current app as an instance method.

The technique used here is to dynamically define a new set of instance methods, include them as instance methods to the current app, and then delegate calls to them to the corresponding class methods on `Sinatra::Delegator.target`, i.e. `Sinatra::Application`. Since Sinatra::Application is a subclass of Sinatra::Base, it has all the class methods of Sinatra::Base. If you are not familiar with the eval syntax, here is a good reference http://olabini.com/blog/2008/01/ruby-antipattern-using-eval-without-positioning-information/. Otherwise the syntax in the Delegator module is straitforward. The reason we have the Sinatra::Delegator module is that it picks some of the class methods from Sinatra::Base and make them available to the current app. Finally the source code annotation at the top of the Delegator module makes sense, and we know why get is available in the current app. We will explain other delegated methods defined here in later tutorials as we encounter them.

After we define a route with the get method, the server starts. Let's see how that happens. There are a lot of default settings going on and we only look at some of them for now.

It all starts with the `at_exit` method in `sinatra/lib/sintra/main.rb`. at_exit is a `Kernal` method that runs the block when the current app exits. 

```ruby
  require 'sinatra/base'
  
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
  
  include Sinatra::Delegator
```

In `sinatra/lib/sintra/main.rb`, it first calls `require 'sinatra/base'` to make sure Sinatra::Base is available to it. We need to explain two methods: `set` and `caller_files``. set is a class method on Sinatra::Base and is also delegated from current app to Sinatra::Application.

```ruby
    # Sets an option to the given value.  If the value is a proc,
    # the proc will be called every time the option is accessed.
    def set(option, value=self, &block)
      raise ArgumentError if block && value != self
      value = block if block
      if value.kind_of?(Proc)
        metadef(option, &value)
        metadef("#{option}?") { !!__send__(option) }
        metadef("#{option}=") { |val| metadef(option, &Proc.new{val}) }
      elsif value == self && option.respond_to?(:each)
        option.each { |k,v| set(k, v) }
      elsif respond_to?("#{option}=")
        __send__ "#{option}=", value
      else
        set option, Proc.new{value}
      end
      self
    end
```

set method is interesting but a bit complicated. There are several forms to use the set method, which helps to explain it. First one is just `set :some_option, "some_value"`. It will just be translated to `set option, Proc.new{value}`, which is exactly the second form. For the second form, it open the singleton class of Sinatra::Base and define three new methods there using the `metadef` private class method of Sinatra::Base. The three class methods are used as setter, getter, and question mark method. The getter is lazy evaluated, meaning content of the block is used as the method body and isn't called until the getter is called. The question mark method uses double bang to get the true/false value based on the truth of the result of the getter method. The third form is that when the setter is already defined by previous calls to the set method, then when we use set method in the first form it doesn't go through the second form and defines the getter setter and question mark element again; instead it just used the already defined setter.

```ruby
    def metadef(message, &block)
      (class << self; self; end).
        send :define_method, message, &block
    end
```

As an example, if we have `set :inline_templates, true`, then we will have three class methods available on Sinatra::Base: `inline_templates` which returns true, `inline_templates?` which returns true also, and `inline_templates=` which sets inline_templates to a new value. We will look at how the set method is typically used in later tutorials.

The last form of set method accepts a hash and split the hash to set individual element. For example, `set :a => 'value1', :b => 'value2'` equals to two calls: `set :a => 'value1'`, and `set :b => 'value2'`

Finally the set method returns self, which is Sinatra::Base so other methods can be chained to set method. However I've never seen any cases this can be useful.

Then we come to the `caller_files` and it's associated code. caller_files is a public class method of Sinatra::Base. `CALLERS_TO_IGNORE` is a constant that defines the patterns that should be ignored from result of the `Kernel#caller`. The first regular expression is kind of special. It matches `/sinatra.rb`, `/sinatra/base.rb`, `/sinatra/main.rb`, and `/sinatra/showexceptions.rb`. `RUBY_IGNORE_CALLERS` is added to CALLERS_TO_IGNORE if it's available. caller_locations calls the Kernel#caller method, which basically returns the calling stack in the format like `/Users/zjia/code/ruby_test/caller/caller.rb:3:in \`&ltmain&gt'`. The `caller(1)` will ignore the top level of the calling stack, i.e., the `sinatra/lib/sinatra/main.rb` itself. Regex `/:(?=\d|in )/` matches a colon preceding a number or a string 'in', but not including the number or 'in'. For example in `/Users/zjia/code/ruby_test/caller/caller.rb:3:in \`&ltmain&gt'` it will match the two colons. Then `/Users/zjia/code/ruby_test/caller/caller.rb:3:in \`\&ltmain&gt'` is splitted at the two colons and [0,2] get the first two elements of the array returned by the split, i.e., the pure file location and the line number. Finally the reject method uses the patterns in CALLERS_TO_IGNORE to remove the unwanted lines of the calling stack. The `caller_files` further removes the line number and returns only the pure file location. 

We return to the line `set :app_file, caller_files.first || $0`. As the source annotation says, `caller_files.first` is the file that calls `require 'sinatra'`. As we talked, when `require 'sinatra'` is called, it requires sinatra/lib/sinatra.rb, which requires sinatra/lib/sinatra/main.rb. sinatra/lib/sinatra.rb and /sinatra/lib/sinatra/main.rb are in the ignored patterns so they are removed from caller_files. Then the first element in the array should be the one that contains the `requires 'sinatra'`. Here I think `caller(1)` in caller_locations is not necessary because the top level of the calling stack sinatra/lib/sinatra/main.rb is in the ignored pattern. If caller_files is an empty array, which is possible when the file is located in the ignored paths, then the current running file stored in $0 is set as the the `app_file`. `app_file` stores the root path of the sinatra project and locations of other files are based on it.

```ruby
  CALLERS_TO_IGNORE = [ # :nodoc:
    /\/sinatra(\/(base|main|showexceptions))?\.rb$/, # all sinatra code
    /lib\/tilt.*\.rb$/,                              # all tilt code
    /\(.*\)/,                                        # generated code
    /rubygems\/custom_require\.rb$/,                 # rubygems require hacks
    /active_support/,                                # active_support require hacks
    /bundler(\/runtime)?\.rb/,                       # bundler require hacks
    /<internal:/                                     # internal in ruby >= 1.9.2
  ]

  # add rubinius (and hopefully other VM impls) ignore patterns ...
  CALLERS_TO_IGNORE.concat(RUBY_IGNORE_CALLERS) if defined?(RUBY_IGNORE_CALLERS)

  # Like Kernel#caller but excluding certain magic entries and without
  # line / method information; the resulting array contains filenames only.
  def caller_files
    caller_locations.
      map { |file,line| file }
  end

  # Like caller_files, but containing Arrays rather than strings with the
  # first element being the file, and the second being the line.
  def caller_locations
    caller(1).
      map    { |line| line.split(/:(?=\d|in )/)[0,2] }.
      reject { |file,line| CALLERS_TO_IGNORE.any? { |pattern| file =~ pattern } }
  end
```  

Next line `set :run, Proc.new { $0 == app_file }` defines three singleton methods on Sinatra::Base. The `run` and `run?` methods do the same thing: if the current running file is the `app_file` we just set, i.e. the current file does `require 'sinatra'`, then it will return true. `run=` setter is also defined on Sinatra::Base, but I don't think it's used. In fact only `run?` is used to determine whether to run the app now or not. The reason to have `run?` is that it's possible that one app can be used as a middleware and should not be run when it's required.

Now we come to the option parsing. If the current app is supposed to be run and any arguments are passed in to run it, sinatra will set those settings based on the passed in arguments. You can refer to the full list of the available settings in the "Available Settings" section in sinatra doc. The option parsing is pretty standard and I will just include a reference here http://ruby-doc.org/stdlib/libdoc/optparse/rdoc/classes/OptionParser.html

Finally we come to `at_exit { Application.run! if $!.nil? && Application.run? }`. Let's look at the run! method. It's defined as a class method of Sinatra::Base. It can optionally accept a hash of options and set them on Sinatra::Base. 

```ruby
  # Run the Sinatra app as a self-hosted server using
  # Thin, Mongrel or WEBrick (in that order)
  def run!(options={})
    set options
    handler      = detect_rack_handler
    handler_name = handler.name.gsub(/.*::/, '')
    puts "== Sinatra/#{Sinatra::VERSION} has taken the stage " +
      "on #{port} for #{environment} with backup from #{handler_name}" unless handler_name =~/cgi/i
    handler.run self, :Host => bind, :Port => port do |server|
      [:INT, :TERM].each { |sig| trap(sig) { quit!(server, handler_name) } }
      set :running, true
    end
  rescue Errno::EADDRINUSE => e
    puts "== Someone is already performing on port #{port}!"
  end
```

Then it tries to get a rack compatible server to run the app by calling `detect_rack_handler`. detect_rack_handler uses either the default array defined by `set :server, %w[thin mongrel webrick]`, or the server option passed in by arguments when running the app, as the parameter to `Rack::Handler.get`. A set of server handlers are predefined by rack to abstract the difference of servers so any rack server can be just run by calling `some_handler.run(myapp)`. You can also define your customized server handler. We will see an example of handler below. As soon as a server handler is found Rack::Handler.get will return it. Assuming we are running `Rack::Handler.get('thin')` and let's see what does it do. 

```ruby
  def detect_rack_handler
    servers = Array(server)
    servers.each do |server_name|
      begin
        return Rack::Handler.get(server_name.downcase)
      rescue LoadError
      rescue NameError
      end
    end
    fail "Server handler (#{servers.join(',')}) not found."
  end
```

@handlers is an hash contains all the server handlers defined by rack. Handlers are added to @handlers by the register method.

```ruby
  def self.get(server)
    return unless server
    server = server.to_s
  
    if klass = @handlers[server]
      obj = Object
      klass.split("::").each { |x| obj = obj.const_get(x) }
      obj
    else
      try_require('rack/handler', server)
      const_get(server)
    end
  end

  def self.register(server, klass)
    @handlers ||= {}
    @handlers[server] = klass
  end
```  

Following is how register is called and a list of all handlers

```ruby 
  register 'cgi', 'Rack::Handler::CGI'
  register 'fastcgi', 'Rack::Handler::FastCGI'
  register 'mongrel', 'Rack::Handler::Mongrel'
  register 'emongrel', 'Rack::Handler::EventedMongrel'
  register 'smongrel', 'Rack::Handler::SwiftipliedMongrel'
  register 'webrick', 'Rack::Handler::WEBrick'
  register 'lsws', 'Rack::Handler::LSWS'
  register 'scgi', 'Rack::Handler::SCGI'
  register 'thin', 'Rack::Handler::Thin'
```

In the case of Rack::Handler.get('thin'), `@handlers[server]` is the string `'Rack::Handler::Thin'`. `klass.split("::").each { |x| obj = obj.const_get(x) }` loop through modules Rack to Handler and then to Thin class in `rack/handler/thin.rb`, which is defined as following:

```ruby
  require "thin"
  require "rack/content_length"
  require "rack/chunked"
  
  module Rack
    module Handler
      class Thin
        def self.run(app, options={})
          server = ::Thin::Server.new(options[:Host] || '0.0.0.0',
                                      options[:Port] || 8080,
                                      app)
          yield server if block_given?
          server.start
        end
      end
    end
  end
```

The thin handler is a class and it has a single class method. When run is called it creates a instance of `::Thin::Server`, yield to the app and let it do something, and starts the thin server with `server.start`.

Let's return to the `run!` method on Sinatra::Base. It outputs the information about the server it got and calls the `run` method on the handler, passing in the default binding(0.0.0.0) and port(4567) and a block. Inside the block, we specify that two signal that can end the server by calling the `quit!` method on Sinatra::Base, and then set the `running` to true which indicate the server is running. Then the control returns to run method on the Thin handler. It starts the server instance for handling requests.

```ruby
  handler.run self, :Host => bind, :Port => port do |server|
    [:INT, :TERM].each { |sig| trap(sig) { quit!(server, handler_name) } }
    set :running, true
  end
```  

```ruby
  def quit!(server, handler_name)
    # Use Thin's hard #stop! if available, otherwise just #stop.
    server.respond_to?(:stop!) ? server.stop! : server.stop
    puts "\n== Sinatra has ended his set (crowd applauds)" unless handler_name =~/cgi/i
  end
```  

This concludes our first tutorial. There are still some topics need to be talked about the server, like how requests are picked up by the server and passed to our app. We will resolve this in later tutorials. In tutorial_2.rb, we will look at high level architecture of sinatra apps and the code that support it, including other forms of sinatra apps, sinatra extensions and middleware.