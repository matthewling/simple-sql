module Simple::SQL::Helpers::RowConverter
  SELF = self

  # returns an array of converted records
  def self.convert_row(records, into:, associations: nil)
    hsh = records.first
    return records unless hsh

    converter = if into == :struct
                  StructConverter.for(attributes: hsh.keys, associations: associations)
                else
                  TypeConverter.for(type: into, associations: associations)
                end

    records.map { |record| converter.convert_row(record) }
  end

  def self.convert(record, into:) # :nodoc:
    ary = convert_row([record], into: into)
    ary.first
  end

  class TypeConverter #:nodoc:
    def self.for(type:, associations:)
      new(type: type, associations: associations)
    end

    def initialize(type:, associations:)
      @type         = type
      @associations = associations
    end

    def convert_row(hsh)
      hsh = convert_associations(hsh) if @associations
      @type.new hsh
    end

    def convert_associations(hsh)
      updates = {}

      @associations.each do |key|
        value = hsh.fetch(key)
        case value
        when Hash   then updates[key] = SELF.convert(value, into: @type)
        when Array  then updates[key] = SELF.convert_row(value, into: @type)
        end
      end

      hsh.merge(updates)
    end
  end

  class StructConverter # :nodoc:
    def self.for(attributes:, associations:)
      @cache ||= {}
      @cache[[attributes, associations]] ||= new(attributes: attributes, associations: associations)
    end

    def initialize(attributes:, associations:)
      @attributes          = attributes
      @associations        = associations
      @association_indices = associations.map { |association| attributes.index(association) } if associations

      @klass = Struct.new(*attributes)
    end

    def convert_row(hsh)
      values = hsh.values_at(*@attributes)

      convert_associations(values) if @associations
      @klass.new(*values)
    end

    # convert values at the <tt>@association_indices</tt>.
    def convert_associations(values)
      @association_indices.each do |idx|
        value = values[idx]
        case value
        when Hash   then values[idx] = SELF.convert(value, into: :struct)
        when Array  then values[idx] = SELF.convert_row(value, into: :struct)
        end
      end
    end
  end
end
