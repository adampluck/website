ELEVENLABS = Faraday.new(
  url: 'https://api.elevenlabs.io/v1',
  headers: { 'Content-Type': 'application/json', 'xi-api-key': "#{ENV['ELEVENLABS_API_KEY']}" },
  request: { timeout: 10 }
)
