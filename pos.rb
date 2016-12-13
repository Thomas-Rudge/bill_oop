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

  attr_reader :bill_list, :ref, :system_total, :ccy

  def initialize(ccy='gbp', enforce_locales:false, ref_start:1)
    @ccy = ccy.downcase
    @ref = ref_start-1
    @bill_list = {}

    I18n.enforce_available_locales = enforce_locales

    @system_total = Money.new(0, @ccy)
  end
  ## This creates a new bill within the system
  def new_bill
    @ref += 1
    return Bill.new(self, @ref)
  end
  ## This creates a new item within the system, which will be available to bills
  def new_item(name, price, discount:false, tax:0, tags:[], price_include_vat:true)
    return Item.new(self, name, price, discount, tax, tags, price_include_vat)
  end
  ## Submits the bill to the systems bill list. Should be called from bill
  def submit(bill)
    @system_total += bill.subtotal
    bref           = bill.bill_ref

    if @bill_list.keys.include? bref
      puts "Bill '#{bref}' has already been submitted!"
    else
      @bill_list[bref] = bill
    end
  end
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

  attr_reader :items, :bill_ref, :subtotal, :submitted, :tax, :discount
  alias_method :submitted?, :submitted
  ## pos is the parent system
  ## bill_ref is a system unique id
  def initialize(pos, bill_ref)
    @pos       = pos
    @subtotal  = Money.new(0, pos.ccy)
    @tax       = Money.new(0, pos.ccy)
    @discount  = Money.new(0, pos.ccy)
    @bill_ref  = bill_ref
    @items     = {}
    @submitted = false
  end
  ## Adds an item to the bill.
  ## If already present increments quantity by 1
  def add_item(item, qty:1)
    # Clone the item so that if the base item changes later, it doesn't  imbalance
    # the entire system (i.e. price changes wont effect bills already submitted)
    unless @submitted
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
  end
  ## Clears the content of the bill
  def reset
    unless submitted
      @items.clear
      retotal()
    end
  end
  ## Calculates the subtotal based on the content of @items
  def retotal
    # Reset totals
    @subtotal -= @subtotal
    @tax      -= @tax
    @discount -= @discount
    # Iterate over the bills items, and process each one
    @items.each do |key, item|
      qty, item = item[1], item[0]
      price     = item.price.cents
      tax       = item.tax
      # If price contains vat, remove the vat
      if item.price_include_vat
        price = (price*100) / (tax+100)
      end
      # Check if a discount is to be applied
      dscnt = discounter(item.discount, qty, price)
      # Total everything up
      price = (price * qty) - dscnt
      tax   = (price / BigDecimal.new(100, 2) * tax)

      @discount += Money.new(dscnt, @pos.ccy)
      @tax      += Money.new(tax, @pos.ccy)
      @subtotal += Money.new(price + tax, @pos.ccy)
    end
  end

  ## This calculates the discount values
  def discounter(discount, quantity, i_price)
    # Discount is always applied before tax
    d_amount = d_qty = 0

    if discount && discount[2] == 0 && (discount[0] + discount[1]) <= quantity
      # Quantity discount
      # tot is the total items used in a single discount
      tot      = discount[0] + discount[1]
      d_qty    = (quantity / tot).floor
      d_amount = i_price
    elsif discount && discount[2] == 1 && discount[0] <= quantity
      # Money discount
      d_qty    = (quantity / discount[0]).floor
      d_amount = discount[1] * Money::Currency.table[@pos.ccy.to_sym][:subunit_to_unit]
    end

    return d_amount * d_qty
  end

  ## This submits the bill to the POS object, and closes the bill
  def submit
    unless @submitted
      retotal()
      @submitted = true
      @pos.submit(self.clone)
    else
      puts "This bill has already been submitted."
    end
  end

  private :discounter

end

## ITEM
# Items are created through the POS object, and added to bill objects
#   pos      - The POS object that spawned the item.
#   name     - Must be a string
#   price    - Must be a floatable value
#   discount - Must be nil or an array with three values
#                - The first value  (x) is the quantity required to trigger the discount
#                - The second value (y) is the discount to be applied
#                - The third value is either - 0 - Buy x get y free (y is a quantity)
#                                              - 1 - Buy x get y off  (y is an amount in pence)
#   tax      - Must be a decimal representing a percentage e.g. 17, 17%, 11.5,etc
#   tags     - Must be a string or array of strings
class Item
  attr_reader :name, :price, :tax, :discount, :tags, :price_include_vat
  alias_method :price_include_vat?, :price_include_vat

  def initialize(pos, name, price, discount, tax, tags, price_include_vat)
    @pos = pos
    @name = name
    @price = price
    @tax = tax
    @discount = discount
    @tags = tags
    @price_include_vat = price_include_vat

    item = self
    @tags.define_singleton_method(:<<) do |val|
      push(item.tosymbol(val))
    end

    validate()
  end
  # Validate values with custom setters
  def price=(val)
    @price = val
    check_price
  end
  def tax=(val)
    @tax = val
    check_tax
  end
  def discount=(val)
    @discount = val
    check_discount
  end
  def tags=(val)
    @tags = val
    check_tags
  end
  def price_include_vat=(val)
    @price_include_vat = val
    check_vat_flag
  end
  ## Turns strings into symbols
  def tosymbol(value)
    value = value.to_s
    value = value.gsub!(/\s+/,'_') || value
    value = value.downcase

    return value.to_sym
  end
  ## Validate the instance variables
  def validate
    check_name
    check_price
    check_tax
    check_discount
    check_tags
    check_vat_flag
  end
  # This will turn the name into a symbol
  def check_name
    @name = tosymbol(@name)
  end
  # This will check the price and turn it into a money object
  def check_price
    if @price.is_a? Money
      if @price.currency.id != @pos.ccy.to_sym
        @price = Money.new(@price.fractional, @pos.ccy)
      end
    elsif @price.is_a? Numeric
      # Money gem works in subunits, so change the price to pence
      @price = BigDecimal.new(@price.to_s)
      @price = (@price * Money::Currency.table[@pos.ccy.to_sym][:subunit_to_unit]).to_i
      @price = Money.new(@price, @pos.ccy)
    else
      puts "#{@name}: Bad value for discount #{@price}"
      @price = Money.new(0, @pos.ccy)
    end
  end
  # This will check the tax variable and turn it into a float
  def check_tax
    flg = @tax == 0 ? true : @tax
    @tax = @tax.to_s.to_f || 0.0
    if flg != true && @tax == 0
      puts "#{@name}: Bad value for tax #{flg}"
    end
  end
  # This will check that the discount is an array of numbers
  def check_discount
    if @discount &&
       (@discount.length != 3 ||
       (!@discount[0].is_a? Integer) ||
       (!@discount[1].is_a? Numeric) ||
       (![0,1].include? @discount[2]))
      puts "#{@name}: Bad value for discount #{@discount}"
      @discount = false
    end
  end
  # This will make any tags symbols
  def check_tags
    if @tags.is_a? Array
      @tags.map! {|tag| tosymbol(tag)}
    else
      @tags = [tosymbol(@tags.to_s)]
    end
  end
  # This will check the VAT flag is a bool
  def check_vat_flag
    if ![true, false].include? @price_include_vat
      puts "#{@name}: Bad value for VAT flag #{@price_include_vat}"
      @price_include_vat = true
    end
  end

  private :validate, :check_name, :check_price, :check_discount
  private :check_tax, :check_tags, :check_vat_flag
end
