StephenReid::App.controller do
  before do
    @favicon = 'moon.png'
    @og_desc = nil
    @og_image = nil
  end

  get '/tags' do
    erb :'coins/tags'
  end

  get '/coins' do
    redirect '/coins/tag/holding'
  end

  get '/coins/tag/:tag' do
    Tag.update_holdings
    if params[:tag] == 'uniswap'
      agent = Mechanize.new
      @uniswap = []
      Coin.where(:uniswap_volume.ne => nil).set(uniswap_volume: nil)
      JSON.parse(agent.get('https://api.coingecko.com/api/v3/exchanges/uniswap').body)['tickers'].each do |ticker|
        if coin = Coin.find_by(slug: ticker['coin_id'])
          coin.update_attribute(:uniswap_volume, ticker['converted_volume']['eth'])
        end
        @uniswap << ticker['coin_id']
      end
    elsif params[:tag] == 'sushiswap'
      agent = Mechanize.new
      @sushiswap = []
      Coin.where(:sushiswap_volume.ne => nil).set(sushiswap_volume: nil)
      JSON.parse(agent.get('https://api.coingecko.com/api/v3/exchanges/sushiswap').body)['tickers'].each do |ticker|
        if coin = Coin.find_by(slug: ticker['coin_id'])
          coin.update_attribute(:sushiswap_volume, ticker['converted_volume']['eth'])
        end
        @sushiswap << ticker['coin_id']
      end
    elsif params[:tag] == 'defi-pulse'
      # agent = Mechanize.new
      # JSON.parse(agent.get('https://defipulse.com/').search('#__NEXT_DATA__').inner_html)['props']['initialState']['coin']['projects'].each do |p|
      #   if (coin = Coin.find_by(name: p['name'])) || (coin = Coin.find_by(defi_pulse_name: p['name']))
      #     coin.set(defi_pulse_name: p['name'])
      #   else
      #     puts "missing: #{p['name']}"
      #   end
      # end and 0
      agent = Mechanize.new
      @defi_pulse = []
      Coin.where(:tvl.ne => nil).set(tvl: nil)
      JSON.parse(agent.get('https://defipulse.com/').search('#__NEXT_DATA__').inner_html)['props']['initialState']['coin']['projects'].each do |project|
        if coin = Coin.find_by(defi_pulse_name: project['name'])
          coin.update_attribute(:tvl, project['value']['tvl']['ETH']['value'])
          @defi_pulse << coin.slug
        end
      end
    end
    erb :'coins/coins'
  end

  get '/coins/table/:tag' do
    partial :'coins/coin_table', locals: { coins: Coin.where(
      tag: Tag.find_by(name: params[:tag])
    ).order('price_change_percentage_24h_in_currency desc') }
  end

  post '/coins/table/:tag' do
    sign_in_required!
    Coin.symbol(params[:symbol]).update_attribute(:tag_id, Tag.find_or_create_by(name: params[:tag]).id)
    200
  end

  get '/coins/:slug' do
    coin = Coin.find_by(slug: params[:slug])
    coin.remote_update
    partial :'coins/coin', locals: { coin: coin }
  end

  get '/coins/:slug/hide' do
    sign_in_required!
    coin = Coin.find_by(slug: params[:slug])
    coin.update_attribute(:tag_id, nil)
    200
  end

  get '/coins/:slug/star' do
    sign_in_required!
    coin = Coin.find_by(slug: params[:slug])
    coin.update_attribute(:starred, true)
    coin.remote_update
    200
  end

  get '/coins/:slug/unstar' do
    sign_in_required!
    coin = Coin.find_by(slug: params[:slug])
    coin.update_attribute(:starred, nil)
    coin.remote_update
    expire("coin_#{params[:slug]}") unless Padrino.env == :development
    200
  end

  post '/coins/:slug/market_cap_rank_prediction' do
    coin = Coin.find_by(slug: params[:slug])
    coin.update_attribute(:market_cap_rank_prediction, params[:p])
    200
  end

  post '/coins/:slug/market_cap_rank_prediction_conviction' do
    coin = Coin.find_by(slug: params[:slug])
    coin.update_attribute(:market_cap_rank_prediction_conviction, params[:p])
    200
  end
end