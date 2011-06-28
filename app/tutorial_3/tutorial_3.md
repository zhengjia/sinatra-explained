The question we are going to look at in this tutorial is: how routing is handled in Sinatra. First we need a little background on routing conditions. A routing condition means that a route is only picked if the condition is met. For example, we have a route like:

```ruby
get '/', :host_name => /^admin\./ do
  "Admin Area, Access denied!"
end
```

We can see we use a hash `:host_name => /^admin\./` to define a condition. `host_name` is actually a method and we use the name of the method as the key a regular expression that represents a route as the value. The route '/' will only be picked if the host name starts with "admin". You can refer to the "Conditions" section in the sinatra README for further information. Don't worry about the meaning of the `host_name` condition. You just need to know the concept of routing conditions. We will explain host_name below in this tutorial.

Quite a few related methods are covered in this tutorial and routing itself is rather complex. Now let's get started. We use the same sinatra app as in tutorial_1/classic.rb.

We know `get '/'` defines a route to the root path. Let's see the get method:

```ruby
  # Defining a `GET` handler also automatically defines a `HEAD` handler.
  def get(path, opts={}, &block)
    conditions = @conditions.dup
    route('GET', path, opts, &block)
    @conditions = conditions
    route('HEAD', path, opts, &block)
  end
```

The get method takes a path, an optional condition hash and a block. The questions we have with this method are: 1. what is the instance variable @conditions? 2. why it's duplicated(@conditions.dup) and then set back(on line 4)? 3. what does the `route` method do?

Let's grep on @conditions, and we find the following `condition` method relevant. The `condition` method takes a block as a proc and add it to @conditions, an array of procs. With this information, although we don't know exactly how, we can guess that `route('GET', path, opts, &block)` will modify @conditions, and we want to use the same @conditions that we used to for 'GET' to define 'HEAD', so we need to set it back. Initially both in classic and modular sinatra app, the @conditions is set to an empty array by `Sinatra::Base.reset!`.

```ruby
  # Add a route condition. The route is considered non-matching when the block returns false.
  def condition(&block)
    @conditions << block
  end
```

Similarly other http methods are defined.

```ruby
  def put(path, opts={}, &bk)     route 'PUT',     path, opts, &bk end
  def post(path, opts={}, &bk)    route 'POST',    path, opts, &bk end
  def delete(path, opts={}, &bk)  route 'DELETE',  path, opts, &bk end
  def head(path, opts={}, &bk)    route 'HEAD',    path, opts, &bk end
  def options(path, opts={}, &bk) route 'OPTIONS', path, opts, &bk end
  def patch(path, opts={}, &bk)   route 'PATCH',   path, opts, &bk end
```

`route` is a private instance method of Sinatra::Base. It takes a HTTP verb("GET", "POST" etc) and the same parameters passed to the get method:

```ruby
  def route(verb, path, options={}, &block)
    # Because of self.options.host
    host_name(options.delete(:host)) if options.key?(:host)
    enable :empty_path_info if path == "" and empty_path_info.nil?

    block, pattern, keys, conditions = compile! verb, path, block, options
    invoke_hook(:route_added, verb, path, block)

    (@routes[verb] ||= []).
      push([pattern, keys, conditions, block]).last
  end
```

Before we delve into the route method, let's look at the methods it uses.

`Sinatra::Base.host_name` is a private method that defines a routing condition by using the `condition` method we just discussed. If you look at the source code annotation for the condition method: "The route is considered non-matching when the block returns false", we can know that if the block { pattern === request.host } returns true, then the condition is considered satisfied, and vice versa. In the block, it references request, which is is an attr_accessor on Sinatra::Base, and an instance of the `Sinatra::Request < Rack::Request`. We will look at Sinatra::Request in detail in other tutorials. `request.host` is the host part without port number of user's requested url. As an simple example, if we specify a host option in the get like `get '/', :host => 'test.smokyapp.com'`, it will only match the route '/' if the request is something like http://test.smokyapp.com. It will not match '/' if the request is http://test2.smokyapp.com. So when `host_name` is called with a regular expression as the path pattern, proc{ pattern === request.host } will be added to the @conditions.

