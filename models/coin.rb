class Coin
  include Mongoid::Document
  include Mongoid::Timestamps

  field :slug, type: String
  field :decimals, type: Integer
  field :units, type: Float
  field :contract_address, type: String
  field :symbol, type: String
  field :name, type: String
  field :defi_pulse_name, type: String
  field :platform, type: String
  field :current_price, type: Float
  field :market_cap, type: Float
  field :market_cap_change_percentage_24h, type: Float
  field :market_cap_rank, type: Integer
  field :market_cap_rank_prediction, type: Integer
  field :market_cap_rank_prediction_conviction, type: Float
  field :total_volume, type: Float
  field :uniswap_volume, type: Float
  field :sushiswap_volume, type: Float
  field :tvl, type: Float
  field :price_change_percentage_1h_in_currency, type: Float
  field :price_change_percentage_24h_in_currency, type: Float
  field :price_change_percentage_7d_in_currency, type: Float
  field :website, type: String
  field :twitter_username, type: String
  field :twitter_followers, type: Integer
  field :hidden, type: Boolean
  field :starred, type: Boolean
  field :staked_units, type: Float
  field :notes, type: String
  field :skip_remote_update, type: Boolean

  belongs_to :tag, optional: true

  def self.admin_fields
    {
      slug: :text,
      symbol: :text,
      name: :text,
      defi_pulse_name: :text,
      skip_remote_update: :check_box,
      units: :number,
      staked_units: :number,
      notes: :text_area,
      contract_address: :text,
      decimals: :number,
      platform: :text,
      current_price: :number,
      market_cap: :number,
      market_cap_rank: :number,
      total_volume: :number,
      price_change_percentage_1h_in_currency: :number,
      price_change_percentage_24h_in_currency: :number,
      price_change_percentage_7d_in_currency: :number,
      market_cap_change_percentage_24h: :number,
      uniswap_volume: :number,
      sushiswap_volume: :number,
      tvl: :number,
      website: :url,
      twitter_username: :text,
      twitter_followers: :number,
      hidden: :check_box,
      starred: :check_box,
      tag_id: :lookup
    }
  end

  before_validation do
    self.symbol = symbol.try(:upcase)
    self.twitter_followers = nil if twitter_followers && twitter_followers.zero?
  end

  def market_cap_at_predicted_rank
    if (p = market_cap_rank_prediction)
      mc = nil
      until mc
        mc = Coin.find_by(market_cap_rank: p).try(:market_cap)
        p += 1
      end
      mc
    end
  end

  def market_cap_change_prediction
    (market_cap_at_predicted_rank / market_cap) * (market_cap_rank_prediction_conviction || 1) if market_cap_at_predicted_rank && market_cap && (market_cap > 0)
  end

  def all_units
    (units || 0) + (staked_units || 0)
  end

  def holding
    (all_units || 0) * (current_price || 0)
  end

  def erc20?
    platform == 'ethereum'
  end

  def score_index(x, coins)
    index = coins.order("#{x} desc").pluck(:symbol).index(symbol) + 1
    min = coins.pluck(x).compact.min
    max = coins.pluck(x).compact.max
    score = 100 * ((send(x) - min) / (max - min))
    [score, index]
  end

  def self.eth_usd
    agent = Mechanize.new
    JSON.parse(agent.get('https://api.coingecko.com/api/v3/coins/ethereum').body)['market_data']['current_price']['usd']
  end

  def self.import
    agent = Mechanize.new
    i = 1
    until (coins = JSON.parse(agent.get("https://api.coingecko.com/api/v3/coins/markets?vs_currency=eth&per_page=250&price_change_percentage=1h,24h,7d&page=#{i}").body)).empty?
      i += 1
      coins.each do |c|
        puts c['symbol'].upcase

        coin = Coin.find_or_create_by!(slug: c['id'])
        next if coin.skip_remote_update

        %w[symbol name current_price market_cap market_cap_rank market_cap_change_percentage_24h total_volume price_change_percentage_1h_in_currency price_change_percentage_24h_in_currency price_change_percentage_7d_in_currency].each do |r|
          coin.send("#{r}=", c[r])
        end
        coin.save
      end
    end
  end

  def self.symbol(symbol)
    Coin.where(symbol: symbol.upcase).order('total_volume desc').first
  end

  def self.remote_update
    Coin.all.each do |coin|
      coin.remote_update
    end
  end

  def remote_update
    return if skip_remote_update

    agent = Mechanize.new
    begin
      c = JSON.parse(agent.get("https://api.coingecko.com/api/v3/coins/#{slug}").body)
    rescue Mechanize::ResponseCodeError => e
      puts e.response_code
      case e.response_code.to_i
      when 404
        destroy
      when 429
        sleep 1
        remote_update
      else
        Airbrake.notify(e)
        self.units = nil
        save!
      end
      return
    end
    %w[current_price market_cap total_volume price_change_percentage_1h_in_currency price_change_percentage_24h_in_currency price_change_percentage_7d_in_currency].each do |r|
      send("#{r}=", c['market_data'][r]['eth'])
    end
    %w[market_cap_rank].each do |r|
      send("#{r}=", c['market_data'][r])
    end
    self.contract_address = c['contract_address']
    self.platform = c['asset_platform_id']
    self.website = c['links']['homepage'].first
    self.twitter_username = c['links']['twitter_screen_name']
    self.twitter_followers = c['community_data']['twitter_followers']
    if starred
      u = 0
      if erc20?
        ENV['ETH_ADDRESSES'].split(',').each do |a|
          u += JSON.parse(agent.get("https://api.etherscan.io/api?module=account&action=tokenbalance&contractaddress=#{contract_address}&address=#{a}&tag=latest&apikey=#{ENV['ETHERSCAN_API_KEY']}").body)['result'].to_i / 10**(decimals || 18).to_f
        end
      elsif symbol == 'ETH'
        ENV['ETH_ADDRESSES'].split(',').each do |a|
          u += JSON.parse(agent.get("https://api.etherscan.io/api?module=account&action=balance&address=#{a}&tag=latest&apikey=#{ENV['ETHERSCAN_API_KEY']}").body)['result'].to_i / 10**(decimals || 18).to_f
        end
      else

        client = Binance::Client::REST.new api_key: ENV['BINANCE_API_KEY'], secret_key: ENV['BINANCE_API_SECRET']
        balances = client.account_info['balances']
        bc = balances.find do |b|
          b['asset'] == symbol
        end
        u += (bc['free'].to_f + bc['locked'].to_f) if bc

      end

      self.units = u
    else
      self.units = nil
    end
    save!
  end
end
