### Simple POS System

A simple POS system written in the Ruby scripting language using OOP.

####Get the dependencies.

```shell
~$ gem install money
```
&nbsp;
####Quick example
```ruby
sys = POS.new

# Create an item for use in bills
spam = system.new_item('Spam', 1.45)

# Create a new bill
bill = system.new_bill

# Add the item to the bill
bill.add_item(spam)

# Submit the bill to the POS system
bill.submit
```
&nbsp;
---
&nbsp;
####POS Object
When creating a POS object there are three optional arguments. The first argument is the systems iso currency. The default currency is GBP (British Pound).

The second, `enforce_locales`, is passed to I18n enforce_available_locales; it is set to false by default to prevent possible errors with non valid locales.

Lastly `ref_start` dictates what the reference of the first bill should be, with all proceeding bills incremented by 1. By default references start from 1.
```ruby

sys = POS.new('eur', enforce_locales:true, ref_start:50)

```
The POS object's properties can be retrieved like this...
```ruby
## sub_total is the gross amount of cash in the system (aggregate of all submitted bills).
# This returns a money object
sys.system_total
=> #<Money fractional:558 currency:EUR> 

# Use format to make it more readable
sys.system_total.format
=> "€5.58" 

# Last ref issued by the system
sys.ref
=>50
# If the POS hasn't issued any bills yet, then sys.ref will return ref_start-1

# The systems currency
sys.ccy
=> "eur"

# A hash of bills that have been submitted so far.
# The key is the bill ref, and the value is the bill object.
sys.bill_list
{50=>#<Bill:0x00000001ff56a8 @pos=#<POS:0x000000021bdc10 @ccy="eur", @ref=50, @bill_list={...}, 
@system_total=#<Money fractional:558 currency:EUR>>, @subtotal=#<Money fractional:558 currency:EUR>, 
@tax=#<Money fractional:93 currency:EUR>, @discount=#<Money fractional:310 currency:EUR>, @bill_ref=50, 
@items={:spam=>[#<Item:0x00000001ffe820 @pos=#<POS:0x000000021bdc10 @ccy="eur", @ref=50, @bill_list={...}, 
@system_total=#<Money fractional:558 currency:EUR>>, @name=:spam, @price=#<Money fractional:155 currency:EUR>, 
@tax=20.0, @discount=[1, 1, 0], @tags=[:meat, :longlife, :Pork], @price_include_vat=false>, 5]}, @submitted=false>} 


# You can get a specific bill object and its properties using the bill's reference number.
sys.bill_list[50].discount.format
=> "€1,55"
```

&nbsp;
####Item Object
An item is created by calling the POS objects `new_item` method. 
The first two arguments are mandatory, all keyword arguments are optional. The first argument should be the items name as either a string or symbol. The second argument should be the items price as an integer, float, or string.

Keyword arguments are as follows:

|kwarg|Usage|Default|
|---|---|---|
|discount|`[Threshold, Discount, Type]` where **Threshold** is the quantity of the item required to trigger the discount; **Discount** is the amount deducted; and **Type** is the type of discount deducted.<br/><br/>**Type** can either be `0` (Buy x get y free) _or_ `1` (By x get y off). The first type would make **Discount** a quantity of the item that would be free, and the second type would make **Discount** an amount to be deducted.<br/><br/>Examples:-<br/>`[1, 1, 0]` - Buy 1 get 1 free.<br/>`[3, 0.5, 1]` - Buy 3 get 50 pence off.|nil|
|tax|Determines the tax (VAT) applied to the item when added to a bill. The value can be an integer, float, or string; e.g. 10, 10.00, "10%"|0|
|tags|Tags are non-functional, and are just present to help search and categorise items within the system.|[ ]|
|price_include_vat|Set to `true` if the price passed to the item is inclusive of VAT, else false.|true|

```ruby
# Create a new item object called spam
spam = sys.new_item('Spam', 1.45, 
  discount:[1, 1, 0], 
  tax:20, 
  tags:['Meat', 'Longlife'], 
  price_include_vat:false
  )
=> #<Item:0x00000001556008 @pos=#<POS:0x00000001665f20 @ccy="eur", @ref=49, @bill_list={}, 
@system_total=#<Money fractional:0 currency:EUR>>, @name=:spam, @price=#<Money fractional:145 
currency:EUR>, @tax=20.0, @discount=[1, 1, 0], @tags=[:meat, :longlife], @price_include_vat=false>

# You can access and change any of the item's properties set at instantiation.
# NB: Changes to items will not affect instances of that item stored in bills.

spam.price.format
=> "€1,45"

spam.price = Money.new(155, 'eur')

spam.price.format
=> "€1,55"

spam.tags << "pork"
=> [:meat, :longlife, :pork]

spam.price_include_vat?
=> false

```
&nbsp;
####Bill Object
A bill is created through the POS object using the `new_bill` method. Items are added to bills using the bill's `add_item` method.

```ruby
bill = sys.new_bill
=> #<Bill:0x000000020b5b10 @pos=#<POS:0x000000021bdc10 @ccy="eur", @ref=50, @bill_list={}, 
@system_total=#<Money fractional:0 currency:EUR>>, @subtotal=#<Money fractional:0 currency:EUR>, 
@tax=#<Money fractional:0 currency:EUR>, @discount=#<Money fractional:0 currency:EUR>, @bill_ref=50, 
@items={}, @submitted=false> 

# Add an item to the bill. `qty` is an optional keyword, default value is 1
bill.add_item(spam, qty:3)

# You can access various properties of the bill
bill.subtotal.format
=> "€3,72"

bill.discount.format
=> "€1,55"

# This returns a hash of items present in the bill.
# The format of the hash is: {item_name: [item_object, quantity]}
bill.items
=> {:spam=>[#<Item:0x0000000209eb40 @pos=#<POS:0x000000021bdc10 @ccy="eur", @ref=50, @bill_list={}, 
@system_total=#<Money fractional:0 currency:EUR>>, @name=:spam, @price=#<Money fractional:155 
currency:EUR>, @tax=20.0, @discount=[1, 1, 0], @tags=[:meat, :longlife, :Pork], 
@price_include_vat=false>, 3]} 

bill.ref
=> 50

bill.tax.format
=> "€0,62"

# You can force the bill to retotal
bill.retotal

# You can reset a bill to clear it of contents.
bill.reset
=> {}
```

Submitting a bill object to the POS

```ruby
# Lets add something to the bill (since we just reset it).
bill.add_item(spam, qty:5)

# This will pass the bill object to the POS object.
bill.submit
=> true

# You can only submit a bill once
bill.submit
This bill has already been submitted.
 => nil

# You can see whether a bill has been submitted by checking its `submitted` property
bill.submitted?
=> true

# Or you can check the POS object to see if the bill is included in the bill list
sys.bill_list.include? 50
=> true

```