```ruby
  # Condition for matching host name. Parameter might be String or Regexp.
  def host_name(pattern)
    condition { pattern === request.host }
  end
```

Next is the enable method. As we have seen in tutorial 1, it's a class method in Sinatra::Base and is delegated in Sinatra::Delegator. It's just a convenient method to the `set` method that sets a array of settings as true.

```ruby
  # Same as calling `set :option, true` for each of the given options.
  def enable(*opts)
    opts.each { |key| set(key, true) }
  end
```

One interesting thing to note is that in sinatra/sinatra.rb, `enable :inline_templates` is called so it defines `inline_templates=` on the singleton class of Sinatra::Base, but Sinatra::Base also defines `inline_templates=` class method itself. As we know class methods are actually methods defined on class's singleton class. The `inline_templates=` defined by Sinatra::Base will overwrite the one defined by `enable :inline_templates`.

Now we know what does the enable method do, we come back to the route method. We've already seen host_name defines a routing condition. Then it calls `enable :empty_path_info`, i.e., set empty_path_info to true to if the path param is an empty string and if `empty_path_info` setting is not already true. Note `set :empty_path_info, nil` is called Sinatra::Base's class definition, so by default empty_path_info is nil. empty_path_info is set to true the first time you give give an empty string as the path param. Then as we can see later when routing is processed if empty_path_info is true it will use '/' as the route.

Next the Sinatra::Base.compile! is called with all the params passed to route.

```ruby
  def compile!(verb, path, block, options = {})
    options.each_pair { |option, args| send(option, *args) }
    method_name = "#{verb} #{path}"

    define_method(method_name, &block)
    unbound_method          = instance_method method_name
    pattern, keys           = compile(path)
    conditions, @conditions = @conditions, []
    remove_method method_name

    [ block.arity != 0 ?
        proc { unbound_method.bind(self).call(*@block_params) } :
        proc { unbound_method.bind(self).call },
      pattern, keys, conditions ]
  end
```

You may wonder what does the `options.each_pair` do. For each element of the option hash, i.e. the condition hash like `:host_name => /^admin\./`, it calls the method with the key as the method name and the value as the parameters to the method. It turns out it's one usage of the `set` method. Take an example from Sinatra doc:

```ruby
set(:probability) { |value| condition { rand <= value } }
get '/win_a_car', :probability => 0.1 do
  "You won!"
end
```

Here we first use set to define a routing condition named probability. A method named `probability` is defined on the singleton class on Sinatra::Base. When we pass the :probability => 0.1 as the option to `get`, 0.1 is passed in as the value parameter to the block, and then a condition is set by adding the { rand <= 0.1 } to the @conditions. Using set with a block that contains a condition makes the condition reusable.

Next it defines a method with method names like "GET /" and with the method body as the block passed in. The method are defined as class methods on Sinatra::Base. The line unbound_method = instance_method method_name is interesting. Before I see it I only know instance_method can extract an unbound method from a class's instance methods. But it actually just finds and extracts a method from the current scope, no matter it's an instance method or a class methods. Here we extract the method that's just defined to the local variable unbound_method. The method is later removed with remove_method method_name. Before we look into why it does that, let's first look at the `compile` method. The `compile(path)` returns an array with two elements path and keys. As we can see path and keys are return from the `compile` method and are stored as part of the route information. Let's see what does `compile` do in detail.

According to the method, the path can be of 4 forms: it responds to to_str, indicating it's a string, responds to keys and match, responds to names and match, and responds to match only, indicating it's a regular expression.

First let's look at the most common case where path is a string. To know what does the compile method do, it's good to see some examples first. We know compile accepts a path param, and return array of pattern and keys. Let's pop up irb and see four examples:

ruby-1.9.2-p180 :002 > Sinatra::Base.send(:compile, "/")
 => [/^\/$/, []]
