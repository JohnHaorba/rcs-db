#
# Full text search keyword indexer
#

require 'mongoid'
require 'set'

require 'rcs-common/trace'

require_relative 'db_objects/evidence'
require_relative 'config'

class Indexer

  def self.run(target)
    puts "Full text search keyword indexer running..."

    # we are standalone (no rails or rack)
    ENV['MONGOID_ENV'] = 'yes'

    # set the parameters for the mongoid.yaml
    ENV['MONGOID_DATABASE'] = 'rcs'
    ENV['MONGOID_HOST'] = "127.0.0.1:27017"

    Mongoid.load!(RCS::DB::Config.instance.file('mongoid.yaml'), :production)

    puts "Connected to MongoDB at #{ENV['MONGOID_HOST']}"

    targets = []

    if target.downcase == 'all'
      targets = ::Item.targets
    else
      targets = ::Item.targets.where(name: Regexp.new(target, true))
    end

    puts "Found #{targets.count} collection to be indexed..."

    if targets.empty?
      puts "Target not found"
      return 1
    end

    targets.each_with_index do |target, index|
      puts
      puts "Indexing #{target.name} - %.0f %%" % ((index + 1) * 100 / targets.count)
      current = Evidence.target(target[:_id].to_s)
      index_collection(current)
    end

    return 0
  end

  def self.index_collection(evidence)
    chunk = 500
    cursor = 0
    count = evidence.where(:kw.exists => false).count
    puts "#{count} evidence to be indexed"

    # divide in chunks to avoid timeouts
    while cursor < count do

      evidence.where(:kw.exists => false).limit(chunk).each do |evi|
        begin
          evi[:kw] = keywordize(evi[:type], evi[:data], evi[:note])
        rescue Exception => e
          evi[:kw] = []
        end

        evi.save
      end

      cursor += chunk

      if count - cursor > 0
        print "#{count - cursor} evidence left - %.2f %%     \r" % (cursor*100/count)
      else
        puts 'done - 100 %                        '
      end
    end

  end


  def self.keywordize(type, data, note)

    # don't index those types
    return [] if ['filesystem', 'mic', 'ip'].include? type

    return keywordize_position(data, note) if type == 'position'

    kw = SortedSet.new

    data.each_value do |value|
      next unless value.is_a? String or value.is_a? Symbol
      kw += value.to_s.keywords
    end

    kw += note.keywords unless note.nil?

    kw.to_a
  end

  def self.keywordize_position(data, note)
    kw = SortedSet.new

    kw += data['latitude'].to_s.keywords unless data['latitude'].nil?
    kw += data['longitude'].to_s.keywords unless data['longitude'].nil?

    unless data['address'].nil?
      data['address'].each_value do |add|
        kw += add.keywords
      end
    end
    unless data['cell'].nil? or not data['cell'].is_a? Hash
      data['cell'].each_value do |cell|
        kw << cell.to_s
      end
    end
    unless data['wifi'].nil? or not data['wifi'].is_a? Array
      data['wifi'].each do |wifi|
        kw += [wifi['mac'].keywords, wifi['ssid'].keywords ].flatten
      end
    end

    data.each_value do |value|
      next unless value.is_a? String
      kw += value.keywords
    end

    kw += note.keywords unless note.nil?

    kw.to_a
  end

end
