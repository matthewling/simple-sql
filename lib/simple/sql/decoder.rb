require "time"

# private
module Simple::SQL::Decoder
  extend self

  def new(result, into:)
    if into == Hash           then HashRecord.new(result)
    elsif into == :struct     then StructRecord.new(result)
    elsif into                then Record.new(result, into: into)
    elsif result.nfields == 1 then SingleColumn.new(result)
    else                           MultiColumns.new(result)
    end
  end

  def parse_timestamp(s)
    r = ::Time.parse(s)
    return r if r.utc_offset == 0
    Time.gm(r.year, r.mon, r.day, r.hour, r.min, r.sec)
  end

  # rubocop:disable Metrics/AbcSize
  # rubocop:disable Metrics/CyclomaticComplexity
  # rubocop:disable Metrics/MethodLength
  def decode_value(type, s)
    case type
    when :unknown                       then s
    when :"character varying"           then s
    when :integer                       then Integer(s)
    when :bigint                        then Integer(s)
    when :numeric                       then Float(s)
    when :"double precision"            then Float(s)
    when :'integer[]'                   then s.scan(/-?\d+/).map { |part| Integer(part) }
    when :"character varying[]"         then parse_pg_array(s)
    when :"text[]"                      then parse_pg_array(s)
    when :"timestamp without time zone" then parse_timestamp(s)
    when :hstore                        then HStore.parse(s)
    when :json                          then ::JSON.parse(s)
    when :jsonb                         then ::JSON.parse(s)
    when :boolean                       then s == "t"
    else
      # unknown value, we just return the string here.
      # STDERR.puts "unknown type: #{type.inspect}"
      s
    end
  end
  # rubocop:enable Metrics/AbcSize
  # rubocop:enable Metrics/CyclomaticComplexity
  # rubocop:enable Metrics/MethodLength

  require "pg_array_parser"
  extend PgArrayParser

  # HStore parsing
  module HStore
    module_function

    # thanks to https://github.com/engageis/activerecord-postgres-hstore for regexps!

    QUOTED_LITERAL    = /"[^"\\]*(?:\\.[^"\\]*)*"/
    UNQUOTED_LITERAL  = /[^\s=,][^\s=,\\]*(?:\\.[^\s=,\\]*|=[^,>])*/
    LITERAL           = /(#{QUOTED_LITERAL}|#{UNQUOTED_LITERAL})/
    PAIR              = /#{LITERAL}\s*=>\s*#{LITERAL}/
    NULL              = /\ANULL\z/i
    DOUBLE_QUOTE      = '"'.freeze
    ESCAPED_CHAR      = /\\(.)/

    def parse(hstore)
      hstore.scan(PAIR).each_with_object({}) do |(k, v), memo|
        k = unpack(k)
        k = k.to_sym
        v = v =~ NULL ? nil : unpack(v)
        memo[k] = v
      end
    end

    def unpack(string)
      string = string[1..-2] if string[0] == DOUBLE_QUOTE # remove quotes, if any
      string.gsub ESCAPED_CHAR, '\1'                      # unescape, if necessary
    end
  end
end

class Simple::SQL::Decoder::SingleColumn
  def initialize(result)
    typename = ::Simple::SQL.send(:resolve_type, result.ftype(0), result.fmod(0))
    @field_type = typename.to_sym
  end

  def decode(row)
    value = row.first
    value && Simple::SQL::Decoder.decode_value(@field_type, value)
  end
end

class Simple::SQL::Decoder::MultiColumns
  def initialize(result)
    @field_types = 0.upto(result.fields.length - 1).map do |idx|
      typename = ::Simple::SQL.send(:resolve_type, result.ftype(idx), result.fmod(idx))
      typename.to_sym
    end
  end

  def decode(row)
    @field_types.zip(row).map do |field_type, value|
      value && Simple::SQL::Decoder.decode_value(field_type, value)
    end
  end
end

class Simple::SQL::Decoder::HashRecord < Simple::SQL::Decoder::MultiColumns
  def initialize(result)
    super(result)
    @field_names = result.fields.map(&:to_sym)
  end

  def decode(row)
    decoded_row = super(row)
    Hash[@field_names.zip(decoded_row)]
  end
end

class Simple::SQL::Decoder::Record < Simple::SQL::Decoder::HashRecord
  def initialize(result, into:)
    super(result)
    @into = into
  end

  def decode(row)
    @into.new(super)
  end
end

class Simple::SQL::Decoder::StructRecord < Simple::SQL::Decoder::MultiColumns
  @@struct_cache = {}

  def initialize(result)
    super(result)

    field_names = result.fields.map(&:to_sym)
    @into = @@struct_cache[field_names] ||= Struct.new(*field_names)
  end

  def decode(row)
    decoded_row = super(row)
    @into.new(*decoded_row)
  end
end
