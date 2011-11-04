class Cobweb::Spider

  ## TASKS

  # redesign to have a resque stack and a single threaded stack
  # dry the code below, its got a lot of duplication
  # detect the end of the crawl (queued == 0 ?)
  # on end of crawl, return statistic hash (could call specified method ?) if single threaded or enqueue to a specified queue the stat hash
  # investigate using event machine for single threaded crawling

  def initialize(options = {})
    @options = options
    @options[:follow_redirects] = true unless @options.has_key?(:follow_redirects)
    @options[:redirect_limit] = 10 unless @options.has_key?(:redirect_limit)
    @options[:processing_queue] = Cobweb::ProcessJob unless @options.has_key?(:processing_queue)
    @options[:crawl_finished_queue] = Cobweb::CrawlFinishedJob unless @options.has_key?(:crawl_finished_queue)
    @options[:quiet] = true unless @options.has_key?(:quiet)
    @options[:debug] = false unless @options.has_key?(:debug)
    @options[:cache] = 300 unless @options.has_key?(:cache)
    @options[:timeout] = 10 unless @options.has_key?(:timeout)
    @options[:redis_options] = {} unless @options.has_key?(:redis_options)

  end

  def start(base_url)
    raise ":base_url is required" unless base_url
    request = {
      :crawl_id => Digest::SHA1.hexdigest(Time.now.to_s),
      :url => base_url
    }

    request.merge!(@options)
    redis = Cobweb::NamespacedRedis.new(Redis.new(request[:redis_options]), "cobweb-#{request[:crawl_id]}")
    redis.hset "statistics", "queued_at", DateTime.now

    Resque.enqueue(CrawlJob, request)
  end

  def get(url, redirect_limit = @options[:redirect_limit])

    raise "url cannot be nil" if url.nil?

    absolutize = Absolutize.new(url, :output_debug => false, :raise_exceptions => false, :force_escaping => false, :remove_anchors => true)

    # get the unique id for this request
    unique_id = Digest::SHA1.hexdigest(url)

    # connect to redis
    redis = Cobweb::NamespacedRedis.new(Redis.new(@options[:redis_options]), "cobweb")

    content = {}

    # check if it has already been cached
    if redis.get(unique_id) and @options[:cache]
      puts "Cache hit for #{url}" unless @options[:quiet]
      content = JSON.parse(redis.get(unique_id)).deep_symbolize_keys
      content[:body] = Base64.decode64(content[:body]) unless content[:body].nil? or content[:mime_type].include?("text/html") or content[:mime_type].include?("application/xhtml+xml")

      content
    else
      # this url is valid for processing so lets get on with it
      print "Retrieving #{url }... " unless @options[:quiet]
      uri = Addressable::URI.parse(url.strip)

      # retrieve data
      http = Net::HTTP.new(uri.host, uri.inferred_port)
      if uri.scheme == "https"
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end

      request_time = Time.now.to_f
      http.read_timeout = @options[:timeout].to_i
      http.open_timeout = @options[:timeout].to_i
      begin
        response = http.start() {|http|
          response = http.get(uri.request_uri)
        }

        if @options[:follow_redirects] and response.code.to_i >= 300 and response.code.to_i < 400
          puts "redirected... " unless @options[:quiet]
          url = absolutize.url(response['location']).to_s
          redirect_limit = redirect_limit - 1
          content = get(url, redirect_limit)
          content[:url] = uri.to_s
          content[:redirect_through] = [] if content[:redirect_through].nil?
          content[:redirect_through].insert(0, url)

          content[:response_time] = Time.now.to_f - request_time
        else
          content[:response_time] = Time.now.to_f - request_time

          puts "Retrieved." unless @options[:quiet]

          # create the content container
          content[:url] = uri.to_s
          content[:status_code] = response.code.to_i
          content[:mime_type] = response.content_type.split(";")[0].strip
          charset = response["Content-Type"][response["Content-Type"].index(";")+2..-1] if !response["Content-Type"].nil? and response["Content-Type"].include?(";")
          charset = charset[charset.index("=")+1..-1] if charset and charset.include?("=")
          content[:character_set] = charset
          content[:length] = response.content_length
          if content[:mime_type].include?("text/html") or content[:mime_type].include?("application/xhtml+xml")
            content[:body] = response.body
          else
            content[:body] = Base64.encode64(response.body)
          end
          content[:location] = response["location"]
          content[:headers] = response.to_hash.symbolize_keys
          # parse data for links
          link_parser = Cobweb::ContentLinkParser.new(content[:url], content[:body])
          content[:links] = link_parser.link_data

        end
        # add content to cache if required
        if @options[:cache]
          content[:body] = Base64.encode64(content[:body]) unless content[:body].nil? or content[:mime_type].include?("text/html") or content[:mime_type].include?("application/xhtml+xml")
          redis.set(unique_id, content.to_json)
          redis.expire unique_id, @options[:cache].to_i
        end
      rescue SocketError => e
        puts "ERROR: #{e.message}"
        content = blank_content(uri, e.message, "error/dnslookup")
      rescue Timeout::Error => e
        puts "ERROR: #{e.message}"
        content = blank_content(uri, e.message, "error/serverdown")
      end
    end
    content
  end

  def head(url, redirect_limit = @options[:redirect_limit])
    raise "url cannot be nil" if url.nil?

    absolutize = Absolutize.new(url, :output_debug => false, :raise_exceptions => false, :force_escaping => false, :remove_anchors => true)

    # get the unique id for this request
    unique_id = Digest::SHA1.hexdigest(url)

    # connect to redis
    redis = Cobweb::NamespacedRedis.new(Redis.new(@options[:redis_options]), "cobweb")

    content = {}

    # check if it has already been cached
    if (redis.get(unique_id) or redis.get("head-#{unique_id}")) and @options[:cache]
      puts "Cache hit for #{url}" unless @options[:quiet]
      if redis.get(unique_id)
        content = JSON.parse(redis.get(unique_id)).deep_symbolize_keys
      else
        content = JSON.parse(redis.get("head-#{unique_id}")).deep_symbolize_keys
      end
      content
    else
      print "Retrieving #{url }... " unless @options[:quiet]
      uri = Addressable::URI.parse(url.strip)

      # retrieve data
      http = Net::HTTP.new(uri.host, uri.inferred_port)
      if uri.scheme == "https"
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end

      request_time = Time.now.to_f
      http.read_timeout = @options[:timeout].to_i
      http.open_timeout = @options[:timeout].to_i

      begin
        response = http.head(uri.to_s)

        if @options[:follow_redirects] and response.code.to_i >= 300 and response.code.to_i < 400
          puts "redirected... " unless @options[:quiet]
          url = absolutize.url(response['location']).to_s
          redirect_limit = redirect_limit - 1
          content = head(url, redirect_limit)
          content[:url] = uri.to_s
          content[:redirect_through] = [] if content[:redirect_through].nil?
          content[:redirect_through].insert(0, url)
        else
          content[:url] = uri.to_s
          content[:status_code] = response.code.to_i
          unless response.content_type.nil?
            content[:mime_type] = response.content_type.split(";")[0].strip
            charset = response["Content-Type"][response["Content-Type"].index(";")+2..-1] if !response["Content-Type"].nil? and response["Content-Type"].include?(";")
            charset = charset[charset.index("=")+1..-1] if charset and charset.include?("=")
            content[:character_set] = charset
          end

          # add content to cache if required
          if @options[:cache]
            puts "Stored in cache [head-#{unique_id}]" if @options[:debug]
            redis.set("head-#{unique_id}", content.to_json)
            redis.expire "head-#{unique_id}", @options[:cache].to_i
          else
            puts "Not storing in cache as cache disabled" if @options[:debug]
          end
        end
      rescue SocketError => e
        puts "ERROR: #{e.message}"
        content = blank_content(uri, e.message, "error/dnslookup")
      rescue Timeout::Error => e
        puts "ERROR: #{e.message}"
        content = blank_content(uri, e.message, "error/serverdown")
      end

      content
    end

    private
    def blank_content(uri, message, mime_type)
       content = {
         :url => uri.to_s,
         :respone_time => Time.now.to_f - request_time,
         :status_code => 0,
         :length => 0,
         :body => "",
         :error => message,
         :mime_type => mime_type,
         :headers => {},
         :links => {}
       }
    end
  end
end

## add symbolize methods to hash
class Hash
  def symbolize_keys
    keys.each do |key|
      if key.instance_of? String
        value = self[key]
        self.delete(key)
        self[key.to_sym] = value
      end
    end
    self
  end
  def deep_symbolize_keys
    symbolize_keys
    keys.each do |key|
      if self[key].instance_of? Hash
        self[key].deep_symbolize_keys
      end
    end
    self
  end
end
