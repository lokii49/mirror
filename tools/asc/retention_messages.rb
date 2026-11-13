# Creates the retention-message DRAFTS in App Store Connect from retention_messages.json:
# one message per tier, a version, a localization per locale, and the tier's two subscriptions
# linked to it. Never submits for review (that is a separate owner-approved step in ASC).
#
#   ruby tools/asc/retention_messages.rb            # dry run: prints what it would do
#   ruby tools/asc/retention_messages.rb --apply    # writes to App Store Connect
#   ruby tools/asc/retention_messages.rb --status   # lists messages, versions, locales, links
#
# Needs the `jwt` gem and mirror/fastlane/api_key.json (App Store Connect API key).
# Plan: .claude/3.1.9-retention-messages.md
require 'jwt'
require 'json'
require 'net/http'
require 'openssl'

APP_ID = '6769007201'
SUBSCRIPTIONS = {
  'mirror_core_monthly' => '6769008613',
  'mirror_core_yearly' => '6769009554',
  'mirror_deep_monthly' => '6770211024',
  'mirror_deep_yearly' => '6770211187',
}.freeze
ROOT = File.expand_path('../..', __dir__)
APPLY = ARGV.include?('--apply')
STATUS = ARGV.include?('--status')

def token
  @token ||= begin
    k = JSON.parse(File.read(File.join(ROOT, 'fastlane/api_key.json')))
    JWT.encode({ iss: k['issuer_id'], iat: Time.now.to_i, exp: Time.now.to_i + 1000, aud: 'appstoreconnect-v1' },
               OpenSSL::PKey::EC.new(k['key']), 'ES256', { kid: k['key_id'] })
  end
end

def api(method, path, body = nil)
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  req = Net::HTTP.const_get(method.capitalize).new(uri)
  req['Authorization'] = "Bearer #{token}"
  if body
    req['Content-Type'] = 'application/json'
    req.body = JSON.generate(body)
  end
  res = Net::HTTP.start(uri.host, 443, use_ssl: true) { |h| h.request(req) }
  raise "#{method} #{path} -> #{res.code}\n#{res.body}" unless res.code.start_with?('2')
  res.body.to_s.empty? ? nil : JSON.parse(res.body)
end

def write(method, path, body)
  unless APPLY
    puts "  [dry run] #{method} #{path} #{body && JSON.generate(body)[0, 160]}"
    return nil
  end
  api(method, path, body)
end

spec = JSON.parse(File.read(File.join(__dir__, 'retention_messages.json')))
spec['messages'].each do |m|
  m['localizations'].each do |locale, (header, body)|
    raise "#{m['referenceName']} #{locale}: header #{header.length} > 66" if header.length > 66
    raise "#{m['referenceName']} #{locale}: body #{body.length} > 144" if body.length > 144
  end
end

existing = api('GET', "/v1/apps/#{APP_ID}/retentionMessages?limit=50")['data']

if STATUS
  existing.each do |msg|
    puts "#{msg['attributes']['referenceName']} (#{msg['id']})"
    api('GET', "/v1/retentionMessages/#{msg['id']}/versions")['data'].each do |v|
      locs = api('GET', "/v1/retentionMessageVersions/#{v['id']}/localizations?limit=50")['data']
      puts "  version #{v['id']} #{v['attributes']['state']}: #{locs.map { |l| l['attributes']['locale'] }.sort.join(', ')}"
    end
  end
  SUBSCRIPTIONS.each do |name, id|
    linked = api('GET', "/v1/subscriptions/#{id}/retentionMessage")['data']
    puts "#{name}: #{linked ? linked['attributes']['referenceName'] : '(none)'}"
  end
  exit
end

puts APPLY ? 'APPLYING to App Store Connect' : 'DRY RUN (pass --apply to write)'
spec['messages'].each do |m|
  name = m['referenceName']
  puts "\n#{name}"
  msg = existing.find { |e| e['attributes']['referenceName'] == name }
  if msg
    puts "  message exists (#{msg['id']})"
  else
    msg = write('POST', '/v1/retentionMessages', { data: {
      type: 'retentionMessages', attributes: { referenceName: name },
      relationships: { app: { data: { type: 'apps', id: APP_ID } } },
    } })&.dig('data')
  end

  version = nil
  if msg
    versions = api('GET', "/v1/retentionMessages/#{msg['id']}/versions")['data']
    version = versions.find { |v| v['attributes']['state'] == 'PREPARE_FOR_SUBMISSION' }
    if version.nil? && !versions.empty?
      puts "  no editable version (states: #{versions.map { |v| v['attributes']['state'] }.join(', ')}); skipping text"
    elsif version.nil?
      version = write('POST', '/v1/retentionMessageVersions', { data: {
        type: 'retentionMessageVersions',
        relationships: { retentionMessage: { data: { type: 'retentionMessages', id: msg['id'] } } },
      } })&.dig('data')
    end
  else
    write('POST', '/v1/retentionMessageVersions', nil)
  end

  have = version ? api('GET', "/v1/retentionMessageVersions/#{version['id']}/localizations?limit=50")['data'] : []
  m['localizations'].each do |locale, (header, body)|
    loc = have.find { |l| l['attributes']['locale'] == locale }
    if loc.nil?
      write('POST', '/v1/retentionMessageLocalizations', { data: {
        type: 'retentionMessageLocalizations', attributes: { locale: locale, header: header, body: body },
        relationships: { retentionMessageVersion: { data: { type: 'retentionMessageVersions', id: version&.dig('id') || '<new>' } } },
      } })
    elsif loc['attributes']['header'] != header || loc['attributes']['body'] != body
      write('PATCH', "/v1/retentionMessageLocalizations/#{loc['id']}", { data: {
        type: 'retentionMessageLocalizations', id: loc['id'], attributes: { header: header, body: body },
      } })
    else
      puts "  #{locale} up to date"
    end
  end

  m['subscriptions'].each do |product|
    sid = SUBSCRIPTIONS.fetch(product)
    linked = api('GET', "/v1/subscriptions/#{sid}/retentionMessage")['data']
    if linked && msg && linked['id'] == msg['id']
      puts "  #{product} linked"
    else
      write('PATCH', "/v1/subscriptions/#{sid}/relationships/retentionMessage",
            { data: { type: 'retentionMessages', id: msg&.dig('id') || '<new>' } })
    end
  end
end
