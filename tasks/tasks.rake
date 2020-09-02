namespace :strategies do
  task update: :environment do
    Strategy.import
    Strategy.update
  end

  task post_structure: :environment do
    Strategy.post_structure
  end
end

namespace :terms do
  task create_edges: :environment do
    term_ids = []
    Post.all(filter: "IS_AFTER({Created at}, '#{1.day.ago.to_s(:db)}')").each do |post|
      term_ids += post['Terms'] if post['Terms']
    end
    term_ids.uniq.each do |term_id|
      term = Term.find(term_id)
      puts term['Name']
      term.create_edges
    end
  end
end

namespace :posts do
  task tag_new: :environment do
    term_ids = []
    agent = Mechanize.new
    Post.all(filter: "{Title} = ''").each do |post|
      result = agent.get("https://iframe.ly/api/iframely?url=#{post['Link'].split('#').first}&api_key=#{ENV['IFRAMELY_API_KEY']}")

      post['Iframely'] = result.body.force_encoding('UTF-8')

      json = JSON.parse(post['Iframely'])

      puts(post['Title'] = json['meta']['title'])
      post['Body'] = json['meta']['description']

      post.save

      if post['Title']
        post.tagify(skip_linking: true)
        term_ids += post['Terms'] if post['Terms']
      end
    end

    puts term_ids.count
    term_ids.uniq.each do |term_id|
      term = Term.find(term_id)
      puts term['Name']
      term.create_edges
    end
  end
end
