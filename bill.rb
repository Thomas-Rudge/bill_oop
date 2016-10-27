require 'money' # Yes please

## POS
# A self contained point of sale object. From the POS object you can create sales items 
# and bills. Bills can then be submitted back to the POS object and recorded as sales
#   ccy             - The currency of the POS instance.
#   enforce_locales - Stops I18n locale not valid errors.
#   ref_start       - Where unique bill refs should start from.
#                     ## NB: The first bill will be assigned ref_start+1
#   bill_list       - A hash of bills submitted to the POS
#                     ## NB: Format {bill_ref: bill_object}
#   system_total    - The gross amount of cash in the POS (sum of all submitted bills)
class POS
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
  
  attr_reader :bill_list, :ref, :system_total, :ccy
end

## BILL
# Bills are created through the pos object. Items can be added 
# to the bill, and the bill can be submitted to the pos object.
#   pos       - The POS object that spawned the bill
#   bill_ref  - A unique bill ID issued by the POS object
#   subtotal  - Keeps track of the bill's gross value
#   tax       - Keeps track of sales tax for the bill
#   items     - A hash of item objects applied to the bill, and their quantities
#               ## NB: Format {item_name :[item_object, quantity]}
#   submitted - A flag denoting whether the bill has been passed back to the POS object
class Bill
  ## pos is the parent system
  ## bill_ref is a system unique id
  def initialize(pos, bill_ref)
    @pos = pos
    @subtotal = Money.new(0, pos.ccy)
    @tax = Money.new(0, pos.ccy)
    @bill_ref = bill_ref
    # items format {name: [item, quantity]}
    @items = {}
    @submitted = false
  end
  ## Adds an item to the bill.
  ## If already present increments quantity by 1
  def add_item(item, qty:1)
    # Clone the item so that if the base item changes later, it doesn't  imbalance 
    # the entire system (i.e. price changes wont effect bills already submitted)
    item = item.clone
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
    retotal()
  end
  ## Calculates the subtotal based on the content of @items
  def retotal
    # Reset totals
    @subtotal -= @subtotal
    @tax -= @tax
    # Iterate over the bills items, and process each one
    @items.each do |key, item|
      qty, item = item[1], item[0]
      price = item.price
      tax = item.tax / 100.00
      dsc_quantity = 0
      dsc_amount = Money.new(0, @pos.ccy)
      # If price contains vat, remove the vat
      if item.price_include_vat
        price = price / (1 + tax)
      end
      # Check if a discount is to be applied
      if item.discount && item.discount[0] >= qty
        # TO DO
      end
      # Total up price * quantity
      tax = (price * tax) * qty
      @tax += tax
      @subtotal += price * qty + tax
    end
  end
  
  ## This submits the bill to the POS object, and closes the bill
  def submit
    unless @submitted
      retotal()
      @pos.submit(self.clone)
      @submitted = true
    else
      puts "This bill has already been submitted."
    end
  end
  
  attr_reader :items, :bill_ref, :subtotal, :submitted, :tax
end

## ITEM
# Items are created through the POS object, and added to bill objects
#   pos      - The POS object that spawned the item.
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
  def initialize(pos, name, price, discount, tax, tags, price_include_vat)
    @pos = pos
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
      # This will trigger the excpetion case if the values aren't valid
      Float(@price); nil
      Float(@tax); nil
      # Money gem works in subunits, so change the price to pence
      @price = @price.to_i * Money::Currency.table[@pos.ccy.to_sym][:subunit_to_unit]
      # Now we'll turn the price into a money object, and tax into an integer
      @price = Money.new(@price, @pos.ccy)
      @tax = @tax.to_i
    rescue
      raise Exception, "Bad value for price '#{@price}' or tax '#{@tax}'"
    end
  end
  
  private :validate, :tosymbol
  attr_accessor :name, :price, :discount, :tax, :tags, :price_include_vat
end
