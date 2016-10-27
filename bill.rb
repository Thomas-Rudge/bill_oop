require 'money' # Yes please

## This is the main class from which other classes will be called and new objects created
class EOS
  ## ccy must be ISO compatible currency (USD, GBP, NOK, etc)
  ## ref_start is a counter whose value is assigned to bills as a unique session reference
  ##
  ## enforce_locales should be set to false if the money 
  ## gem complains that your locale is not valid
  def initialize(ccy='gbp', enforce_locales:false, ref_start:0)
    @ccy = ccy.downcase! || ccy
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
  def new_item(name, price, discount:false, tax:0, tags:[], price_include_vat:true)
    return Item.new(self, name, price, discount, tax, tags, price_include_vat)
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
  attr_reader :bill_list, :ref, :system_total, :ccy
end

class Bill
  ## eos is the parent system
  ## bill_ref is a system unique id
  def initialize(eos, bill_ref)
    @eos = eos
    @subtotal = Money.new(0, eos.ccy)
    @tax = Money.new(0, eos.ccy)
    @bill_ref = bill_ref
    # items format {name: [item, quantity]}
    @items = {}
    @submitted = false
  end
  ## Adds an item to the bill.
  ## If already present increments quantity by 1
  def add_item(item, qty:1)
    qty.times do
      if @items.keys.include? item.name
        @items[item.name][1] += 1
      else
        @items[item.name] = [item, 1]
      end
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
    @items.each do |key, item|
      qty, item = item[1], item[0]
      price = item.price
      tax = item.tax / 100.00
      dsc_quantity = 0
      dsc_amount = Money.new(0, @eos.ccy)
      new_total = Money.new(0, @eos.ccy)
      puts "Price #{price}", "Qty #{qty}", "Tax #{tax}"
      # Remove VAT from price if present
      if item.price_include_vat
        price = price / (1 + tax)
        puts "Repriced #{price}"
      end
      # Check if a discount is to be applied
      if item.discount && item.discount[0] >= qty
      end
      # Total up price * quantity
      tax = price * tax
      @tax += tax
      puts "New tax #{@tax}"
      @subtotal += (price * qty + tax)
    end
  end
  
  def submit
    unless @submitted
      retotal()
      @eos.submit(self.clone)
      @submitted = true
    else
      puts "This bill has already been submitted."
    end
  end
  
  attr_reader :items, :bill_ref, :subtotal, :submitted, :tax
end

# ITEM for purchase through the EOS system
#   name     - Must be a string
#   price    - Must be a floatable value
#   discount - Must be nil or an array with three integers
#                - The first integer  (x) is the quantity required to trigger the discount
#                - The second integer (y) is the discount to be applied
#                - The third integer is either - 0 - Buy x get y free (y is a quantity)
#                                              - 1 - Buy x get y off  (y is an amount in pence)
#   tax      - Must be a decimal representing a percentage e.g. 17, 17%, 11.5,etc
#   tags     - Must be a string or array of strings
class Item
  def initialize(eos, name, price, discount, tax, tags, price_include_vat)
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
    # Make price and tax money objects
    begin
      # Money silently turns invalid values to 0
      # so we'll check price is valid using Float
      @price = @price.to_s.gsub!(',', '') || @price.to_s
      @tax = @tax.to_s.gsub!('%', '') || @tax.to_s
      Float(@price); nil
      Float(@tax); nil
      @price = @price.to_i * Money::Currency.table[@eos.ccy.to_sym][:subunit_to_unit]
      @price = Money.new(@price, @eos.ccy)
      @tax = @tax.to_i
    rescue
      raise Exception, "Bad value for price '#{@price}' or tax '#{@tax}'"
    end
  end
  
  private :validate, :tosymbol
  attr_accessor :name, :price, :discount, :tax, :tags, :price_include_vat
end