ruby-1.9.2-p180 :003 > Sinatra::Base.send(:compile, "/a*")
 => [/^\/a(.*?)$/, ["splat"]]
ruby-1.9.2-p180 :004 > Sinatra::Base.send(:compile, "/a/:boo")
 => [/^\/a\/([^\/?#]+)$/, ["boo"]]
ruby-1.9.2-p180 :005 > Sinatra::Base.send(:compile,"/a/:boo/*.pdf")
 => [/^\/a\/([^\/?#]+)\/(.*?)\.pdf$/, ["boo", "splat"]]

If you haven't already realize it, the returned array contains a regular expression as the pattern that will be used to match a request url to a route, and keys are the name of the params. We can verify it with the last example. /^\/a\/([^\/?#]+)\/(.*?)\.pdf$/ matches requests start with '/a/' and then all string that's not in '\/?#' as the param[:boo] and then a '/' preceding any string preceding '.pdf' as the param[:splat].

Let's see how the matched string in a url is stored into keys. The regular expression /((:\w+)|[\*#{special_chars.join}])/ is the key here. It equals to /((:\w+)|[\*.+()$])/, which will match a word starting with semicolon, or any of the following punctuations '*.+()$'. gsub tries to match the string as many times as it can. If the match is *, like the case when path is "/a*", then 'splat' is added to the key, and * is substituded for (.*?). If any of the special_chars is matched, then the key is not changed, and pattern is the escaped special_char. Otherwise, the key is the matched word without the starting semicolon, and the matched word is substituted for ([^/?#]+). Notice that if there are multiple matches for *, they are added in order to param[:splat]. Examples from sinatra doc:

```ruby
get '/say/*/to/*' do
  # matches /say/hello/to/world
  params[:splat] # => ["hello", "world"]
end

get '/download/*.*' do
  # matches /download/path/to/file.xml
  params[:splat] # => ["path/to/file", "xml"]
end
```

In the case of path is a regular expression, it will just return the regular expression itself as the first element 'pattern' of the array, and the empty array 'keys' as the second element of the array.

```ruby
  def compile(path)
    keys = []
    if path.respond_to? :to_str
      special_chars = %w{. + ( ) $}
      pattern =
        path.to_str.gsub(/((:\w+)|[\*#{special_chars.join}])/) do |match|
          case match
          when "*"
            keys << 'splat'
            "(.*?)"
          when *special_chars
            Regexp.escape(match)
          else
            keys << $2[1..-1]
            "([^/?#]+)"
          end
        end
      [/^#{pattern}$/, keys]
    elsif path.respond_to?(:keys) && path.respond_to?(:match)
      [path, path.keys]
    elsif path.respond_to?(:names) && path.respond_to?(:match)
      [path, path.names]
    elsif path.respond_to? :match
      [path, keys]
    else
      raise TypeError, path
    end
  end
```

The other two cases are kind of special. They are used for paths that are defined with custom classes. If you look at test/routing_test.rb, you can find a class RegexpLookAlike. The objects of this class respond to match and keys method. It also has a MatchData class. MatchData defines the object returned by the match method, and the capture instance method converts the matches to an array. Refer to http://ruby-doc.org/core/classes/MatchData.html for further information.

You can define a custom class like RegexpLookAlike and the path like RegexpLookAlike.new will be a valid path parameter. In the case of RegexpLookAlike, RegexpLookAlike.new will be the path, and  ["one", "two", "three", "four"] will be the keys.

```ruby
  class RegexpLookAlike
    class MatchData
      def captures
        ["this", "is", "a", "test"]
      end
    end

    def match(string)
      ::RegexpLookAlike::MatchData.new if string == "/this/is/a/test/"
    end

    def keys
      ["one", "two", "three", "four"]
    end
  end
```

The last case which path responds to name method is similar to this one.

After `compile` finishes, path and keys are returned to the `route` method and assigned to the corresponding variable. Now we get to the line `conditions, @conditions = @conditions, []`. We see here that the local variable `conditions` is a copy of @conditions, and @conditions is reset to empty array. We sure want the routing conditions to be independent of each route. Now we know why in the `get` method duplicates the @conditions because it's reset here and we want to use the same routing conditions for the `GET` and `HEAD`.

Next the method "GET /" that's just defined is removed. We could, for example, use the proc directly to define a route. For example, we can have a simplified `get` method:

```ruby
class Base
  class << self
    attr_accessor :routes
  end
  @routes = {}
  class << self
    def get path, &block
      @routes[path] = block
    end
  end
end

Base.get '/' do
  puts "hello world"
end

Base.routes.each_pair do |k, v|
  puts "Route #{k}:"
  puts v.call
end
```

This works fine. However if we add a helper, then the helper is undefined in `Base.get '/'`:

```ruby
class Base
  class << self
    attr_accessor :routes
  end
  @routes = {}

  def a_helper
    "a message from a_helper"
  end

  class << self
    def get path, &block
      @routes[path] = block
    end
  end

end

Base.get '/' do
  puts "hello world #{a_helper}"
end

Base.routes.each_pair do |k, v|
  puts "Route #{k}:"
  puts v.call
end
```

If we lazy evaluate it by using a unbound_method, then it works fine. Now we know why we define and then remove the `GET /` method.

```ruby
class Base
  class << self
    attr_accessor :routes
  end
  @routes = {}

  def a_helper
    "a message from a_helper"
  end

  class << self
    def get path, &block
      define_method "a_route", &block
      unbound_method = instance_method "a_route"
      @routes[path] = proc { unbound_method.bind(self).call }
    end
  end

end

Base.get '/' do
  puts "hello world #{a_helper}"
end

Base.routes.each_pair do |k, v|
  puts "Route #{k}:"
  puts Base.new.instance_eval &v
end
```

Since the unbound_method is an instance method, `unbound_method.bind(self)` binds to an instance of current class, and wrapped in a proc object with `call` method on it. When the proc is evaluated then the unbound_method is run.  If arguments are passed to the block, for example

get '/hello/:name' do |n|
  "Hello #{n}!"
end

*@block_params will be passed in as parameter. Note the @block_params is not available here, but that's fine because it's not evaluated yet.

The compile! method finishes and four pieces of information is returned to the`route` method: the route method which wrapped in a proc, route pattern, parameter keys, conditions which is an array of proc. The four pieces are assigned to variable block, pattern, keys, conditions respectively.

Let's see an example of the `compile!`. I use the sourcify gem https://github.com/ngty/sourcify to lookup the proc.
ruby-1.9.2-p180 :001 > require 'sinatra'
 => true
ruby-1.9.2-p180 :002 > require 'sourcify'
 => true
ruby-1.9.2-p180 :003 > arr = Sinatra::Base.send :compile!,'GET', '/', proc{"abc"}, :host_name => /admin/
 => [#<Proc:0x000001022fbf40@/Users/zjia/.rvm/gems/ruby-1.9.2-p180/gems/sinatra-1.2.3/lib/sinatra/base.rb:1165>, /^\/$/, [], [#<Proc:0x000001022fc558@/Users/zjia/.rvm/gems/ruby-1.9.2-p180/gems/sinatra-1.2.3/lib/sinatra/base.rb:1088>]]
ruby-1.9.2-p180 :004 > arr.first.to_source
 => "proc { unbound_method.bind(self).call }"
ruby-1.9.2-p180 :005 > arr.last.collect(&:to_source)
 => ["proc { pattern.===(request.host) }"]
ruby-1.9.2-p180 :006 >

Next let's look at the `invoke_hook` method. The first argument name is :route_added, and args is an array [verb, path, block]. What does `invoke_hook` do is to call the `extensions` method to get all extensions on the current app and its superclasses. For each of the extensions if the `route_added` method exists on the extension then it calls it as a callback method.

```ruby
  def invoke_hook(name, *args)
    extensions.each { |e| e.send(name, *args) if e.respond_to?(name) }
  end
```

Then the the `route` method add the array [pattern, keys, conditions, block] to the @routes hash which is keyed on the HTTP verb like 'GET', 'POST', 'HEAD' etc, and returns the [pattern, keys, conditions, block] as the result of the `route` method. With the same conditions a HEAD route is added.

Let's see an example of the routes added.

ruby-1.9.2-p180 :002 > get '/:action', :host_name => /^admin\./ do
ruby-1.9.2-p180 :003 >       "Admin Area, Access denied!"
ruby-1.9.2-p180 :004?>   end
 => [/^\/([^\/?#]+)$/, ["action"], [#<Proc:0x00000101b090d0@/Users/zjia/.rvm/gems/ruby-1.9.2-p180/gems/sinatra-1.2.3/lib/sinatra/base.rb:1088>], #<Proc:0x00000101b086f8@/Users/zjia/.rvm/gems/ruby-1.9.2-p180/gems/sinatra-1.2.3/lib/sinatra/base.rb:1165>]
ruby-1.9.2-p180 :005 > get '/download/*.*' do
ruby-1.9.2-p180 :006 >       params[:splat]
ruby-1.9.2-p180 :007?>   end
 => [/^\/download\/(.*?)\.(.*?)$/, ["splat", "splat"], [], #<Proc:0x00000101afb7a0@/Users/zjia/.rvm/gems/ruby-1.9.2-p180/gems/sinatra-1.2.3/lib/sinatra/base.rb:1165>]
ruby-1.9.2-p180 :008 > Sinatra::Application.routes
 => {"GET"=>[[/^\/([^\/?#]+)$/, ["action"], [#<Proc:0x00000101b09cd8@/Users/zjia/.rvm/gems/ruby-1.9.2-p180/gems/sinatra-1.2.3/lib/sinatra/base.rb:1088>], #<Proc:0x00000101b09378@/Users/zjia/.rvm/gems/ruby-1.9.2-p180/gems/sinatra-1.2.3/lib/sinatra/base.rb:1165>], [/^\/download\/(.*?)\.(.*?)$/, ["splat", "splat"], [], #<Proc:0x00000101afc448@/Users/zjia/.rvm/gems/ruby-1.9.2-p180/gems/sinatra-1.2.3/lib/sinatra/base.rb:1165>]], "HEAD"=>[[/^\/([^\/?#]+)$/, ["action"], [#<Proc:0x00000101b090d0@/Users/zjia/.rvm/gems/ruby-1.9.2-p180/gems/sinatra-1.2.3/lib/sinatra/base.rb:1088>], #<Proc:0x00000101b086f8@/Users/zjia/.rvm/gems/ruby-1.9.2-p180/gems/sinatra-1.2.3/lib/sinatra/base.rb:1165>], [/^\/download\/(.*?)\.(.*?)$/, ["splat", "splat"], [], #<Proc:0x00000101afb7a0@/Users/zjia/.rvm/gems/ruby-1.9.2-p180/gems/sinatra-1.2.3/lib/sinatra/base.rb:1165>]]}

Besides routes we can define filters that are processed before or after a request. A filter is like a route in that it can also be matched if a path or a condition is given. There are two types filters - before filter and after filter. Both of then use the `add_filter` method. `filters` is a attr_reader of the Sinatra::Base singleton class: `@filters = {:before => [], :after => []}`.

```ruby
  # Define a before filter; runs before all requests within the same
  # context as route handlers and may access/modify the request and
  # response.
  def before(path = nil, options = {}, &block)
    add_filter(:before, path, options, &block)
  end

  # Define an after filter; runs after all requests within the same
  # context as route handlers and may access/modify the request and
  # response.
  def after(path = nil, options = {}, &block)
    add_filter(:after, path, options, &block)
  end

  # add a filter
  def add_filter(type, path = nil, options = {}, &block)
    return filters[type] << block unless path
    path, options = //, path if path.respond_to?(:each_pair)
    block, *arguments = compile!(type, path, block, options)
    add_filter(type) do
      process_route(*arguments) { instance_eval(&block) }
    end
  end
```

Suppose we add a before filter without a path, so that it will be run before every request.

```ruby
before '/foo/*' do
  @note = 'Hi!'
  request.path_info = '/foo/bar/baz'
end
```

In the `add_filter` the block of the before filter is added to the filters[:before] hash. If there is no path, which means it doesn't need to be routed, then `add_filter` is just returned with the filters[:before] hash. Next if path is a hash, which means the path is a condition, then the path is set to `//` which will match any routes, and options is set to the condition. Then `compile!(type, path, block, options)` is called. We get the pattern, keys, conditions from `compile!` and assign them to an array `argument`. After that `add_filter` is called again with only the `type` and a block as the parameters. `add_filter` then adds the block to `filters[type]` and returns. So the filters[:before] and filters[:after] are two proc arrays. Now let's see the block passed to `add_filter`. In the block it calls `process_route(*arguments) { instance_eval(&block) }`. `process_route` is a pretty big method.

It first make a copy of `@params`. We can see `@params` is assigned back to `original_params` in the ensure block at the end of `process_route` method. So `params` will be modified in `process_route` and we want it to be the same after `process_route` returns. `:params` is an attr_accessor defined on Sinatra::Base: `attr_accessor :env, :request, :response, :params`.

```ruby
  # If the current request matches pattern and conditions, fill params
  # with keys and call the given block.
  # Revert params afterwards.
  #
  # Returns pass block.
  def process_route(pattern, keys, conditions)
    @original_params ||= @params
    route = @request.route
    route = '/' if route.empty? and not settings.empty_path_info?
    if match = pattern.match(route)
      values = match.captures.to_a
      params =
        if keys.any?
          keys.zip(values).inject({}) do |hash,(k,v)|
            if k == 'splat'
              (hash[k] ||= []) << v
            else
              hash[k] = v
            end
            hash
          end
        elsif values.any?
          {'captures' => values}
        else
          {}
        end
      @params = @original_params.merge(params)
      @block_params = values
      catch(:pass) do
        conditions.each { |cond|
          throw :pass if instance_eval(&cond) == false }
        yield
      end
    end
  ensure
    @params = @original_params
  end
```

`params` is assigned in the `Sinatra::Base#call!` method: `@params = indifferent_params(@request.params)`. We've seen `call!` is run when a request comes in and our app is initialized. `@request` is an instance of Sinatra::Request and is also an attr_accessor on Sinatra::Base. `@request.params` just returns an hash of parameters passed in by the request. For example in the request to `http://127.0.0.1:4567/?a[name]=1&b=2` the request.params is `{"a"=>{"name"=>"1"}, "b"=>"2"}`. In `indifferent_params` an `indifferent_hash` is called and returns a hash that will automatically convert symbol key to string key when accessing it. We merge the params to that hash so we can access the top level params with both symbol key and string key. Next params is looped and convert the nested params using `indifferent_params`.

```ruby
  # Enable string or symbol key access to the nested params hash.
  def indifferent_params(params)
    params = indifferent_hash.merge(params)
    params.each do |key, value|
      next unless value.is_a?(Hash)
      params[key] = indifferent_params(value)
    end
  end
```

```ruby
  # Creates a Hash with indifferent access.
  def indifferent_hash
    Hash.new {|hash,key| hash[key.to_s] if Symbol === key }
  end
```

Next `route = @request.route` takes a copy of the unescaped the requested path stored in `Sinatra::Base#path_info` and assigns it to the instance variable `route`. I list the slick method Rack::Utils.unescape here but don't explain it.

```ruby
  def route
    @route ||= Rack::Utils.unescape(path_info)
  end
```

```ruby
# Unescapes a URI escaped string. (Stolen from Camping).
def unescape(s)
  s.tr('+', ' ').gsub(/((?:%[0-9a-fA-F]{2})+)/n){
    [$1.delete('%')].pack('H*')
  }
end
module_function :unescape
```

Let's see an example of Rack::Utils.unescape.

ruby-1.9.2-p180 :012 > Rack::Utils.unescape('https%3A%2F%2Fapi.dropbox.com%2F0%2Ffileops%2Fcreate_folder&path%3D%2Ftest%26root%3Ddropbox')
 => "https://api.dropbox.com/0/fileops/create_folder&path=/test&root=dropbox"

The path_info returns `/0/fileops/create_folder&path=/test&root=dropbox`

Next line basically says that if you have define an empty route "" and the `path_info` is empty then it will use `/` as the route. I don't find the usage of an empty route yet so let's ignore it.

The `route` is matched against the pattern. Remember the pattern is the regular expression that represents the route. If a match it found, `values = match.captures.to_a` assigns all of the matched components to the variable `value`. Here `to_a` isn't necessary since `captures` already returns an array.

Next chunk of code just tries to populate the `params` variable if there is any element in `keys`. `keys.zip(values)` drops each key in `keys` to each of the element in values array to for a 2-dimension array. For example, our keys array is `['splat', 'foo']`, and the value array is ['bar', 'foobar'], then `keys.zip(values)` returns [['splat', 'bar'], ['foo', 'foobar']. Then constructs a hash using the first element of the 2-dimension array as the key and the last element as the value. In the case of above example, the final hash is {"splat" => 'bar, 'foo', 'foobar'}. If there is no elements in `keys` and there is any `values`, which means the route defines unnamed parameters like the following example, then we just assign all the values to hash keyed on 'captures'. Otherwise an empty hash is returned.

```ruby
get %r{/hello/([\w]+)} do
  "Hello, #{params[:captures].first}!"
end
```

Then we merge the `params` hash to the existing @params: `@params = @original_params.merge(params)`. We assign `values` to @block_params which as we discussed will be used as parameters to the routes defined like:

```ruby
get '/hello/:name' do |n|
  "Hello #{n}!"
end
```

Next we examine whether the conditions are all satisfied. If the any of condition procs is evaluated as false by `instance_eval(&cond) == false`, i.e. the condition isn't satisfied, then `yield` isn't called and no further processing is done; otherwise `process_route` yields to the block passed to it.

Now let's return to our `add_filter` method. The block passed to `process_route` is `{ instance_eval(&block) }`, which basically runs the block we passed to the filter. We can imagine when a request comes in, for each of the filters we try to match it with the request; if a match is found we run the filter.

After routes and filters are defined, let's see how routing is handled. Suppose classic.rb is running and we have a request to '/' coming in. As we have discussed in tutorial_2, the Sinatra::Base.call initializes the app and calls Sinatra::Base#call which in turn calls Sinatra::Base#call!. In Sinatra::Base#call! this line triggers the routing process: `invoke { dispatch! }`. `dispatch!` is where the routing happens.

```ruby
  # Dispatch a request with error handling.
  def dispatch!
    static! if settings.static? && (request.get? || request.head?)
    filter! :before
    route!
  rescue NotFound => boom
    handle_not_found!(boom)
  rescue ::Exception => boom
    handle_exception!(boom)
  ensure
    filter! :after unless env['sinatra.static_file']
  end
```

First off a sequence settings. By default, in classic sinatra app `app_file` is the file that is being run. In modular sinatra app it's nil unless set. `root` and `public `are true if app_file is set. `static` is true if the public folder in the `root` exists.

```ruby
  set :app_file, nil
  set :root, Proc.new { app_file && File.expand_path(File.dirname(app_file)) }
  set :public, Proc.new { root && File.join(root, 'public') }
  set :static, Proc.new { public && File.exist?(public) }
```

If `static` is true, and the request is either get or head request, then `static!` is called. `request.get?` and `request.head?` are instance methods on Rack::Request:

```ruby
def get?;     request_method == "GET"     end
def head?;    request_method == "HEAD"    end
```

In `static!` the first line double check settings.public is not nil. You may wonder that `settings.public` should not be nil since `static!` is already called. otherwise `static?` would return false. However it's possible after the current app is run we monkeypatch the app and set the public to nil. So the check is necessary.

If `public` exists, we construct the absolute path to the `path_info` by combining the absolute path to the public folder and the unescaped `request.path_info`. Note unescaped is imported to Sinatra::Base by `include Rack::Utils`. The check of `path.start_with?(public_dir)` is important because we don't want the any request to access files outside the public folder. For example the request can be '/../../../etc/passwd'. If the file exists。 then we set the env['sinatra.static_file'] to the path to the file, and use `send_file` to generate the response object. `send_file` is inside the Sinatra::Helper. We will learn it in later tutorials. Note even the requested file is found it's not the end; we still need to run `filter!` and `route!`

```ruby
  # Attempt to serve static files from public directory. Throws :halt when
  # a matching file is found, returns nil otherwise.
  def static!
    return if (public_dir = settings.public).nil?
    public_dir = File.expand_path(public_dir)

    path = File.expand_path(public_dir + unescape(request.path_info))
    return unless path.start_with?(public_dir) and File.file?(path)

    env['sinatra.static_file'] = path
    send_file path, :disposition => nil
  end
```

Then `Sinatra::Base#filter!` is run. We pass in :before as the first parameter, which means we want the before filters run. The `filter!` iteratively gets the before filters on current app and all it's superclasses' and evaluates them on the instance level of current app, i.e. `process_route(*arguments) { instance_eval(&block) }` will be run. We already know `process_route` stuffs the params hash, and run the block if a route is matched.

```ruby
  # Run filters defined on the class and all superclasses.
  def filter!(type, base = settings)
    filter! type, base.superclass if base.superclass.respond_to?(:filters)
    base.filters[type].each { |block| instance_eval(&block) }
  end
```

After before filters are run, `route!` is run on the current class and all superclasses.

```ruby
  # Run routes defined on the class and all superclasses.
  def route!(base = settings, pass_block=nil)
    if routes = base.routes[@request.request_method]
      routes.each do |pattern, keys, conditions, block|
        pass_block = process_route(pattern, keys, conditions) do
          route_eval(&block)
        end
      end
    end

    # Run routes defined in superclass.
    if base.superclass.respond_to?(:routes)
      return route!(base.superclass, pass_block)
    end

    route_eval(&pass_block) if pass_block
    route_missing
  end

Based on the `Rack::Request#request_method`, it gets the corresponding values of the @routes hash, and calls `process_route` on each of the routes.

```ruby
def request_method;  @env["REQUEST_METHOD"] end
```

If a route is matched, `route_eval` is called, which evaluates the route processing proc and throws :halt with the result of the `instance_eval(&block)`.

```ruby
  # Run a route block and throw :halt with the result.
  def route_eval(&block)
    throw :halt, instance_eval(&block)
  end
```

The :halt terminates further processing of other possible routes. :halt is caught in the `Sinatra::Base#invoke`. Remember `dispatch!` is wrapped in `invoke { dispatch! }`. So the block passed to invoke is run by `instance_eval` and the result is used to generate the response.

```
  # Run the block with 'throw :halt' support and apply result to the response.
  def invoke(&block)
    res = catch(:halt) { instance_eval(&block) }
    return if res.nil?

    case
    when res.respond_to?(:to_str)
      @response.body = [res]
    when res.respond_to?(:to_ary)
      res = res.to_ary
      if Fixnum === res.first
        if res.length == 3
          @response.status, headers, body = res
          @response.body = body if body
          headers.each { |k, v| @response.headers[k] = v } if headers
        elsif res.length == 2
          @response.status = res.first
          @response.body   = res.last
        else
          raise TypeError, "#{res.inspect} not supported"
        end
      else
        @response.body = res
      end
    when res.respond_to?(:each)
      @response.body = res
    when (100..599) === res
      @response.status = res
    end

    res
  end
```