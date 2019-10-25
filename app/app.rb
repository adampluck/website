module ActivateApp
  class App < Padrino::Application
    register Padrino::Rendering
    register Padrino::Helpers
    register WillPaginate::Sinatra
    helpers Activate::DatetimeHelpers
    helpers Activate::ParamHelpers
    helpers Activate::NavigationHelpers
    
    if Padrino.env == :production
      register Padrino::Cache
      enable :caching 
    end
      
    require 'sass/plugin/rack'
    Sass::Plugin.options[:template_location] = Padrino.root('app', 'assets', 'stylesheets')
    Sass::Plugin.options[:css_location] = Padrino.root('app', 'assets', 'stylesheets')
    use Sass::Plugin::Rack

    use Airbrake::Rack::Middleware

    set :sessions, :expire_after => 1.year
    set :public_folder, Padrino.root('app', 'assets')
    set :default_builder, 'ActivateFormBuilder'

    Mail.defaults do
      delivery_method :smtp, {
        :user_name => ENV['SMTP_USERNAME'],
        :password => ENV['SMTP_PASSWORD'],
        :address => ENV['SMTP_ADDRESS'],
        :port => 587
      }
    end

    before do
      redirect "http://#{ENV['DOMAIN']}#{request.path}" if ENV['DOMAIN'] and request.env['HTTP_HOST'] != ENV['DOMAIN']
      if params[:r]
        ActivateApp::App.cache.clear
        redirect request.path
      end      
      fix_params!
      Time.zone = 'London'
      @og_desc = 'Transdisciplinary thinker, cultural changemaker and metamodern mystic'
      @og_image = "http://#{ENV['DOMAIN']}/images/link4.png"
    end

    error do
      Airbrake.notify(env['sinatra.error'], :session => session)
      erb :error, :layout => :application
    end

    not_found do
      erb :not_found, :layout => :application
    end

    get '/', :cache => true do
      expires 1.hour.to_i
      @posts = Post.all(filter: "AND(
        IS_AFTER({Created at}, '#{1.month.ago.to_s(:db)}'),
        FIND('\"url\": ', {Iframely}) > 0,
        {Twitter URL} != ''
      )", sort: { "Created at" => "desc" }, paginate: false)       
      erb :home
    end
    
    get '/search' do
      @title = params[:q]
      if params[:q]
        @posts = Post.all(filter: "AND(
        OR(
          FIND(LOWER('#{params[:q]}'), LOWER({Title})) > 0,
          FIND(LOWER('#{params[:q]}'), LOWER({Body})) > 0,
          FIND(LOWER('#{params[:q]}'), LOWER({Iframely})) > 0
        ),
        {Twitter URL} != '')
          ", sort: { "Created at" => "desc" })       
      else
        @posts = Post.all(filter: "AND(
        IS_AFTER({Created at}, '#{1.month.ago.to_s(:db)}'),
        FIND('\"url\": ', {Iframely}) > 0,
        {Twitter URL} != ''
      )", sort: { "Created at" => "desc" }, paginate: false)    
      end
      erb :search            
    end
    
    get '/feed', :provides => :rss, :cache => true do
      expires 1.hour.to_i
      @posts = Post.all(filter: "AND(
        IS_AFTER({Created at}, '#{1.month.ago.to_s(:db)}'),
        FIND('\"url\": ', {Iframely}) > 0,
        {Twitter URL} != ''
      )", sort: { "Created at" => "desc" }, paginate: false)     
      RSS::Maker.make("atom") do |maker|
        maker.channel.author = "Stephen Reid"
        maker.channel.updated = Time.now.to_s
        maker.channel.about = "http://stephenreid.net"
        maker.channel.title = "Stephen Reid"

        @posts.each { |post|
          maker.items.new_item do |item|
            item.link = post['Link']
            item.title = post['Title']
            item.description = post['Body']
            item.updated = post['Created at']
          end
        }
      end.to_s            
    end
    
    get '/bio', :cache => true do
      @title = 'Biography'
      erb :bio
    end
    
    get '/donate', :cache => true do
      @title = 'Donate'
      erb :donate
    end
    
    get '/training', :cache => true do
      @title = 'Training'
      erb :training
    end    

    get '/podcast', :cache => true do
      @title = 'Podcast'
      erb :podcast
    end

    get '/calendar', :cache => true do
      @title = 'Calendar'
      erb :calendar
    end
     
    get '/habits', :cache => true do
      @title = 'Habits'
      erb :habits
    end
    
    get '/diet', :cache => true do
      @title = 'Diet'
      erb :diet
    end    

    get '/tarot', :cache => true do
      @title = 'Tarot'
      @og_image = "http://#{ENV['DOMAIN']}/images/the-magician.jpg"
      erb :tarot
    end
    
    get '/products', :cache => true do
      @title = 'Recommended products'
      erb :products
    end    
    
    get '/books', :cache => true do
      @title = 'Books'
      erb :books
    end 
    
    get '/posts/:id', :cache => true do
      @post = Post.find(params[:id]) 
      @json = JSON.parse(@post['Iframely'])
      @title = @post['Title']
      @og_desc = @post['Body']
      if @json['links'] && @json['links']['thumbnail']
        @og_image = @json['links']['thumbnail'].first['href']
      end
      erb :post
    end 
    
    get '/posts/:id/iframely' do
      @post = Post.find(params[:id])
      agent = Mechanize.new
      result = agent.get("https://iframe.ly/api/iframely?url=#{@post['Link'].split('#').first}&api_key=#{ENV['IFRAMELY_API_KEY']}")
      @post['Iframely'] = result.body.force_encoding("UTF-8")
      @post.save
      redirect "/posts/#{params[:id]}"
    end
    
    get '/blog', :cache => true do
      @blog_posts = BlogPost.all(sort: { "Published at" => "desc" })
      erb :blog
    end   
    
    get '/blog/feed', :provides => :rss, :cache => true do
      @blog_posts = BlogPost.all(sort: { "Published at" => "desc" })
      RSS::Maker.make("atom") do |maker|
        maker.channel.author = "Stephen Reid"
        maker.channel.updated = Time.now.to_s
        maker.channel.about = "http://stephenreid.net"
        maker.channel.title = "Stephen Reid"

        @blog_posts.each { |blog_post|
          maker.items.new_item do |item|
            item.link = "https://#{ENV['DOMAIN']}/blog/#{blog_post['Slug']}"
            item.title = blog_post['Title']
            item.description = blog_post['Summary']
            item.updated = blog_post['Published at']
          end
        }
      end.to_s            
    end    

    get '/blog/:slug', :cache => true do
      @blog_post = BlogPost.all(filter: "{Slug} = '#{params[:slug]}'").first
      @title = @blog_post['Title']
      @og_desc = @blog_post['Summary']
      @og_image = @blog_post['Attachments'].first['url']
      erb :blog_post
    end    
    


    
    get '/to/:slug' do
      @url = Product.all(filter: "{Slug} = '#{params[:slug]}'").first['URL']
      redirect @url
    end
    
    get '/p/:slug' do
      @url = Product.all(filter: "{Slug} = '#{params[:slug]}'").first['URL']
      erb :redirect
    end
    
    get '/r/:slug' do
      @url = Link.all(filter: "{Slug} = '#{params[:slug]}'").first['URL']
      erb :redirect
    end    
                   
    get '/places-plans' do
      @title = 'Places & Plans'
      erb :places
    end      
        
    get '/link' do
      redirect 'http://stephenreid.net'
    end
    
    get '/substack' do
      @from = params[:from] ? Date.parse(params[:from]) : Date.today
      erb :substack
    end   
           
    
    
    
    
            
    get '/ps' do
      redirect 'https://www.google.com/maps/place/The+Psychedelic+Society/@51.547382,-0.0449452,17z/data=!4m12!1m6!3m5!1s0x48761dff684f311b:0xa492a62a16335e19!2sThe+Psychedelic+Society!8m2!3d51.547382!4d-0.0427565!3m4!1s0x48761dff684f311b:0xa492a62a16335e19!8m2!3d51.547382!4d-0.0427565'
    end    
        
    get '/gh' do
      redirect 'https://www.google.com/maps/place/Greenhouse/@51.5529027,-0.0879017,15z/data=!4m2!3m1!1s0x0:0x9850520d11f22809?sa=X&ved=2ahUKEwjDvsas2MDhAhVlRRUIHS9_B5MQ_BIwDnoECA0QCA'
    end
    
    
    
    
    get '/darknet' do #, :cache => true do
      redirect 'https://dark.fail/'
    end

    get '/why-use-the-darknet' do #, :cache => true do
      redirect 'https://dark.fail/'
    end
        
    get '/podcasts' do
      redirect '/podcast'
    end        
        
    get '/bio' do
      redirect '/'
    end
    
    get '/books-videos' do
      redirect '/'
    end    
    
    get '/featured' do
      redirect '/'
    end
    
    get '/recommended' do
      redirect '/'
    end

  end
end
