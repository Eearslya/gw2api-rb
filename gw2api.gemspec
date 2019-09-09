Gem::Specification.new do |s|
  s.name = 'gw2api'
  s.authors = ['Eearslya Sleiarion']
  s.version = '0.2.1'
  s.date = '2019-09-09'
  s.summary = 'A gem to allow easy access to all of the data provided by the Guild Wars 2 API.'
  s.files = [
    'lib/gw2api.rb'
  ]
  s.require_paths = ['lib']
  s.add_runtime_dependency 'typhoeus', '~> 1.3.1'
end
