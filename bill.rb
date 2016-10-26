require 'money' # Yes please

## This is the main class from which other classes will be called and new objects created
class EOS
  ## ccy must be ISO compatible currency (USD, GBP, NOK, etc)
  ## ref_start is a counter whose value is assigned to bills as a unique session reference
  ##
  ## enforce_locales should be set to false if the money 
  ## gem complains that your locale is not valid
  def initialize(ccy='GBP', enforce_locales=false, ref_start=0)
    @ccy = ccy
    @ref = ref_start
    I18n.enforce_available_locales = enforce_locales
    @bill_list = {}
    @system_total = Money.new(0, @ccy)
  end
  ## This creates a new bill within the system
  def new_bill
    increment_ref(true)
    return Bill.new(self, @ref)
  end
  ## This creates a new item within the system, which will be available to bills
  def new_item
    return Item.new(self, name, price, discount, tax=0, tags=[], price_include_vat=true)
  end
  ## Submits the bill to the systems bill list. Should be called from bill
  def submit(bill)
    @system_total += bill.subtotal
    bref = bill.bill_ref
    if @bill_list.keys.include? bref
      puts "Bill '#{bref}' has already been submitted!"
    else
      @bill_list[bref] = bill
    end
  end
  ## Increments the ref
  def increment_ref(increment)
    if increment
      @ref += 1
    else
      @ref -= 1
    end
  end
  
  private :submit
  attr_reader :bill_list, :ref, :system_total
end

class Bill
  ## eos is the parent system
  ## bill_ref is a system unique id
  def initialize(eos, bill_ref)
    @eos = eos
    @subtotal = Money.new(0, @@ccy)
    @bill_ref = bill_ref
    # items format {name: [item, quantity]}
    @items = {}
    @submitted = false
  end
  ## Adds an item to the bill.
  ## If already present increments quantity by 1
  def add_item(item)
    if @items.keys.include? item.name
      @items[item.name][1] += 1
    else
      @items[item.name] = [item, 1]
    end
    retotal()
  end
  ## Clears the content of the bill
  def reset
    @items.clear
    @subtotal -= @subtotal
  end
  ## Calculates the subtotal based on the content of @items
  def retotal
    @subtotal -= @subtotal
    @items.each do |item|
      # Check if a discount is to be applied
    end
  end
  
  def submit
    unless @submitted
      eos.submit(self.clone)
      @submitted = true
    else
      puts "This bill has already been submitted."
    end
  end
  
  attr_reader :items, :bill_ref, :subtotal, :submitted
end

# ITEM for purchase through the EOS system
#   name     - Must be a string
#   price    - Must be a floatable value
#   discount - Must be nil or an array with three integers
#                - The first integer  (x) is the quantity required to trigger the discount
#                - The second integer (y) is the discount to be applied
#                - The third integer is either - 0 - Buy x get y free (y is a quantity)
#                                              - 1 - Buy x get y off  (y is an amount in pence)
#   tax      - Must be a percentage
#   tags     - Must be a string or array of strings
class Item
  def initialize(eos, name, price, discount, tax=0, tags=[], price_include_vat=true)
    @eos = eos
    @name = name
    @price = price
    @tax = tax
    @discount = discount
    @tags = tags
    @price_include_vat = price_include_vat
    validate()
  end
  ## Turns strings into symbols
  def tosymbol(value)
    if value.methods.include? :encode
      value = value.gsub!(/\s+/,'_') || value
      value = value.downcase! || value
      value = value.to_sym
    end
    return value
  end
  ## Validate the instance variables
  def validate
    # Make tags an array if it's a string or symbol
    if @tags.methods.include? :downcase
      @tags = [@tags]
    end
    # Make all tags symbols
    @tags.map! {|tag| tosymbol(tag)}
    # Turn the name to a symbol
    @name = tosymbol(@name)
    # Make price a money object
    begin
      # Money silently turns invalid values to 0
      # so we'll check price is valid using Float
      Float(@price.gsub(',', ''))
      @price = Money.new(@price.gsub(',', ''), @eos.ccy)
    rescue
      raise Exception, "Bad value for 'price' %s" % price
    end
  end
  
  private :validate, :tosymbol
  attr_accessor :name, :price, :discount, :tax, :tags
end


